import Foundation

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
/// are app state, kept by `appStateStore`.
@MainActor
public final class Shipyard {
    /// What signing out left behind.
    public enum SignOutResult: Equatable, Sendable {
        /// The token store is cleared and nothing else holds a token.
        case signedOut
        /// The token came from `gh`, which is still signed in: shipyard picks
        /// it up again at the next launch unless the user runs `gh auth logout`.
        case ghStillSignedIn
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

    /// What the panel draws. A failed refresh keeps the rows and sets
    /// `fetchError` and the time they were last updated.
    public private(set) var menu = MenuModel.empty
    /// The last refresh that succeeded; `nil` before one did.
    public private(set) var snapshot: Snapshot?
    /// Why the latest refresh failed; `nil` once one succeeds.
    public private(set) var fetchError: GitHubError?
    /// Whether a refresh is running now.
    public var isRefreshing: Bool { gate.isRunning }
    /// What the rate budget knows: limits, recent costs, a pause.
    public private(set) var budget = RateBudget()
    /// Whether ⌘R may refresh now: false only while the rate budget pauses
    /// refreshing (the menu model says why).
    public var canRefreshNow: Bool { budget.canRefresh(at: clock.now) }

    public let configStore: ConfigStore
    /// Seen items and collapsed projects, in `state.json`.
    public let appStateStore: AppStateStore
    private let tokenStore: any TokenStore
    private let urlOpener: any URLOpening
    private let notifier: any Notifying
    private let timer: any RefreshTimer
    private let clock: any WallClock
    private var gate = RefreshGate()
    private let tokenProvider: TokenProvider
    private let deviceFlow: DeviceFlow
    private let transport: any HTTPTransport

    /// The client for the current token; `nil` when signed out.
    private(set) var github: GitHubClient?
    private var deviceFlowTask: Task<Void, Never>?
    /// Bumped whenever a device flow begins or is cancelled, so a flow that
    /// was cancelled can't change anything when it finishes.
    private var deviceFlowGeneration = 0
    /// Bumped whenever a token is taken up or dropped, so an answer to a
    /// request made with an earlier token can't sign in or out.
    private var session = 0

    public init(
        configStore: ConfigStore,
        appStateStore: AppStateStore,
        tokenStore: any TokenStore,
        urlOpener: any URLOpening,
        notifier: any Notifying,
        gh: any GhTokenLookup = GhCLI(),
        transport: any HTTPTransport = URLSessionTransport(),
        clock: any WallClock = SystemClock(),
        timer: any RefreshTimer = TaskRefreshTimer(),
        sleep: @escaping DeviceFlow.Sleep = DeviceFlow.systemSleep,
        oauthClientID: String = OAuthApp.clientID
    ) {
        self.configStore = configStore
        self.appStateStore = appStateStore
        self.tokenStore = tokenStore
        self.urlOpener = urlOpener
        self.notifier = notifier
        self.clock = clock
        self.timer = timer
        self.tokenProvider = TokenProvider(store: tokenStore, gh: gh)
        self.deviceFlow = DeviceFlow(clientID: oauthClientID, transport: transport, clock: clock, sleep: sleep)
        self.transport = transport
    }

    /// Loads the app state and the configuration and signs in with the token
    /// store's token or `gh`'s, if either has one; otherwise stays signed
    /// out. Signing in with projects runs the first refresh.
    public func start() async {
        appStateStore.load(at: clock.now)
        configStore.reload()
        let provider = tokenProvider
        // `gh auth token` spawns a process; keep it off the main actor.
        let found = await Task.detached { provider.current() }.value
        guard let found else {
            apply(.signedOut)
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
        if tokenSource == .tokenStore { try? tokenStore.delete() }
        endSession()
    }

    /// Clears the token store and returns to `signedOut`. When the token came
    /// from `gh`, says so, so the app can tell the user to run `gh auth logout`.
    @discardableResult
    public func signOut() -> SignOutResult {
        cancelDeviceFlow()
        let source = tokenSource
        try? tokenStore.delete()
        signInError = nil
        endSession()
        return source == .gh ? .ghStillSignedIn : .signedOut
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

    /// Moves the phase with a reload's result and refreshes (or stops the
    /// timer). Only a valid change moves anything.
    private func follow(_ result: ConfigStore.ReloadResult) async {
        if case .changed(let configuration) = result {
            apply(.configurationChanged(hasProjects: configuration.hasProjects))
            // `[attention]` and `[menu-bar]` apply at once, even if the
            // refresh below can't run (paused).
            menu.applyAttention(appStateStore.state, configuration: configuration)
            if phase.canRefresh {
                await refresh()
            } else {
                timer.disarm()
            }
        }
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

    /// A limit the picker ran into holds refreshes back too: it's the same limit.
    private func recordLimit(_ error: any Error) {
        guard let error = error as? GitHubError else { return }
        budget.record(error, at: clock.now)
    }

    // MARK: - Refreshing

    /// Fetches every project's items and publishes the menu model. The timer,
    /// opening the panel, ⌘R, waking and a configuration change all come here.
    /// Does nothing outside `ready`. One refresh runs at a time: a call while
    /// one runs returns at once and the running one goes again when it's done
    /// (several calls meanwhile make one more run). Afterwards the timer is
    /// armed for the next one, as the rate budget says. While the budget
    /// pauses refreshing (a limit ran out, or a secondary limit), nothing is
    /// sent: the timer stays armed for the end of the pause.
    public func refresh() async {
        guard phase.canRefresh else { return }
        guard canRefreshNow else {
            if !gate.isRunning { armTimer() }
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

    private func performRefresh() async {
        let configuration = configStore.lastValid
        let projects = configuration.projects.map(configuration.settings(for:))
        let current = session
        let now = clock.now
        do {
            let snapshot = try await request { try await $0.fetch(projects: projects, at: now) }
            guard current == session else { return }
            self.snapshot = snapshot
            fetchError = nil
            budget.record(snapshot.rateLimits, at: clock.now)
            var notifications: [PostedNotification] = []
            appStateStore.update { state in
                notifications = Self.notify(snapshot: snapshot, projects: projects, configuration: configuration, state: &state, at: now)
                state.attention.prune(present: snapshot.items.values.joined(), at: now)
            }
            menu = MenuModel.build(snapshot: snapshot, configuration: configuration, state: appStateStore.state, now: clock.now)
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
            let failure = (error as? GitHubError) ?? .network(error.localizedDescription)
            fetchError = failure
            budget.record(failure, at: clock.now)
            menu.fetchError = failure
            publishRateStatus()
        }
    }

    /// Finds the events in `snapshot` and records them in `state`, returning
    /// what to post: each event not handled before, once, in the first
    /// project (in configuration order) whose rules select it. Every event
    /// is recorded as handled, notified or not. Then `snapshot` becomes the
    /// known items, and its sources known, so the next refresh compares with it.
    private static func notify(
        snapshot: Snapshot,
        projects: [ProjectSettings],
        configuration: Configuration,
        state: inout AppState,
        at now: Date
    ) -> [PostedNotification] {
        let events = EventDetector.events(known: state.known, snapshot: snapshot, projects: projects)
        let settings = Dictionary(projects.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let hidden = Set(configuration.hideAuthors.map { $0.lowercased() })
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
                settings[event.project].map { NotificationRules.shouldNotify(event, settings: $0, hiddenAuthors: hidden) } ?? false
            }
            if let selected { notifications.append(NotificationRules.notification(for: selected)) }
            state.notified.insert(first, at: now)
        }
        state.known = state.known.updated(with: snapshot, projects: projects)
        state.notified.prune(present: state.known.items.keys, at: now)
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
        menu.rateIndicator = budget.indicator(show: configStore.lastValid.rateLimit.show, at: clock.now)
        return delay
    }

    /// Arms the timer with the rate budget's delay while refreshes may run,
    /// and stops it otherwise.
    private func armTimer() {
        guard phase.canRefresh else {
            timer.disarm()
            return
        }
        let delay = publishRateStatus()
        timer.arm(after: delay.seconds(from: clock.now)) { [weak self] in
            await self?.refresh()
        }
    }

    // MARK: - User actions

    /// Opens the row's item on GitHub in the browser and marks it seen.
    public func open(_ row: MenuRow) {
        urlOpener.open(row.url)
        markSeen(row)
    }

    /// A notification was clicked: opens its item on GitHub and marks it
    /// seen, the version the last refresh found (or, before one has listed
    /// it, the version known from an earlier run). The app's notifier calls
    /// this with the notification's `itemURL`.
    public func openNotification(_ itemURL: URL) {
        urlOpener.open(itemURL)
        let id = itemURL.absoluteString
        let fingerprint = snapshot?.items.values.joined().first { $0.id == id }?.fingerprint
            ?? appStateStore.state.known.items[id]?.fingerprint
        guard let fingerprint else { return }
        let now = clock.now
        updateAppState { $0.attention.markSeen(id: id, fingerprint: fingerprint, at: now) }
    }

    /// Marks the row's item seen without opening it (⌥-click): it needs
    /// attention again only once it changes.
    public func markSeen(_ row: MenuRow) {
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
        updateAppState { state in
            for row in rows { state.attention.markSeen(row.item, at: now) }
        }
    }

    /// Collapses the project's section, or expands it if it's collapsed.
    /// Remembered across restarts.
    public func toggleCollapsed(_ project: String) {
        updateAppState { state in
            if state.collapsed.remove(project) == nil { state.collapsed.insert(project) }
        }
    }

    /// Changes the app state, saves it, and brings the menu model's
    /// attention flags, counts and collapsed sections up to date.
    private func updateAppState(_ body: (inout AppState) -> Void) {
        appStateStore.update(body)
        menu.applyAttention(appStateStore.state, configuration: configStore.lastValid)
    }

    private func apply(_ event: LifecycleEvent) {
        phase = phase.after(event)
    }
}
