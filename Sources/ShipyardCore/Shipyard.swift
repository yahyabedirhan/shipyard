import Foundation
import Observation

/// The orchestrator: owns the lifecycle phase and handles the user's actions.
/// The app builds one with its adapters and the panel draws from it.
///
/// It signs in (a stored or `gh` token, else the device flow), signs out on
/// any 401, follows the configuration between `needsProjects` and `ready`,
/// and in `ready` runs the refresh pipeline: fetch every project's items in
/// one GraphQL request, find the events since the last refresh and post the
/// ones the notification rules select, publish the menu model (with which
/// rows need attention), and ask the rate budget when to run next. What the
/// user has seen and collapsed, the items it knew and the events it notified
/// are app state, kept by `appStateStore`. The pings agents send are kept by
/// `pingStore` and listed with the projects' items, without GitHub; the
/// pings of the remote machines (`[remote] machines`) are polled through
/// Herdr on a timer of their own (`pollMachines()`) and listed with them.
/// Observable, so the panel redraws when what it reads changes.
@MainActor
@Observable
public final class Shipyard {
    /// What signing out left behind.
    public enum SignOutResult: Equatable, Sendable {
        /// The token store is cleared and nothing else holds a token.
        case signedOut
        /// The token came from `gh`, which is still signed in: shipyard picks
        /// it up again at the next launch unless the user runs `gh auth logout`.
        case ghStillSignedIn
    }

    /// Why shipyard is signed out, so the connect screen can say what to do.
    public enum SignedOutReason: Equatable, Sendable {
        /// Neither the token store nor `gh` had a token: `gh` isn't
        /// installed or isn't signed in.
        case noToken
        /// GitHub rejected the token from this source (401): revoked or expired.
        case rejected(TokenSource)
        /// The user signed out; the result says whether `gh` still holds a token.
        case userSignedOut(SignOutResult)
    }

    /// Where shipyard is in its lifecycle.
    public private(set) var phase: Phase = .signedOut
    /// Where the current token came from; `nil` when signed out.
    public private(set) var tokenSource: TokenSource?
    /// The signed-in account, once GitHub has told us; `nil` when signed out
    /// or when GitHub couldn't be reached yet.
    public private(set) var viewer: Viewer?
    /// Why the last device flow ended without signing in (for example
    /// `.expired`); cleared when a new one begins. `nil` after a cancel.
    public private(set) var signInError: DeviceFlowError?
    /// Why shipyard is signed out, for the connect screen; `nil` while signed
    /// in, and while `start()` is still looking for a token.
    public private(set) var signedOutReason: SignedOutReason?

    /// What the panel draws. A failed refresh keeps the rows and sets
    /// `fetchError` and the time they were last updated.
    public private(set) var menu = MenuModel.empty
    /// The groups Show more revealed past their `show-first` cap, until
    /// Show less or the menu closes (`panelClosed()`); never saved.
    public private(set) var expandedGroups: Set<GroupID> = []
    /// The last refresh that succeeded; `nil` before one did.
    public private(set) var snapshot: Snapshot?
    /// The pings in the ping store, as last read: at start and whenever the
    /// store changes (`reloadPings()`).
    public private(set) var pings: [Ping] = []
    /// What each remote machine (`[remote] machines`) last listed, and how
    /// its latest poll went (`pollMachines()`).
    public private(set) var remote = RemoteMachines()
    /// How often the remote machines are polled, apart from the refresh.
    public static let machinePollInterval: TimeInterval = 30
    /// The notifications of pings that left (withdrawn, dismissed, past
    /// their seen-window), still to take out of Notification Center
    /// (`removeLeftBanners()`).
    private var leftBanners: [String] = []
    /// Why the latest refresh failed; `nil` once one succeeds.
    public private(set) var fetchError: GitHubError?
    /// Whether a refresh is running now.
    public var isRefreshing: Bool { gate.isRunning }
    /// Why the configuration file was rejected, for the panel's banner;
    /// `nil` while it reads cleanly. Shipyard keeps running on the last
    /// valid configuration meanwhile.
    public private(set) var configError: ConfigError?
    /// Unknown settings the last clean read ignored, and old forms it read,
    /// for the panel's quiet banner; empty when there are none or the latest
    /// read failed.
    public private(set) var configWarnings: [ConfigIssue] = []
    /// The presets onboarding offers as its first step: all of them while
    /// the file holds nothing but `version` (missing, or the app's header);
    /// none once it has other settings, when onboarding shows the plain
    /// project picker instead. Follows every reload.
    public private(set) var presets: [Preset] = Preset.all
    /// What the rate budget knows: limits, recent costs, a pause.
    public private(set) var budget = RateBudget()
    /// Whether ⌘R may refresh now: false only while the rate budget pauses
    /// refreshing (the menu model says why).
    public var canRefreshNow: Bool { budget.canRefresh(at: clock.now) }

    public let configStore: ConfigStore
    /// Seen items and collapsed projects, in `state.json`.
    public let appStateStore: AppStateStore
    /// The verdict on the configuration file after each reload, in
    /// `config-status.json`, for agents that can't see the banner.
    public let configStatusStore: ConfigStatusStore
    /// The pings agents send with the `shipyard` CLI, which writes to the
    /// same store.
    public let pingStore: PingStore
    /// Each project's repositories as last resolved, for the `shipyard` CLI
    /// to file a ping by its repository without calling GitHub.
    public let repositoriesStore: ResolvedRepositoriesStore
    private let tokenStore: any TokenStore
    private let actions: any ActionRunning
    private let herdr: HerdrFocus
    private let remoteReader: RemotePingReader
    /// Polls the remote machines, apart from `timer`: no GitHub request.
    private let machineTimer: any RefreshTimer
    /// One poll of the remote machines at a time; a call meanwhile (an
    /// edit adding a machine, ⌘R) makes one more run after it.
    @ObservationIgnored private var machineGate = RefreshGate()
    private let notifier: any Notifying
    private let loginItem: any LoginItem
    private let timer: any RefreshTimer
    private let clock: any WallClock
    private var gate = RefreshGate()
    private let tokenProvider: TokenProvider
    private let deviceFlow: DeviceFlow
    /// Whether the build has an OAuth App client ID, so the device flow can start.
    public let canSignInWithGitHub: Bool
    private let transport: any HTTPTransport

    /// The client for the current token; `nil` when signed out.
    private(set) var github: GitHubClient?
    @ObservationIgnored private var deviceFlowTask: Task<Void, Never>?
    /// Bumped whenever a device flow begins or is cancelled, so a flow that
    /// was cancelled can't change anything when it finishes.
    @ObservationIgnored private var deviceFlowGeneration = 0
    /// Bumped whenever a token is taken up or dropped, so an answer to a
    /// request made with an earlier token can't sign in or out.
    @ObservationIgnored private var session = 0
    /// What the projects' repository groups and `owner/*` stand for,
    /// looked up at most hourly.
    @ObservationIgnored private let resolver = RepositoryResolver()
    /// Whether the next refresh looks every group and `owner/*` up again,
    /// whatever their age: at launch, after a configuration change, on ⌘R
    /// and after signing in again.
    @ObservationIgnored private var forceResolve = true

    public init(
        configStore: ConfigStore,
        appStateStore: AppStateStore,
        configStatusStore: ConfigStatusStore,
        pingStore: PingStore,
        repositoriesStore: ResolvedRepositoriesStore,
        tokenStore: any TokenStore,
        actions: any ActionRunning,
        notifier: any Notifying,
        loginItem: any LoginItem,
        gh: any GhTokenLookup = GhCLI(),
        herdr: HerdrFocus = HerdrFocus(),
        remote: RemotePingReader = RemotePingReader(),
        transport: any HTTPTransport = URLSessionTransport(),
        clock: any WallClock = SystemClock(),
        timer: any RefreshTimer = TaskRefreshTimer(),
        machineTimer: any RefreshTimer = TaskRefreshTimer(),
        sleep: @escaping Sleep = systemSleep,
        oauthClientID: String = OAuthApp.clientID
    ) {
        self.configStore = configStore
        self.appStateStore = appStateStore
        self.configStatusStore = configStatusStore
        self.pingStore = pingStore
        self.repositoriesStore = repositoriesStore
        self.tokenStore = tokenStore
        self.actions = actions
        self.herdr = herdr
        self.remoteReader = remote
        self.machineTimer = machineTimer
        self.notifier = notifier
        self.loginItem = loginItem
        self.clock = clock
        self.timer = timer
        self.tokenProvider = TokenProvider(store: tokenStore, gh: gh)
        self.deviceFlow = DeviceFlow(clientID: oauthClientID, transport: transport, clock: clock, sleep: sleep)
        self.canSignInWithGitHub = OAuthApp.isSet(oauthClientID)
        self.transport = transport
    }

    /// Loads the app state and the configuration, registers or removes the
    /// login item as `launch-at-login` says, and signs in with the token
    /// store's token or `gh`'s, if either has one; otherwise stays signed
    /// out. Signing in with projects runs the first refresh.
    ///
    /// A missing configuration file is created first, with its commented
    /// header, on every start, not only the first; one that exists is never
    /// touched.
    public func start() async {
        signedOutReason = nil
        appStateStore.load(at: clock.now)
        createConfigurationIfMissing()
        configStore.reload()
        publishConfigStatus()
        // Pings sent while the app wasn't running list and notify now,
        // signed in or not, without waiting for GitHub.
        await reloadPings()
        // So do the remote machines' pings, from their first poll.
        followMachines()
        // A file broken since launch has no valid configuration behind it,
        // only the defaults: leave the login item as it is until it's fixed.
        if configError == nil { followLaunchAtLogin() }
        let provider = tokenProvider
        // `gh auth token` spawns a process; keep it off the main actor.
        let found = await Task.detached { provider.current() }.value
        guard let found else {
            apply(.signedOut)
            signedOutReason = .noToken
            return
        }
        await connect(with: found)
    }

    // MARK: - Device flow

    /// Starts the device flow: requests a code, moves to `connecting` with it,
    /// and polls until the user approves. On success the token is saved to the
    /// token store and shipyard signs in; on expiry, denial or failure it
    /// returns to `signedOut` with `signInError` set, ready to begin again.
    /// Only starts from `signedOut`; while one runs, returns that one.
    @discardableResult
    public func beginDeviceFlow() -> Task<Void, Never> {
        if let deviceFlowTask { return deviceFlowTask }
        guard phase == .signedOut else { return Task {} }
        signInError = nil
        deviceFlowGeneration += 1
        let generation = deviceFlowGeneration
        let task = Task { await self.runDeviceFlow(generation) }
        deviceFlowTask = task
        return task
    }

    /// Stops a running device flow and returns to `signedOut`.
    public func cancelDeviceFlow() {
        guard let task = deviceFlowTask else { return }
        deviceFlowGeneration += 1
        deviceFlowTask = nil
        task.cancel()
        apply(.deviceFlowCancelled)
    }

    /// Opens the page the device flow's code is entered on (github.com/login/device),
    /// while the code shows; otherwise does nothing.
    public func openVerificationPage() {
        guard case .connecting(let code) = phase else { return }
        actions.open(code.verificationURL)
    }

    private func runDeviceFlow(_ generation: Int) async {
        do {
            let authorization = try await deviceFlow.requestCode()
            guard generation == deviceFlowGeneration else { return }
            apply(.deviceFlowStarted(authorization.code))

            let token = try await deviceFlow.waitForToken(authorization)
            guard generation == deviceFlowGeneration else { return }
            deviceFlowTask = nil
            // A token the store can't keep still works until the app quits.
            try? tokenStore.save(token)
            await connect(with: FoundToken(value: token, source: .tokenStore))
        } catch {
            guard generation == deviceFlowGeneration else { return }
            deviceFlowTask = nil
            if error is CancellationError {
                signInError = nil
            } else {
                signInError = (error as? DeviceFlowError) ?? .network(error.localizedDescription)
            }
            apply(.deviceFlowCancelled)
        }
    }

    // MARK: - Signing in and out

    /// Signs in with `found`: asks GitHub who the token belongs to, then moves
    /// on to the picker or the projects. A 401 signs out instead; an
    /// unreachable GitHub still signs in and leaves `viewer` for later.
    private func connect(with found: FoundToken) async {
        session += 1
        let current = session
        github = GitHubClient(token: found.value, transport: transport)
        tokenSource = found.source
        let viewer: Viewer?
        do {
            viewer = try await request { try await $0.viewer() }
        } catch GitHubError.unauthorized {
            return
        } catch {
            viewer = nil
        }
        guard current == session else { return }
        self.viewer = viewer
        signedOutReason = nil
        apply(.signedIn(hasProjects: configStore.lastValid.hasProjects))
        await refresh()
    }

    /// Runs `body` with the current client. Every request to GitHub's API goes
    /// through here, so a 401 from any of them signs out.
    func request<T>(_ body: (GitHubClient) async throws -> T) async throws -> T {
        guard let github else { throw GitHubError.unauthorized }
        let current = session
        do {
            return try await body(github)
        } catch GitHubError.unauthorized {
            if current == session { signOutAfterUnauthorized() }
            throw GitHubError.unauthorized
        }
    }

    /// GitHub rejected the token: forget it, and drop it from the token store
    /// when it came from there, so the next start can fall back to `gh`.
    private func signOutAfterUnauthorized() {
        // A request only runs with a token, so the source is set; were it
        // not, dropping the stored token is the safe side.
        let source = tokenSource ?? .tokenStore
        if source == .tokenStore { try? tokenStore.delete() }
        endSession()
        signedOutReason = .rejected(source)
    }

    /// Clears the token store and returns to `signedOut`. When the token came
    /// from `gh`, says so, so the connect screen can offer Connect with gh.
    @discardableResult
    public func signOut() -> SignOutResult {
        cancelDeviceFlow()
        let source = tokenSource
        try? tokenStore.delete()
        signInError = nil
        endSession()
        let result: SignOutResult = source == .gh ? .ghStillSignedIn : .signedOut
        signedOutReason = .userSignedOut(result)
        return result
    }

    private func endSession() {
        session += 1
        github = nil
        tokenSource = nil
        viewer = nil
        snapshot = nil
        fetchError = nil
        menu = .empty
        budget = RateBudget()
        // Another account reaches other repositories.
        resolver.reset()
        forceResolve = true
        timer.disarm()
        apply(.signedOut)
    }

    // MARK: - Configuration

    /// Reads the configuration file again and follows it: a change with
    /// projects moves to `ready` and refreshes, one without moves to
    /// `needsProjects` and stops the timer. A rejected edit changes nothing
    /// (the store keeps the last valid configuration and its error). The
    /// app's configuration watcher calls this.
    @discardableResult
    public func reloadConfiguration() async -> ConfigStore.ReloadResult {
        let result = configStore.reload()
        await follow(result)
        return result
    }

    /// Moves the phase with a reload's result, rebuilds the menu from the
    /// last snapshot and refreshes (or stops the timer). Only a valid change
    /// moves anything.
    private func follow(_ result: ConfigStore.ReloadResult) async {
        publishConfigStatus()
        if case .changed(let configuration) = result {
            // New selectors, or `archived` and `forks` changed: look them up now.
            forceResolve = true
            followLaunchAtLogin()
            followMachines()
            apply(.configurationChanged(hasProjects: configuration.hasProjects))
            // Projects, filters, `[attention]` and `[menu-bar]` apply at
            // once, even if the refresh below can't run (paused) or fails.
            rebuildMenu(configuration)
            if phase.canRefresh {
                // So does `[rate-limit]`: the delay and the indicator follow
                // the new share and `show` from the limits already heard,
                // rather than wait for the refresh to come back.
                publishRateStatus()
                await refresh()
            } else {
                timer.disarm()
            }
        }
    }

    /// Publishes the latest reload's verdict: `configError` and
    /// `configWarnings` for the panel's banners, and the same in
    /// `config-status.json` for agents. Every reload comes through here,
    /// accepted, rejected or unchanged.
    private func publishConfigStatus() {
        configError = configStore.error
        configWarnings = configStore.warnings
        presets = configStore.acceptsPreset ? Preset.all : []
        configStatusStore.record(ConfigStatus(
            checked: clock.now,
            config: configStore.url,
            configModified: configStore.modified,
            error: configError,
            warnings: configWarnings
        ))
    }

    /// Registers or removes the login item to match `launch-at-login` in
    /// the last valid configuration: at start, and on every valid change,
    /// so an edit applies at once. The login item ignores a repeat.
    private func followLaunchAtLogin() {
        loginItem.setEnabled(configStore.lastValid.launchAtLogin)
    }

    // MARK: - Project picker

    /// The repositories the picker suggests: the viewer's own and those they
    /// contributed to, most recently pushed first, without archived ones.
    /// Throws `GitHubError` when GitHub can't answer (a 401 also signs out;
    /// a spent rate limit also pauses refreshing).
    public func suggestedRepositories() async throws -> [RepoSummary] {
        let now = clock.now
        do {
            return try await request { try await $0.recentRepositories(at: now) }
        } catch {
            recordLimit(error)
            throw error
        }
    }

    /// Checks a repository the user typed (`owner/name`, or a github.com
    /// link to one) against GitHub before the picker accepts it. Accepted
    /// repositories carry GitHub's spelling of the name; a rejection says why.
    public func checkRepository(_ text: String) async -> RepositoryCheck {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let slug = RepositoriesQuery.slug(from: typed) else { return .rejected(.notASlug(typed)) }
        do {
            return .accepted(try await request { try await $0.repository(slug) })
        } catch GitHubError.http(404) {
            return .rejected(.notFound(slug))
        } catch GitHubError.http(403) {
            return .rejected(.forbidden(slug))
        } catch {
            recordLimit(error)
            let failure = (error as? GitHubError) ?? .network(error.localizedDescription)
            return .rejected(.couldNotCheck(slug, failure))
        }
    }

    /// Writes the picker's choices to the configuration file, one
    /// `[[projects]]` block each, appended after whatever is there, and
    /// follows the reload that comes after: with projects, the phase moves
    /// to `ready` and the first refresh runs, without a restart. Throws a
    /// `ConfigError` (and writes nothing) for an empty name, a name already
    /// used, a project without repositories or a slug that isn't
    /// `owner/name`; throws the file system's error when it can't write.
    @discardableResult
    public func addProjects(_ projects: [NewProject]) async throws -> ConfigStore.ReloadResult {
        let result = try configStore.append(projects: projects)
        await follow(result)
        return result
    }

    /// Onboarding's first step: writes `preset`'s whole file, with
    /// `projects` as the repositories picked for it (none for
    /// `review-queue`, or for `incoming-contributions` watching `owned`), and
    /// follows the reload like `addProjects`: the phase moves to `ready` and
    /// the first refresh runs, without a restart. Throws a `ConfigError`
    /// (and writes nothing) when the file already holds settings besides
    /// `version`, which also stops offering presets, or when a project is
    /// invalid; throws the file system's error when it can't write.
    @discardableResult
    public func choosePreset(_ preset: Preset, projects: [NewProject] = []) async throws -> ConfigStore.ReloadResult {
        let result: ConfigStore.ReloadResult
        do {
            result = try configStore.writePreset(preset, projects: projects)
        } catch let error as ConfigError where error == Configuration.presetRefused {
            // The file changed since the last reload: read it, so the panel
            // shows the plain picker.
            await reloadConfiguration()
            throw error
        }
        await follow(result)
        return result
    }

    // MARK: - Layout button

    /// The header's layout button: writes the layout after the current one
    /// (`MenuLayout.next`, wrapping) to `[menu] layout` in the configuration
    /// file and follows the reload, so the menu switches as it does for a
    /// hand edit. When the file can't be written (it doesn't read, `[menu]`
    /// is in a form the writer doesn't edit, or the file system refuses),
    /// nothing changes and `configError` says why until the next reload.
    public func switchToNextLayout() async {
        let next = configStore.lastValid.menu.layout.next
        do {
            await follow(try configStore.setLayout(next))
        } catch let error as ConfigError {
            configError = error
        } catch {
            configError = ConfigError([ConfigIssue(line: nil, message: "can't switch the layout: \(error.localizedDescription)")])
        }
    }

    /// A limit the picker ran into holds refreshes back too: it's the same limit.
    private func recordLimit(_ error: any Error) {
        guard let error = error as? GitHubError else { return }
        budget.record(error, at: clock.now)
    }

    // MARK: - Refreshing

    /// Fetches every project's items and publishes the menu model. The timer,
    /// ⌘R, waking and a configuration change all come here.
    /// It lists the pings again first, so a seen ping whose window has
    /// passed leaves even while signed out; outside `ready` that's all it
    /// does. One refresh runs at a time: a call while
    /// one runs returns at once and the running one goes again when it's done
    /// (several calls meanwhile make one more run). Afterwards the timer is
    /// armed for the next one, as the rate budget says. While the budget
    /// pauses refreshing (a limit ran out, or a secondary limit), nothing is
    /// sent: the menu is listed again from the last snapshot, so a closed
    /// item whose window has passed leaves, and the timer comes back after
    /// the configured interval, or at the end of the pause when that's sooner.
    public func refresh() async {
        // A seen ping whose seen-window has passed leaves the store too,
        // and its notification Notification Center, signed in or not.
        listPings()
        await removeLeftBanners()
        guard phase.canRefresh else { return }
        guard canRefreshNow else {
            if !gate.isRunning {
                rebuildMenu(configStore.lastValid)
                armTimer()
            }
            return
        }
        guard gate.begin() else { return }
        while true {
            await performRefresh()
            guard gate.finish() else { break }
            guard phase.canRefresh, canRefreshNow, gate.begin() else { break }
        }
        armTimer()
    }

    /// The Refresh button (⌘R): creates the configuration file with its
    /// commented header when it's missing, then refreshes like `refresh()`.
    /// A file that exists is never touched.
    public func refreshNow() async {
        createConfigurationIfMissing()
        forceResolve = true
        await refresh()
    }

    /// Creates `config.toml` with its commented header when it's missing, so
    /// the user and their agents find the common settings to uncomment. A
    /// file that can't be written changes nothing: a missing file still
    /// reads as the defaults with no projects.
    private func createConfigurationIfMissing() {
        _ = try? configStore.createIfMissing()
    }

    private func performRefresh() async {
        let configuration = configStore.lastValid
        let configured = configuration.projects.map(configuration.settings(for:))
        let current = session
        let now = clock.now
        do {
            // Groups and wildcards first: looked up at most hourly, or at once
            // after a configuration change, ⌘R or signing in.
            let force = forceResolve
            forceResolve = false
            let resolved = try await resolver.resolve(configured, force: force, at: now) { lookup in
                try await self.request { try await $0.repositories(of: lookup, at: now) }
            }
            guard current == session else { return }
            // For the CLI; a file that can't be written leaves pings to
            // match the configuration's `owner/name` selectors alone.
            try? repositoriesStore.record(resolved.mapValues(\.repositories))
            let projects = configured.map { $0.resolved(by: resolved[$0.name]) }
            let snapshot = try await request { try await $0.fetch(projects: configured, resolved: resolved, at: now) }
            guard current == session else { return }
            self.snapshot = snapshot
            fetchError = nil
            budget.record(snapshot.rateLimits, at: clock.now)
            // What each project has: the menu, the counts and the
            // notifications below all read these, and nothing else.
            let listings = self.listings(for: projects, in: snapshot, configuration: configuration)
            var notifications: [PostedNotification] = []
            let listed = listedPings
            appStateStore.update { state in
                notifications = Self.notify(snapshot: snapshot, listings: listings, projects: projects, pings: listed, state: &state, at: now)
                state.attention.prune(present: snapshot.items.values.joined(), at: now)
            }
            var built = MenuModel.build(
                listings: listings,
                snapshot: snapshot,
                configuration: configuration,
                state: appStateStore.state,
                expanded: expandedGroups,
                now: clock.now
            )
            // A fold whose group is gone, or whose project is, goes too.
            // A machine's section may only be waiting for its poll: its folds stay.
            let machines = Set(configuration.remote.machines)
            let folds = built.foldsToKeep(appStateStore.state.collapsedGroups)
                .union(appStateStore.state.collapsedGroups.filter { machines.contains($0.project) })
            appStateStore.update { $0.collapsedGroups = folds }
            built.foldedGroups = folds
            menu = built
            publishRateStatus()
            // Recorded (and saved) before posting: a crash in between loses a
            // notification rather than repeating one.
            for notification in notifications {
                await notifier.post(notification)
            }
        } catch GitHubError.unauthorized {
            // `request` has signed out already.
        } catch is CancellationError {
        } catch {
            guard current == session else { return }
            // Keep the rows and when they were fetched; say why they're old.
            // Rebuilt from the last snapshot (or none, listing every project
            // as not loaded yet) under the configuration this refresh used.
            let failure = (error as? GitHubError) ?? .network(error.localizedDescription)
            rebuildMenu(configuration)
            fetchError = failure
            budget.record(failure, at: clock.now)
            menu.fetchError = failure
            publishRateStatus()
        }
    }

    /// Finds the events in `snapshot`, and the new pings the listings hold,
    /// and records them in `state`, returning what to post (`select`).
    /// Every fetched item becomes known, listed or not: `snapshot` becomes
    /// the known items, and its sources known, so the next refresh compares
    /// with it, and an item a filter change brings into view later isn't new.
    private static func notify(
        snapshot: Snapshot,
        listings: [String: [Item]],
        projects: [ProjectSettings],
        pings: [Ping],
        state: inout AppState,
        at now: Date
    ) -> [PostedNotification] {
        let events = EventDetector.events(known: state.known, snapshot: snapshot, projects: projects)
            + EventDetector.pingEvents(listings: listings, projects: projects)
        let notifications = select(events, listings: listings, projects: projects, viewer: snapshot.viewerLogin, state: &state, at: now)
        state.known = state.known.updated(with: snapshot, projects: projects)
        // A ping's record stays while the ping does, so it's never notified again.
        state.notified.prune(present: Array(state.known.items.keys) + pings.map(\.item.id), at: now)
        return notifications
    }

    /// Records `events` in `state` and returns what to post: each event not
    /// handled before, once, in the first project (in configuration order)
    /// that lists the item and whose rules select it. Every event is
    /// recorded as handled, notified or not.
    private static func select(
        _ events: [Event],
        listings: [String: [Item]],
        projects: [ProjectSettings],
        viewer: String?,
        state: inout AppState,
        at now: Date
    ) -> [PostedNotification] {
        let settings = Dictionary(projects.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let listed = listings.mapValues { Set($0.map(\.id)) }
        var byID: [String: [Event]] = [:]
        var order: [String] = []
        for event in events {
            if byID[event.id] == nil { order.append(event.id) }
            byID[event.id, default: []].append(event)
        }
        var notifications: [PostedNotification] = []
        for id in order {
            guard let occurrences = byID[id], let first = occurrences.first, !state.notified.contains(first) else { continue }
            let selected = occurrences.first { event in
                guard listed[event.project]?.contains(event.item.id) == true, let project = settings[event.project] else { return false }
                return NotificationRules.shouldNotify(event, settings: project, viewer: viewer)
            }
            if let selected { notifications.append(NotificationRules.notification(for: selected)) }
            state.notified.insert(first, at: now)
        }
        return notifications
    }

    /// When the next refresh runs, from the rate budget and the configuration.
    private func nextDelay() -> RefreshDelay {
        let configuration = configStore.lastValid
        return budget.nextDelay(
            configured: TimeInterval(configuration.refreshIntervalSeconds),
            sharePercent: configuration.rateLimit.maxSharePercent,
            at: clock.now
        )
    }

    /// Puts the next delay and the rate-limit indicator in the menu model.
    @discardableResult
    private func publishRateStatus() -> RefreshDelay {
        let delay = nextDelay()
        menu.refreshDelay = delay
        let configuration = configStore.lastValid
        // REST serves workflow runs only: its line shows while some project shows them.
        let showsRuns = configuration.projects.contains { configuration.settings(for: $0).shows(.workflowRun) }
        menu.rateIndicator = budget.indicator(
            show: configuration.rateLimit.show,
            in: showsRuns ? [.graphql, .rest] : [.graphql],
            at: clock.now
        )
        return delay
    }

    /// Arms the timer with the rate budget's delay while refreshes may run,
    /// and stops it otherwise. While paused it comes back after the
    /// configured interval (or the pause's end, when sooner), so the
    /// listings still drop what has passed its window.
    private func armTimer() {
        guard phase.canRefresh else {
            timer.disarm()
            return
        }
        let delay = publishRateStatus()
        var seconds = delay.seconds(from: clock.now)
        if delay.isPaused { seconds = min(seconds, TimeInterval(configStore.lastValid.refreshIntervalSeconds)) }
        timer.arm(after: seconds) { [weak self] in
            await self?.refresh()
        }
    }

    // MARK: - User actions

    /// Opens the row's item on GitHub in the browser and marks it seen. A
    /// ping's row runs the ping's action instead (`runAction(ofPing:)`).
    /// Returns the work still running (a ping's action), for tests to
    /// await; the app doesn't wait for it.
    @discardableResult
    public func open(_ row: MenuRow) -> Task<Void, Never> {
        if let ping = row.item.ping {
            // A remote ping isn't in the ping store: its click is its machine's.
            guard ping.machine == nil else { return Task {} }
            return runAction(ofPing: ping.id)
        }
        actions.open(row.url)
        markSeen(row)
        return Task {}
    }

    /// Opens the project's repository on GitHub in the browser (Return on
    /// its header): the first one the configuration lists. It marks
    /// nothing seen.
    public func openRepository(of project: MenuSection) {
        guard let url = project.repositoryURL else { return }
        actions.open(url)
    }

    /// Opens the signed-in account's profile on GitHub in the browser (a
    /// click on the header's avatar or handle). Opens nothing until
    /// the account is known.
    public func openProfile() {
        guard let viewer else { return }
        actions.open(viewer.profileURL)
    }

    /// A notification was clicked: opens its item on GitHub and marks it
    /// seen, the version the last refresh found (or, before one has listed
    /// it, the version known from an earlier run). The app's notifier calls
    /// this with the notification's `itemURL`. A ping's notification runs
    /// the ping's action, as its row does. Returns the work still running
    /// (a ping's action), for tests to await.
    @discardableResult
    public func openNotification(_ itemURL: URL) -> Task<Void, Never> {
        if let ping = Ping.id(from: itemURL) { return runAction(ofPing: ping) }
        guard Ping.remote(from: itemURL) == nil else { return Task {} }
        actions.open(itemURL)
        let id = itemURL.absoluteString
        let fingerprint = snapshot?.items.values.joined().first { $0.id == id }?.fingerprint
            ?? appStateStore.state.known.items[id]?.fingerprint
        if let fingerprint {
            let now = clock.now
            updateAppState { $0.attention.markSeen(id: id, fingerprint: fingerprint, at: now) }
        }
        return Task {}
    }

    /// Marks the row's item seen without opening it (⌥-click): it needs
    /// attention again only once it changes. A ping's action isn't run,
    /// and its failure, if it had one, is cleared.
    public func markSeen(_ row: MenuRow) {
        if let ping = row.item.ping {
            if ping.machine == nil { markPingsSeen([ping]) }
            return
        }
        updateAppState { $0.attention.markSeen(row.item, at: clock.now) }
    }

    /// Marks every row that can need attention (open ones, failed runs)
    /// seen, in the project named `project`, or in every project when it's `nil`.
    public func markAllSeen(project: String? = nil) {
        let rows = menu.sections
            .filter { project == nil || $0.name == project }
            .flatMap(\.rows)
            .filter { Attention.canNeedAttention($0.item) }
        guard !rows.isEmpty else { return }
        let now = clock.now
        let listed = rows.compactMap(\.item.ping).filter { $0.machine == nil }
        if !listed.isEmpty { markPingsSeen(listed) }
        let items = rows.filter { $0.item.ping == nil }.map(\.item)
        guard !items.isEmpty else { return }
        updateAppState { state in
            for item in items { state.attention.markSeen(item, at: now) }
        }
    }

    /// Removes the row's ping now (the hover ✕, or ⌫ on the selected
    /// row), seen or not, with any failure on it, and takes its
    /// notification out of Notification Center. Any other row stays: only
    /// pings can be dismissed. Returns the removal still running, for tests
    /// to await; the app doesn't wait for it.
    @discardableResult
    public func dismiss(_ row: MenuRow) -> Task<Void, Never> {
        guard let ping = row.item.ping, ping.machine == nil else { return Task {} }
        try? pingStore.remove(id: ping.id)
        listPings()
        return Task { await removeLeftBanners() }
    }

    // MARK: - Pings

    /// Reads the ping store again and, when a ping arrived, changed or
    /// went, lists the pings at once from the last snapshot: no GitHub
    /// request. A new ping a project lists posts its `ping.sent`
    /// notification when the project's rules select it; a replaced one
    /// (same id, same sent time) doesn't again. A ping that went (withdrawn
    /// with the CLI) takes its notification out of Notification Center.
    /// The app's watcher on the store calls this.
    public func reloadPings() async {
        guard listPings() else { return }
        await removeLeftBanners()
        let configuration = configStore.lastValid
        let projects = configuration.projects.map(configuration.settings(for:))
        let listings = self.listings(for: projects, in: snapshot, configuration: configuration)
        let events = EventDetector.pingEvents(listings: listings, projects: projects)
        let unhandled = events.filter { !appStateStore.state.notified.contains($0) }
        guard !unhandled.isEmpty else { return }
        let now = clock.now
        let viewer = snapshot?.viewerLogin
        var notifications: [PostedNotification] = []
        // Recorded (and saved) before posting, as in a refresh.
        appStateStore.update { state in
            notifications = Self.select(unhandled, listings: listings, projects: projects, viewer: viewer, state: &state, at: now)
        }
        for notification in notifications {
            await notifier.post(notification)
        }
    }

    /// Runs the action of the ping `id` names, as the store has it now (a
    /// replace may have changed it), through the action port (a Herdr
    /// action through `runHerdr`). When it
    /// works, or the ping has none, the ping is marked seen (and any earlier
    /// failure cleared); when it fails, the ping stays as it was and the
    /// failure's reason is recorded on it for its row. Either is written
    /// only to the sending of the ping that ran: one withdrawn, replaced or
    /// sent anew while its action ran is left as the CLI wrote it. A ping
    /// no longer stored does nothing.
    private func runAction(ofPing id: String) -> Task<Void, Never> {
        guard let ping = pingStore.ping(id: id) else {
            listPings()
            return Task {}
        }
        guard let action = ping.action else {
            markPingsSeen([ping])
            return Task {}
        }
        return Task {
            let outcome: ActionOutcome
            if case .herdr(let target) = action {
                outcome = await runHerdr(target)
            } else {
                outcome = await actions.run(action)
            }
            switch outcome {
            case .done:
                markPingsSeen([ping])
            case .failed(let reason):
                try? pingStore.recordFailure(ping, reason: reason)
                listPings()
            }
        }
    }

    /// A ping's Herdr action: focuses the tab or pane `target` names
    /// (`HerdrFocus`), then, once that worked, brings `[herdr] terminal`
    /// forward through the action port, as an `--app` action would. Without
    /// a terminal set, only the focus runs. Either failing fails the action.
    private func runHerdr(_ target: String) async -> ActionOutcome {
        let focused = await herdr.focus(target)
        guard focused == .done, let terminal = configStore.lastValid.herdr.terminal else { return focused }
        return await actions.run(.app(terminal))
    }

    // MARK: - Remote machines

    /// The pings listed: the ping store's, then the remote machines'.
    private var listedPings: [Ping] { pings + remote.pings }

    /// Every project's listing, and each remote machine's own, from
    /// `snapshot` and the listed pings (`Listing.listings`).
    private func listings(for projects: [ProjectSettings], in snapshot: Snapshot?, configuration: Configuration) -> [String: [Item]] {
        Listing.listings(
            for: projects,
            in: snapshot,
            pings: listedPings,
            machines: configuration.remote.machines.map(configuration.settings(forMachine:)),
            now: clock.now
        )
    }

    /// Follows `[remote] machines` in the last valid configuration: at
    /// start and on every valid change. A changed list keeps what the
    /// machines still listed know, drops the removed ones' pings, and
    /// polls at once; no machines stops polling.
    private func followMachines() {
        let labels = configStore.lastValid.remote.machines
        guard labels != remote.labels else { return }
        remote.follow(labels)
        rebuildMenu(configStore.lastValid)
        armMachineTimer(after: 0)
    }

    /// Asks every remote machine for its pings at once, through Herdr
    /// (`RemotePingReader`), and lists each machine's as it answers, so a
    /// slow one never holds up another. A machine that fails keeps its
    /// last pings and records why. No GitHub request is made. Then the
    /// machine timer comes back in `machinePollInterval`. Its timer calls
    /// this. A call while a poll runs returns at once, and the running poll
    /// goes again when it's done, so a machine added meanwhile is asked.
    public func pollMachines() async {
        guard !remote.labels.isEmpty, machineGate.begin() else { return }
        repeat {
            await pollMachinesOnce()
        } while machineGate.finish() && machineGate.begin()
        armMachineTimer(after: Self.machinePollInterval)
    }

    private func pollMachinesOnce() async {
        let reader = remoteReader
        await withTaskGroup(of: (String, Result<PingList, RemotePingReader.Failure>).self) { group in
            for label in remote.labels {
                group.addTask { (label, await reader.list(machine: label)) }
            }
            for await (label, result) in group {
                let before = remote.machine(label)?.pings
                remote.record(result, for: label, at: clock.now)
                if remote.machine(label)?.pings != before { rebuildMenu(configStore.lastValid) }
            }
        }
    }

    /// Arms the machine timer to poll after `seconds` while there are
    /// remote machines, and stops it otherwise.
    private func armMachineTimer(after seconds: TimeInterval) {
        guard !remote.labels.isEmpty else {
            machineTimer.disarm()
            return
        }
        machineTimer.arm(after: seconds) { [weak self] in
            await self?.pollMachines()
        }
    }

    /// Reads the ping store again, removing the seen pings whose
    /// seen-window has passed, and, when anything changed, lists the
    /// pings from the last snapshot. Returns whether anything changed.
    @discardableResult
    private func listPings() -> Bool {
        let configuration = configStore.lastValid
        let now = clock.now
        let stored = pingStore.all().compactMap { ping -> Ping? in
            guard Self.hasLeft(ping, in: configuration, at: now) else { return ping }
            // Removed only as it was read: one the CLI replaced or sent anew
            // meanwhile is listed as it is now. One that can't be removed
            // stays stored; no listing shows it.
            guard (try? pingStore.removeIfUnchanged(ping)) == false else { return nil }
            return pingStore.ping(id: ping.id)
        }
        forgetLeftPings(stored: stored)
        guard stored != pings else { return false }
        pings = stored
        rebuildMenu(configStore.lastValid)
        return true
    }

    /// Forgets the pings that left the store, so an id sent again later is
    /// a new ping that notifies again (a replace, which keeps its
    /// `instance`, never does), and queues their notifications for
    /// `removeLeftBanners()`. A ping left when its `ping.sent` record names
    /// no stored ping (withdrawn, dismissed, past its window, or gone while
    /// the app wasn't running), or another instance than the stored one
    /// (withdrawn and sent anew under its id, however soon).
    private func forgetLeftPings(stored: [Ping]) {
        let current = Dictionary(
            stored.map { ($0.item.id, NotifiedEvents.key(Event(kind: .pingSent, project: "", item: $0.item, occurrence: $0.instance ?? ""))) },
            uniquingKeysWith: { first, _ in first }
        )
        let pingRecords = appStateStore.state.notified.records.filter { key, record in
            guard let url = URL(string: key), Ping.id(from: url) != nil else { return false }
            return record.events.contains { $0 != current[key] }
        }
        guard !pingRecords.isEmpty else { return }
        appStateStore.update { state in
            for key in pingRecords.keys.sorted() {
                leftBanners += state.notified.remove(itemID: key) { $0 != current[key] }
            }
        }
    }

    /// Takes the notifications of the pings that left out of Notification
    /// Center. Before any new notification is posted, since a ping sent
    /// again with the same id posts under the same notification id.
    private func removeLeftBanners() async {
        let banners = leftBanners
        leftBanners = []
        for id in banners {
            await notifier.removeDelivered(id: id)
        }
    }

    /// Whether `ping` has left every project it's filed under: it's seen,
    /// and each of those projects' `seen-window` has passed since. A
    /// project no longer configured counts with `[defaults.pings]`'s window,
    /// so a ping whose projects are all gone still leaves once it's seen.
    private static func hasLeft(_ ping: Ping, in configuration: Configuration, at now: Date) -> Bool {
        guard ping.seen != nil else { return false }
        let windows = ping.projects.map { name in
            configuration.projects.first { $0.name == name }
                .map { configuration.settings(for: $0).pings.seenWindow }
                ?? configuration.defaults.pings.seenWindow
        }
        return windows.allSatisfy { !ping.isListed(seenWindow: $0, at: now) }
    }

    /// Records `listed` (the pings as the user saw them) as seen now, in
    /// the ping store, clearing their actions' failures, and lists them
    /// again. One withdrawn, replaced or sent anew since is left as it is
    /// (`PingStore.markSeen(_:at:)`). A store that can't be written leaves
    /// them as they were.
    private func markPingsSeen(_ listed: [Ping]) {
        let now = clock.now
        for ping in listed { try? pingStore.markSeen(ping, at: now) }
        listPings()
    }

    /// Collapses the project's section, or expands it if it's collapsed.
    /// Remembered across restarts.
    public func toggleCollapsed(_ project: String) {
        updateAppState { state in
            if state.collapsed.remove(project) == nil { state.collapsed.insert(project) }
        }
    }

    /// Folds the subsection `group` names, or unfolds it if it's folded,
    /// without a refresh; its subheader keeps its count. Remembered across
    /// restarts. A group drawn after a divider, or one no longer listed,
    /// has no subheader to fold, and nothing changes.
    public func toggleGroup(_ group: GroupID) {
        guard menu.subsection(group) != nil else { return }
        updateAppState { state in
            if state.collapsedGroups.remove(group) == nil { state.collapsedGroups.insert(group) }
        }
    }

    /// Shows every row of the group `group` names, past its `show-first`
    /// cap, until Show less or the menu closes. Kept in memory only: a group
    /// that isn't capped changes nothing.
    public func showMore(_ group: GroupID) {
        guard let listed = menu.group(group), listed.hiddenCount > 0 else { return }
        expandedGroups.insert(group)
        menu.applyExpansions(expandedGroups, configuration: configStore.lastValid)
    }

    /// Caps the group `group` names at its `show-first` again.
    public func showLess(_ group: GroupID) {
        guard expandedGroups.remove(group) != nil else { return }
        menu.applyExpansions(expandedGroups, configuration: configStore.lastValid)
    }

    /// The menu closed: every group Show more revealed is capped again, so
    /// the menu opens with every cap back.
    public func panelClosed() {
        guard !expandedGroups.isEmpty else { return }
        expandedGroups = []
        menu.applyExpansions(expandedGroups, configuration: configStore.lastValid)
    }

    /// Changes the app state, saves it, and brings the menu model's
    /// attention flags, counts and collapsed sections up to date.
    private func updateAppState(_ body: (inout AppState) -> Void) {
        appStateStore.update(body)
        applyAttention(configStore.lastValid)
    }

    /// Rebuilds the menu model from the last snapshot (or none) under
    /// `configuration`, keeping the fetch error, the refresh delay and the
    /// rate-limit indicator: a project added since shows as not loaded yet,
    /// a removed one disappears. Follows the menu bar rule of `applyAttention`.
    private func rebuildMenu(_ configuration: Configuration) {
        let listings = self.listings(for: configuration.projects.map(configuration.settings(for:)), in: snapshot, configuration: configuration)
        var rebuilt = MenuModel.build(
            listings: listings,
            snapshot: snapshot,
            configuration: configuration,
            state: appStateStore.state,
            expanded: expandedGroups,
            now: clock.now
        )
        rebuilt.fetchError = menu.fetchError
        rebuilt.refreshDelay = menu.refreshDelay
        rebuilt.rateIndicator = menu.rateIndicator
        if phase != .ready { rebuilt.menuBarLabel = .hidden }
        menu = rebuilt
    }

    /// Brings the menu model's attention up to date, with no count in the
    /// menu bar unless the phase is `ready`: without projects the menu has
    /// nothing to count.
    private func applyAttention(_ configuration: Configuration) {
        menu.applyAttention(appStateStore.state, configuration: configuration)
        if phase != .ready { menu.menuBarLabel = .hidden }
    }

    private func apply(_ event: LifecycleEvent) {
        phase = phase.after(event)
    }
}
