import Foundation
import Observation
import ShipyardCommand
import ShipyardConfig
import ShipyardNotices
import ShipyardPings

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
/// The user's notes are read from Notion through `ntn`, Notion's CLI, with
/// its own login (`notionRoute`, ADR 0012), every minute and when the menu
/// opens (`refreshNotes()`), and listed with them too, once the user
/// connected Notion (`connectNotion()`, ADR 0013): until then no `ntn`
/// runs but the Notion view's check (`checkNotion()`).
/// A demo run with example items (`demoItems`) lists them in place of
/// GitHub's items and the notes, signed in as the file's account, and
/// reads no token and sends no request.
/// Observable, so the panel redraws when what it reads changes.
@MainActor
@Observable
public final class Shipyard {
    /// What signing out left behind.
    public enum SignOutResult: Equatable, Sendable {
        case signedOut
        case ghStillSignedIn
    }

    /// Why shipyard is signed out, so the connect screen can say what to do.
    public enum SignedOutReason: Equatable, Sendable {
        case noToken
        case rejected(TokenSource)
        case userSignedOut(SignOutResult)
    }

    /// Where shipyard is in its lifecycle.
    public private(set) var phase: Phase = .signedOut {
        didSet { followBannerConditions() }
    }
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
    public private(set) var menu = MenuModel.empty {
        didSet { followBannerConditions() }
    }
    /// The theme the panel draws with: the one `theme` in the configuration
    /// names, kept from the last valid configuration while an edit is
    /// rejected, and following the theme files on every reload.
    public private(set) var theme = BuiltInThemes.system
    /// The gear menu's Theme submenu, as the latest reload read the themes.
    public private(set) var themeMenu = ThemeMenu(.builtIn, current: BuiltInThemes.system)
    private(set) var expandedGroups: Set<GroupID> = []
    private(set) var snapshot: Snapshot?
    /// The pings in the ping store, as last read: at start and whenever the
    /// store changes (`reloadPings()`).
    public private(set) var pings: [Ping] = []
    /// What each remote machine (`[remote] machines`) last listed, and how
    /// its latest poll went (`pollMachines()`).
    public private(set) var remote = RemoteMachines()
    /// How often the remote machines are polled, apart from the refresh.
    public static let machinePollInterval: TimeInterval = 30
    private var leftBanners: [String] = []
    private var followsConfiguredMachines = false
    /// Each project's open notes, by project slug, as Notion last listed
    /// them; a project whose read failed keeps its last ones.
    public private(set) var notes: [String: [Note]] = [:]
    /// Why each project's notes couldn't be read, by project slug, for its
    /// error row; empty once a read works.
    public private(set) var noteErrors: [String: String] = [:]
    /// Why the last read could list no notes at all: no `ntn`, ntn logged
    /// out, or no "Shipyard Notes" page in ntn's workspace. The notes
    /// banner says so rather than listing none; `nil` once a read works.
    public private(set) var notesBlocked: NotesNotice?
    /// Each project's notes database in Notion, by project slug, as the
    /// last read matched them: its header's notes count opens it.
    public private(set) var noteDatabases: [String: URL] = [:]
    /// The projects the new-note icon is starting a note in now.
    public private(set) var startingNotes: Set<String> = []
    /// Whether the user connected Notion (Connect with ntn), as the app
    /// state keeps it: only then are notes read. Kept here too, observed,
    /// so connecting redraws the panel at once.
    public private(set) var notionConnected = false
    /// What the Notion view's latest check found (`checkNotion()`); `nil`
    /// before one, and while one runs.
    public private(set) var notionStatus: NotionStatus?
    @ObservationIgnored private var notionCheck = 0
    /// Why the new-note icon couldn't start a note, by project slug, for
    /// its error row; cleared when the menu opens again or a note starts.
    public private(set) var newNoteErrors: [String: String] = [:]
    /// How often the notes are read, apart from the refresh; opening the
    /// menu reads them too.
    public static let notesInterval: TimeInterval = 60
    /// Why the latest refresh failed; `nil` once one succeeds.
    public private(set) var fetchError: GitHubError?
    /// Whether a refresh is running now.
    public var isRefreshing: Bool { gate.isRunning }
    /// Why the configuration file was rejected, for the panel's banner;
    /// `nil` while it reads cleanly. Shipyard keeps running on the last
    /// valid configuration meanwhile.
    public private(set) var configError: ConfigurationError? {
        didSet { followBannerConditions() }
    }
    /// Unknown settings the last clean read ignored, and other warnings,
    /// for the panel's quiet banner; empty when there are none or the latest
    /// read failed.
    public private(set) var configWarnings: [ConfigurationIssue] = [] {
        didSet { followBannerConditions() }
    }
    /// The problems of the theme files beside the configuration file, for
    /// the panel's banner; empty while every file reads. A file with a
    /// problem keeps the theme it last read.
    public private(set) var themeIssues: [ThemeIssue] = [] {
        didSet { followBannerConditions() }
    }
    /// Whether macOS lets shipyard post notifications, as the app's
    /// notifier last learned: the condition of the notifications-off banner.
    public var notificationsAreOff = false {
        didSet {
            notifierReported = true
            followBannerConditions()
        }
    }
    /// App control's lease as the app's control server last left it: the
    /// condition of the lease's banner and of the stopped holders' quiet
    /// lines. A lease that ends, or is handed straight to the next holder,
    /// clears the lease banner's snooze, so the next lease shows its banner.
    /// A relaunch starts with no lease known, so a lease it was handed over
    /// shows its banner again. The menu bar icon's dot is the app's, and a
    /// snooze never hides it.
    public var lease = PanelBanner.Lease() {
        didSet {
            if lease.held?.term != oldValue.held?.term, bannerSnoozes.ends["lease"] != nil {
                changeBannerSnoozes { $0.clear("lease") }
            }
            followBannerConditions()
        }
    }
    private var bannerSnoozes = BannerSnoozes()
    private var restoredSnoozes: Set<String> = []
    private var configurationRead = false
    private var refreshEnded = false
    private var notifierReported = false
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

    public let configStore: ConfigurationStore
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
    private var resolvedRepositories: [String: [String]]?
    private let tokenStore: any TokenStore
    private let actions: any ActionRunning
    private let herdr: HerdrFocus
    private let remoteReader: RemotePingReader
    private let machineTimer: any RefreshTimer
    @ObservationIgnored private var machineGate = RefreshGate()
    private let notionRoute: (any HTTPTransport)?
    private let notesTimer: any RefreshTimer
    @ObservationIgnored private var notesGate = RefreshGate()
    @ObservationIgnored private let notesReader = NotesReader()
    private let notifier: any Notifying
    private let tailnet: any TailnetIdentity
    private let loginItem: any LoginItem
    private let timer: any RefreshTimer
    private let clock: any WallClock
    private var gate = RefreshGate()
    private let tokenProvider: TokenProvider
    private let deviceFlow: DeviceFlow
    /// Whether the build has an OAuth App client ID, so the device flow can start.
    public let canSignInWithGitHub: Bool
    private let transport: any HTTPTransport
    /// How the GitHub client waits before it sends a timed-out request again.
    private let sleep: Sleep
    /// A demo run's example items, listed in place of GitHub's and
    /// Notion's; `nil` outside a demo run with a `demo-items.json`.
    private let demoItems: DemoItems?

    private(set) var github: (any GitHubReading)?
    @ObservationIgnored private var deviceFlowTask: Task<Void, Never>?
    @ObservationIgnored private var deviceFlowGeneration = 0
    @ObservationIgnored private var session = 0
    @ObservationIgnored private let resolver = RepositoryResolver()
    /// Whether the next refresh looks every group and `owner/*` up again,
    /// whatever their age: at launch, after a configuration change, on ⌘R
    /// and after signing in again.
    @ObservationIgnored private var forceResolve = true

    public init(
        configStore: ConfigurationStore,
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
        notionRoute: (any HTTPTransport)? = nil,
        notesTimer: any RefreshTimer = TaskRefreshTimer(),
        tailnet: any TailnetIdentity = TailscaleCLI(),
        sleep: @escaping Sleep = systemSleep,
        oauthClientID: String = OAuthApp.clientID,
        demoItems: DemoItems? = nil
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
        self.notionRoute = notionRoute
        self.notesTimer = notesTimer
        self.notifier = notifier
        self.tailnet = tailnet
        self.loginItem = loginItem
        self.clock = clock
        self.timer = timer
        self.tokenProvider = TokenProvider(store: tokenStore, gh: gh)
        self.deviceFlow = DeviceFlow(clientID: oauthClientID, transport: transport, clock: clock, sleep: sleep)
        self.sleep = sleep
        self.canSignInWithGitHub = OAuthApp.isSet(oauthClientID)
        self.transport = transport
        self.demoItems = demoItems
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
        try? pingStore.createDirectory()
        appStateStore.load(at: clock.now)
        bannerSnoozes = appStateStore.state.bannerSnoozes
        restoredSnoozes = Set(bannerSnoozes.ends.keys)
        notionConnected = appStateStore.state.notionConnected
        try? ConfigurationLocation.record(configStore.url, in: repositoriesStore.directory)
        createConfigurationIfMissing()
        configStore.reload()
        publishConfigStatus()
        configurationRead = true
        followBannerConditions()
        await reloadPings()
        await followMachines()
        if readsNotes {
            rebuildMenu(configStore.lastValid)
            armNotesTimer(after: 0)
        }
        if configError == nil { followLaunchAtLogin() }
        if let demoItems {
            await connect(to: demoItems, source: .demoItems)
            return
        }
        let provider = tokenProvider
        let found = await Task.detached { provider.current() }.value
        guard let found else {
            apply(.signedOut)
            signedOutReason = .noToken
            return
        }
        await connect(with: found)
    }

    /// Starts the device flow: requests a code, moves to `connecting` with it,
    /// and polls until the user approves. On success the token is saved to the
    /// token store and shipyard signs in; on expiry, denial or failure it
    /// returns to `signedOut` with `signInError` set, ready to begin again.
    /// Only starts from `signedOut`; while one runs, returns that one.
    @discardableResult
    public func beginDeviceFlow() -> Task<Void, Never> {
        if let deviceFlowTask { return deviceFlowTask }
        guard phase == .signedOut, demoItems == nil else { return Task {} }
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

    private func connect(with found: FoundToken) async {
        await connect(to: GitHubClient(token: found.value, transport: transport, sleep: sleep), source: found.source)
    }

    private func connect(to github: any GitHubReading, source: TokenSource) async {
        session += 1
        let current = session
        self.github = github
        tokenSource = source
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

    func request<T>(_ body: (any GitHubReading) async throws -> T) async throws -> T {
        guard let github else { throw GitHubError.unauthorized }
        let current = session
        do {
            return try await body(github)
        } catch GitHubError.unauthorized {
            if current == session { signOutAfterUnauthorized() }
            throw GitHubError.unauthorized
        }
    }

    private func signOutAfterUnauthorized() {
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
        if demoItems == nil { try? tokenStore.delete() }
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
        resolver.reset()
        forceResolve = true
        timer.disarm()
        apply(.signedOut)
    }

    /// Reads the configuration file again and follows it: a change with
    /// projects moves to `ready` and refreshes, one without moves to
    /// `needsProjects` and stops the timer. A rejected edit changes nothing
    /// (the store keeps the last valid configuration and its error). The
    /// app's configuration watcher calls this.
    @discardableResult
    public func reloadConfiguration() async -> ConfigurationStore.ReloadResult {
        let result = configStore.reload()
        await follow(result)
        return result
    }

    private func follow(_ result: ConfigurationStore.ReloadResult) async {
        publishConfigStatus()
        if case .changed(let configuration) = result {
            forceResolve = true
            followLaunchAtLogin()
            await followMachines()
            if readsNotes { armNotesTimer(after: 0) }
            apply(.configurationChanged(hasProjects: configuration.hasProjects))
            rebuildMenu(configuration)
            if phase.canRefresh {
                publishRateStatus()
                await refresh()
            } else {
                timer.disarm()
            }
        }
    }

    private func publishConfigStatus() {
        configError = configStore.error
        configWarnings = configStore.warnings
        let theme = configStore.theme
        if self.theme != theme { self.theme = theme }
        let themeMenu = ThemeMenu(configStore.themes, current: theme)
        if self.themeMenu != themeMenu { self.themeMenu = themeMenu }
        let themeIssues = configStore.themeIssues
        if self.themeIssues != themeIssues { self.themeIssues = themeIssues }
        presets = configStore.acceptsPreset ? Preset.all : []
        let notices = configStore.lastValid.notices
        let port = notices.listen ? notices.port : nil
        if noticeListenerPort != port { noticeListenerPort = port }
        configStatusStore.record(configStore.check(at: clock.now))
    }

    private func followLaunchAtLogin() {
        loginItem.setEnabled(configStore.lastValid.launchAtLogin)
    }

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
    /// `ConfigurationError` (and writes nothing) for an empty name, a name already
    /// used, a project without repositories or a slug that isn't
    /// `owner/name`; throws the file system's error when it can't write.
    @discardableResult
    public func addProjects(_ projects: [NewProject]) async throws -> ConfigurationStore.ReloadResult {
        let result = try configStore.append(projects: projects)
        await follow(result)
        return result
    }

    /// Onboarding's first step: writes `preset`'s whole file, with
    /// `projects` as the repositories picked for it (none for
    /// `review-queue`, or for `incoming-contributions` watching `owned`), and
    /// follows the reload like `addProjects`: the phase moves to `ready` and
    /// the first refresh runs, without a restart. Throws a `ConfigurationError`
    /// (and writes nothing) when the file already holds settings besides
    /// `version`, which also stops offering presets, or when a project is
    /// invalid; throws the file system's error when it can't write.
    @discardableResult
    public func choosePreset(_ preset: Preset, projects: [NewProject] = []) async throws -> ConfigurationStore.ReloadResult {
        let result: ConfigurationStore.ReloadResult
        do {
            result = try configStore.writePreset(preset, projects: projects)
        } catch let error as ConfigurationError where error == Configuration.presetRefused {
            await reloadConfiguration()
            throw error
        }
        await follow(result)
        return result
    }

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
        } catch let error as ConfigurationError {
            configError = error
        } catch {
            configError = ConfigurationError([ConfigurationIssue(line: nil, message: "can't switch the layout: \(error.localizedDescription)")])
        }
    }

    /// The gear menu's Theme submenu: writes `name` to the top-level `theme`
    /// in the configuration file and follows the reload, so the panel draws
    /// the theme as it does for a hand edit. When the file can't be written
    /// (it doesn't read, `theme` is in a form the writer doesn't edit, the
    /// name is no theme, or the file system refuses), nothing changes and
    /// `configError` says why until the next reload.
    public func switchTheme(to name: String) async {
        do {
            await follow(try configStore.setTheme(name))
        } catch let error as ConfigurationError {
            configError = error
        } catch {
            configError = ConfigurationError([ConfigurationIssue(line: nil, message: "can't switch the theme: \(error.localizedDescription)")])
        }
    }

    private func recordLimit(_ error: any Error) {
        guard let error = error as? GitHubError else { return }
        budget.record(error, at: clock.now)
    }

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
    /// commented header when it's missing, then refreshes like `refresh()`
    /// and, at the same time, polls every remote machine (`pollMachines()`).
    /// A file that exists is never touched.
    public func refreshNow() async {
        createConfigurationIfMissing()
        forceResolve = true
        async let polled: Void = pollMachines()
        await refresh()
        await polled
    }

    private func createConfigurationIfMissing() {
        try? configStore.createIfMissing()
    }

    private func performRefresh() async {
        let configuration = configStore.lastValid
        let configured = configuration.projects.map(configuration.settings(for:))
        let current = session
        let now = clock.now
        do {
            let force = forceResolve
            forceResolve = false
            let resolved = try await resolver.resolve(configured, force: force, at: now) { lookup in
                try await self.request { try await $0.repositories(of: lookup, at: now) }
            }
            guard current == session else { return }
            let repositories = resolved.mapValues(\.repositories)
            resolvedRepositories = repositories
            try? repositoriesStore.record(repositories)
            let projects = configured.map { $0.resolved(by: resolved[$0.slug]) }
            let snapshot = try await request { try await $0.fetch(projects: configured, resolved: resolved, at: now) }
            guard current == session else { return }
            self.snapshot = snapshot
            fetchError = nil
            budget.record(snapshot.rateLimits, at: clock.now)
            let listings = self.listings(for: projects, in: snapshot, configuration: configuration)
            var notifications: [PostedNotification] = []
            let listed = listedPings
            appStateStore.update { state in
                notifications = Self.notify(
                    snapshot: snapshot,
                    listings: listings,
                    projects: projects,
                    machines: Self.machineSettings(configuration),
                    pings: listed,
                    state: &state,
                    at: now
                )
                state.attention.prune(present: snapshot.items.values.joined(), at: now)
            }
            var built = MenuModel.build(
                listings: listings,
                snapshot: snapshot,
                configuration: configuration,
                state: appStateStore.state,
                expanded: expandedGroups,
                notes: notesMenuState,
                now: clock.now
            )
            let machines = Set(configuration.remote.machines)
            let folds = built.foldsToKeep(appStateStore.state.collapsedGroups)
                .union(appStateStore.state.collapsedGroups.filter { machines.contains($0.project) })
            appStateStore.update { $0.collapsedGroups = folds }
            built.foldedGroups = folds
            built.machineNotices = MachineNotice.notices(remote)
            built.refreshDelay = menu.refreshDelay
            built.rateIndicator = menu.rateIndicator
            menu = built
            publishRateStatus()
            refreshEnded = true
            followBannerConditions()
            for notification in notifications {
                await notifier.post(notification)
            }
        } catch GitHubError.unauthorized {
        } catch is CancellationError {
        } catch {
            guard current == session else { return }
            let failure = (error as? GitHubError) ?? .network(error.localizedDescription)
            rebuildMenu(configuration)
            fetchError = failure
            budget.record(failure, at: clock.now)
            menu.fetchError = failure
            publishRateStatus()
            refreshEnded = true
            followBannerConditions()
        }
    }

    private static func notify(
        snapshot: Snapshot,
        listings: [String: [Item]],
        projects: [ProjectSettings],
        machines: [ProjectSettings],
        pings: [Ping],
        state: inout AppState,
        at now: Date
    ) -> [PostedNotification] {
        let events = EventDetector.events(known: state.known, snapshot: snapshot, projects: projects)
            + EventDetector.pingEvents(listings: listings, projects: projects + machines)
        let notifications = select(events, listings: listings, projects: projects + machines, viewer: snapshot.viewerLogin, state: &state, at: now)
        state.known = state.known.updated(with: snapshot, projects: projects)
        state.notified.prune(present: Array(state.known.items.keys) + pings.map(\.item.id), at: now)
        return notifications
    }

    private static func select(
        _ events: [Event],
        listings: [String: [Item]],
        projects: [ProjectSettings],
        viewer: String?,
        state: inout AppState,
        at now: Date
    ) -> [PostedNotification] {
        let settings = Dictionary(projects.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
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
            let filed = occurrences.filter { listed[$0.project]?.contains($0.item.id) == true && settings[$0.project] != nil }
            let unfiled = !filed.isEmpty && filed.allSatisfy(\.isInMachineSection)
            if unfiled && state.notified.passedOverUnfiled(first) { continue }
            let selected = filed.first { event in
                settings[event.project].map { NotificationRules.shouldNotify(event, settings: $0, viewer: viewer) } ?? false
            }
            if let selected {
                var notification = NotificationRules.notification(for: selected)
                notification.project = settings[selected.project]?.title ?? selected.project
                notifications.append(notification)
            }
            if unfiled && selected == nil {
                state.notified.passOverUnfiled(first, at: now)
            } else {
                state.notified.insert(first, at: now)
            }
        }
        return notifications
    }

    private func nextDelay() -> RefreshDelay {
        let configuration = configStore.lastValid
        return budget.nextDelay(
            configured: configuration.refreshInterval,
            sharePercent: configuration.rateLimit.maxSharePercent,
            at: clock.now
        )
    }

    @discardableResult
    private func publishRateStatus() -> RefreshDelay {
        let delay = nextDelay()
        menu.refreshDelay = delay
        let configuration = configStore.lastValid
        let showsRuns = configuration.projects.contains { configuration.settings(for: $0).shows(.workflowRun) }
        menu.rateIndicator = budget.indicator(
            show: configuration.rateLimit.show,
            in: showsRuns ? [.graphql, .rest] : [.graphql],
            at: clock.now
        )
        return delay
    }

    private func armTimer() {
        guard phase.canRefresh else {
            timer.disarm()
            return
        }
        let delay = publishRateStatus()
        var seconds = delay.seconds(from: clock.now)
        if delay.isPaused { seconds = min(seconds, configStore.lastValid.refreshInterval) }
        timer.arm(after: seconds) { [weak self] in
            await self?.refresh()
        }
    }

    /// Opens the row's item on GitHub in the browser and marks it seen. A
    /// ping's row runs the ping's action instead (`runAction(ofPing:)`).
    /// Returns the work still running (a ping's action), for tests to
    /// await; the app doesn't wait for it.
    @discardableResult
    public func open(_ row: MenuRow) -> Task<Void, Never> {
        if row.kind == .note {
            actions.open(row.url)
            return Task {}
        }
        if let ping = row.item.ping {
            guard ping.machine == nil else { return runAction(ofRemotePing: row.item.url) }
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

    /// Opens a repository's page for one kind on GitHub in the browser (a
    /// click on a header's count chip, or a choice from its menu):
    /// `MenuSection.pageLinks(for:)`. It marks nothing seen.
    public func openPage(_ link: PageLink) {
        actions.open(link.url)
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
    /// the ping's action, as its row does; a remote ping's goes the way its
    /// listed row's click does (`open(_:)`), and does nothing once no row
    /// lists it. Returns the work still running (a ping's action), for
    /// tests to await.
    @discardableResult
    public func openNotification(_ itemURL: URL) -> Task<Void, Never> {
        guard itemURL != ControlNotice.panelURL else { return Task {} }
        guard !NoticeRules.isNoticeURL(itemURL) else { return runAction(ofNotice: NoticeRules.click(from: itemURL)) }
        if let ping = Ping.id(from: itemURL) { return runAction(ofPing: ping) }
        guard Ping.remote(from: itemURL) == nil else { return runAction(ofRemotePing: itemURL) }
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

    /// Posts app control's `notice` (a lease that started or ended) when the
    /// last valid configuration's top-level rules select it
    /// (`NotificationRules.shouldNotify(_:configuration:)`). Nothing is
    /// recorded: the app hands over each start and end once.
    public func notify(_ notice: ControlNotice) async {
        guard NotificationRules.shouldNotify(notice, configuration: configStore.lastValid) else { return }
        await notifier.post(NotificationRules.notification(for: notice, at: clock.now))
    }

    /// Answers an agent's notice request (`shipyard notice send`) with the
    /// verdict its command exits by: a notice is shown (`show(_:)`), a
    /// withdrawal done (`withdrawNotice(id:)`).
    public func receive(_ request: NoticeRequest) async -> NoticeVerdict {
        switch request {
        case .show(let notice): return await show(notice)
        case .withdraw(let id): return await withdrawNotice(id: id)
        }
    }

    /// Shows an agent's `notice` (`shipyard notice send`) when the last valid
    /// configuration files it under a project whose rules select
    /// `agent.notice` (`NoticeRules`), and says what came of it: the
    /// verdict the agent's command exits by. Nothing is stored, counted or
    /// listed. A notice with an `id` is posted under it
    /// (`NoticeRules.notificationID`), replacing one still shown under it;
    /// one without is its own notification, never replacing another.
    /// A notice taken off a remote machine names it (`machine`, its Herdr
    /// label), so a Herdr click or button focuses the pane there, as a
    /// remote ping's does.
    public func show(_ notice: Notice, from machine: String? = nil) async -> NoticeVerdict {
        let resolved = resolvedRepositories ?? repositoriesStore.load()
        resolvedRepositories = resolved
        switch NoticeRules.project(for: notice, configuration: configStore.lastValid, resolved: resolved) {
        case .failure(let refusal):
            return .refused(refusal.message)
        case .success(let project):
            guard await notifier.canShow() else { return .refused(NoticeRules.notificationsOff) }
            let id = NoticeRules.notificationID(notice.id ?? UUID().uuidString.lowercased())
            await notifier.post(NoticeRules.notification(for: notice, project: project, id: id, machine: machine))
            return .shown
        }
    }

    /// Takes the notice shown under `id` (its `--id`) out of Notification
    /// Center (`shipyard notice withdraw <id>`). Nothing is kept of a
    /// notice, so one gone already, or never shown, is no error: always `.shown`.
    public func withdrawNotice(id: String) async -> NoticeVerdict {
        await notifier.removeDelivered(id: NoticeRules.notificationID(id))
        return .shown
    }

    /// Answers a notice request from another machine, which the app's
    /// tailnet listener received with `login`, the `Tailscale-User-Login`
    /// that `tailscale serve` put on the request (ADR 0010). It's taken only
    /// when `login` is exactly the Mac's own Tailscale login, looked up now;
    /// then it's answered as one from the Mac (`receive(_:)`): a notice
    /// shown, a withdrawal done. Without a login, with another, or while the
    /// Mac's own can't be learned, it's refused and nothing changes. A
    /// notice whose click or a button focuses Herdr is refused too
    /// (`TailnetWire.herdrRefusal`): the command refuses it before sending,
    /// and this catches one sent another way.
    public func receive(_ request: NoticeRequest, from login: String?) async -> NoticeVerdict {
        guard let login, !login.isEmpty else { return .refused(NoticeRules.noLogin) }
        switch await tailnet.ownLogin() {
        case .failure(let unknown):
            return .refused(NoticeRules.ownLoginUnknown(unknown.reason))
        case .success(let own) where own != login:
            return .refused(NoticeRules.otherLogin(login))
        case .success:
            if case .show(let notice) = request, notice.focusesHerdr { return .refused(TailnetWire.herdrRefusal) }
            return await receive(request)
        }
    }

    /// The port on 127.0.0.1 the app listens on for notices from other
    /// machines, as the last valid configuration's `[notices]` says; `nil`
    /// unless `listen = true`, so nothing listens unless the user asked.
    /// Set by every read of the configuration (`publishConfigStatus`), before
    /// any GitHub request, and observed: the app follows its changes, so the
    /// listener never waits on a refresh.
    public private(set) var noticeListenerPort: Int?

    /// Marks the row's item seen without opening it (⌥-click): it needs
    /// attention again only once it changes. A ping's action isn't run,
    /// and its failure, if it had one, is cleared.
    public func markSeen(_ row: MenuRow) {
        guard row.kind != .note else { return }
        if let ping = row.item.ping {
            if ping.machine == nil { markPingsSeen([ping]) } else { markRemoteSeen([ping]) }
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
        let remote = rows.compactMap(\.item.ping).filter { $0.machine != nil }
        if !remote.isEmpty { markRemoteSeen(remote) }
        let items = rows.filter { $0.item.ping == nil }.map(\.item)
        guard !items.isEmpty else { return }
        updateAppState { state in
            for item in items { state.attention.markSeen(item, at: now) }
        }
    }

    /// Removes the row's ping now (the hover ✕, or ⌫ on the selected
    /// row), seen or not, with any failure on it, and takes its
    /// notification out of Notification Center. Any other row stays: only
    /// pings can be dismissed. A remote ping is hidden on the Mac until its
    /// machine stops listing that instance (`RemotePingMarks`): only its
    /// agent can withdraw it. Returns the removal still running, for tests
    /// to await; the app doesn't wait for it.
    @discardableResult
    public func dismiss(_ row: MenuRow) -> Task<Void, Never> {
        guard let ping = row.item.ping else { return Task {} }
        guard ping.machine == nil else {
            let id = ping.item.id
            appStateStore.update { state in
                state.remotePings.dismiss(ping)
                leftBanners += state.notified.remove(itemID: id) { _ in true }
            }
            rebuildMenu(configStore.lastValid)
            return Task { await removeLeftBanners() }
        }
        try? pingStore.remove(id: ping.id)
        listPings()
        return Task { await removeLeftBanners() }
    }

    /// Reads the ping store again and, when a ping arrived, changed or
    /// went, lists the pings at once from the last snapshot: no GitHub
    /// request. A new ping a project lists posts its `ping.sent`
    /// notification when the project's rules select it; a replaced one
    /// (same id, same instance) doesn't again. A ping that went (withdrawn
    /// with the CLI) takes its notification out of Notification Center.
    /// The app's watcher on the store calls this.
    public func reloadPings() async {
        guard listPings() else { return }
        await removeLeftBanners()
        await notifyNewPings()
    }

    private func notifyNewPings() async {
        let configuration = configStore.lastValid
        let configured = configuration.projects.map(configuration.settings(for:))
        let listings = self.listings(for: configured, in: snapshot, configuration: configuration)
        let projects = configured + Self.machineSettings(configuration)
        let events = EventDetector.pingEvents(listings: listings, projects: projects)
        let notified = appStateStore.state.notified
        let unhandled = events.filter { !notified.contains($0) && !($0.isInMachineSection && notified.passedOverUnfiled($0)) }
        guard !unhandled.isEmpty else { return }
        let now = clock.now
        let viewer = snapshot?.viewerLogin
        var notifications: [PostedNotification] = []
        appStateStore.update { state in
            notifications = Self.select(unhandled, listings: listings, projects: projects, viewer: viewer, state: &state, at: now)
        }
        for notification in notifications {
            await notifier.post(notification)
        }
    }

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
                outcome = await runHerdr(target, inSession: ping.herdrSession, sentFrom: ping.terminal)
            } else {
                outcome = await actions.run(action)
            }
            switch outcome {
            case .done:
                markPingsSeen([ping])
            case .failed(let reason, let detail):
                try? pingStore.recordFailure(ping, reason: reason, detail: detail)
                listPings()
            }
        }
    }

    private func runAction(ofRemotePing url: URL) -> Task<Void, Never> {
        guard let ping = remote.pings.first(where: { $0.item.url == url }), let machine = ping.machine else {
            return Task {}
        }
        guard let action = ping.action else {
            markRemoteSeen([ping])
            return Task {}
        }
        return Task {
            let outcome: ActionOutcome
            if case .herdr(let target) = action {
                outcome = await runHerdr(target, on: machine)
            } else {
                outcome = await actions.run(action)
            }
            switch outcome {
            case .done:
                markRemoteSeen([ping])
            case .failed(let reason, let detail):
                remote.recordFailure(ping, reason: reason, detail: detail)
                rebuildMenu(configStore.lastValid)
            }
        }
    }

    private func runAction(ofNotice click: NoticeRules.Click?) -> Task<Void, Never> {
        guard let click else { return Task {} }
        return Task {
            if case .herdr(let target) = click.action, let machine = click.machine {
                _ = await runHerdr(target, on: machine)
            } else if case .herdr(let target) = click.action {
                _ = await runHerdr(target, inSession: click.herdrSession, sentFrom: click.terminal)
            } else {
                _ = await actions.run(click.action)
            }
        }
    }

    private func runHerdr(_ target: String, on machine: String? = nil, inSession session: String? = nil, sentFrom: String? = nil) async -> ActionOutcome {
        let focused = await herdr.focus(target, on: machine, inSession: session)
        guard focused == .done, let terminal = configStore.lastValid.herdr.terminal ?? sentFrom else { return focused }
        return await actions.run(.app(terminal))
    }

    private var listedPings: [Ping] { pings + appStateStore.state.remotePings.apply(to: remote.pings) }

    private func markRemoteSeen(_ listed: [Ping]) {
        let now = clock.now
        let sendings = listed.compactMap { seen -> Ping? in
            guard let current = remote.pings.first(where: { $0.item.id == seen.item.id }) else { return nil }
            var unfiled = seen
            unfiled.projects = current.projects
            unfiled.repository = current.repository
            return unfiled.isSameSending(as: current) ? current : nil
        }
        guard !sendings.isEmpty else { return }
        for ping in sendings { remote.clearFailure(ping) }
        appStateStore.update { state in
            for ping in sendings {
                var seen = ping
                seen.failure = nil
                state.remotePings.markSeen(seen, at: now)
            }
        }
        rebuildMenu(configStore.lastValid)
    }

    private func pruneRemoteMarks() {
        guard !appStateStore.state.remotePings.marks.isEmpty else { return }
        let listed = remote.pings
        let unknown = Set(remote.machines.filter { $0.answered == nil }.map(\.label))
        let truncated = Set(remote.machines.filter(\.truncated).map(\.label))
        appStateStore.update { $0.remotePings.prune(listed: listed, keeping: unknown, truncated: truncated) }
    }

    private func filedPings(_ configuration: Configuration) -> [Ping] {
        let remotePings = appStateStore.state.remotePings.apply(to: remote.pings)
        let pings = pings.map { ProjectFiling.named($0, configuration: configuration) }
        guard remotePings.contains(where: { $0.projects.isEmpty && $0.repository != nil }) else {
            return pings + remotePings.map { ProjectFiling.named($0, configuration: configuration) }
        }
        let resolved = resolvedRepositories ?? repositoriesStore.load()
        resolvedRepositories = resolved
        return pings + remotePings.map { ProjectFiling.filed(remote: $0, configuration: configuration, resolved: resolved) }
    }

    private func listings(for projects: [ProjectSettings], in snapshot: Snapshot?, configuration: Configuration) -> [String: [Item]] {
        let pings = filedPings(configuration)
        numberPings(pings, projects: projects.map(\.slug), configuration: configuration)
        return Listing.listings(
            for: projects,
            in: snapshot,
            pings: pings,
            machines: configuration.remote.machines.map(configuration.settings(forMachine:)),
            numbers: appStateStore.state.pingNumbers,
            notes: notes,
            now: clock.now
        )
    }

    private func numberPings(_ pings: [Ping], projects: [String], configuration: Configuration) {
        guard configStore.error == nil || followsConfiguredMachines else { return }
        let heard = Set(remote.machines.filter { $0.answered != nil || $0.failure != nil }.map(\.label))
        guard appStateStore.state.pingNumbers != nil || Set(configuration.remote.machines).isSubset(of: heard) else { return }
        let now = clock.now
        let present = pings.filter { !Self.hasLeft($0, in: configuration, at: now) }
        let sections = Listing.sections(of: present, projects: projects, machines: configuration.remote.machines)
        let answered = Set(remote.machines.filter { $0.answered != nil }.map(\.label))
        let truncated = Set(remote.machines.filter(\.truncated).map(\.label))
        let configured = Set(configuration.remote.machines)
        let listedURLs = Set(remote.pings.map(\.item.id))
        let follows = followsConfiguredMachines
        appStateStore.update { state in
            var numbers = state.pingNumbers ?? PingNumbers()
            numbers.number(sections) { url in
                guard let machine = URL(string: url).flatMap(Ping.remote(from:))?.machine else { return true }
                if follows && !configured.contains(machine) { return true }
                return answered.contains(machine) && (!truncated.contains(machine) || listedURLs.contains(url))
            }
            state.pingNumbers = numbers
        }
    }

    private static func machineSettings(_ configuration: Configuration) -> [ProjectSettings] {
        configuration.remote.machines.map(configuration.settings(forMachine:))
    }

    private func followMachines() async {
        let labels = configStore.lastValid.remote.machines
        let fromFile = configStore.error == nil
        guard labels != remote.labels || (fromFile && !followsConfiguredMachines) else { return }
        if fromFile { followsConfiguredMachines = true }
        remote.follow(labels)
        pruneRemoteMarks()
        forgetLeftPings(stored: pings)
        rebuildMenu(configStore.lastValid)
        await removeLeftBanners()
        armMachineTimer(after: 0)
    }

    /// Asks every remote machine for its pings at once, through Herdr
    /// (`RemotePingReader`), and lists each machine's as it answers, so a
    /// slow one never holds up another. A machine that fails keeps its
    /// last pings and records why. A machine whose pings changed posts its
    /// new pings' `ping.sent` notifications, once per sending, and takes
    /// the notifications of the pings it no longer lists out of
    /// Notification Center. A machine that answered then hands over the
    /// notices its agents left for the Mac, shown by the user's rules
    /// unless they waited too long. No GitHub request is made. Then the
    /// machine timer comes back in `machinePollInterval`. Its timer calls
    /// this. A call while a poll runs returns at once, and the running poll
    /// goes again when it's done, so a machine added meanwhile is asked.
    public func pollMachines() async {
        guard !remote.labels.isEmpty, machineGate.begin() else { return }
        repeat {
            await pollMachinesOnce()
        } while machineGate.finish() && machineGate.begin()
        pruneRemoteMarks()
        if listedPings.contains(where: { $0.machine != nil && $0.seen != nil }) || appStateStore.state.pingNumbers == nil {
            rebuildMenu(configStore.lastValid)
            forgetLeftPings(stored: pings)
            await removeLeftBanners()
        }
        armMachineTimer(after: Self.machinePollInterval)
    }

    private enum MachineAnswer: Sendable {
        case pings(String, Result<PingList, RemotePingReader.Failure>)
        case notices(String, [QueuedNotice])
    }

    private func pollMachinesOnce() async {
        let reader = remoteReader
        await withTaskGroup(of: MachineAnswer.self) { group in
            for label in remote.labels {
                group.addTask { .pings(label, await reader.list(machine: label)) }
            }
            while let answer = await group.next() {
                switch answer {
                case .pings(let label, let result):
                    await record(result, for: label)
                    guard case .success = result else { continue }
                    group.addTask { .notices(label, await reader.takeNotices(machine: label)) }
                case .notices(let label, let queued):
                    await showQueued(queued, from: label)
                }
            }
        }
    }

    private func record(_ result: Result<PingList, RemotePingReader.Failure>, for label: String) async {
        let before = remote.machine(label)
        remote.record(result, for: label, at: clock.now)
        menu.machineNotices = MachineNotice.notices(remote)
        let after = remote.machine(label)
        let firstAnswer = before?.answered == nil && after?.answered != nil
        guard after?.pings != before?.pings || firstAnswer else { return }
        rebuildMenu(configStore.lastValid)
        forgetLeftPings(stored: pings)
        await removeLeftBanners()
        await notifyNewPings()
    }

    private func showQueued(_ queued: [QueuedNotice], from machine: String) async {
        for notice in queued where NoticeRules.isFresh(notice, at: clock.now) {
            _ = await show(notice.notice, from: machine)
        }
    }

    private func armMachineTimer(after seconds: TimeInterval) {
        guard !remote.labels.isEmpty else {
            machineTimer.disarm()
            return
        }
        machineTimer.arm(after: seconds) { [weak self] in
            await self?.pollMachines()
        }
    }

    @discardableResult
    private func listPings() -> Bool {
        let configuration = configStore.lastValid
        let now = clock.now
        let stored = pingStore.all().compactMap { ping -> Ping? in
            guard Self.hasLeft(ping, in: configuration, at: now) else { return ping }
            guard (try? pingStore.removeIfUnchanged(ping)) == false else { return nil }
            return pingStore.ping(id: ping.id)
        }
        forgetLeftPings(stored: stored)
        guard stored != pings else { return false }
        pings = stored
        rebuildMenu(configStore.lastValid)
        return true
    }

    private func forgetLeftPings(stored: [Ping]) {
        let answered = Set(remote.machines.filter { $0.answered != nil }.map(\.label))
        let configuration = configStore.lastValid
        let configured = Set(configuration.remote.machines)
        let truncated = Set(remote.machines.filter(\.truncated).map(\.label))
        let listedURLs = Set(remote.pings.map(\.item.id))
        let now = clock.now
        let listedRemote = filedPings(configuration).filter { $0.machine != nil && !Self.hasLeft($0, in: configuration, at: now) }
        let current = Dictionary(
            (stored + listedRemote).map { ($0.item.id, Event(kind: .pingSent, project: "", item: $0.item, occurrence: $0.instance ?? "")) },
            uniquingKeysWith: { first, _ in first }
        )
        func isCurrent(_ recorded: String, _ url: String) -> Bool {
            current[url].map { NotifiedEvents.records(recorded, as: $0) } ?? false
        }
        let pingRecords = appStateStore.state.notified.records.filter { key, record in
            guard let url = URL(string: key) else { return false }
            if Ping.id(from: url) == nil {
                guard let machine = Ping.remote(from: url)?.machine else { return false }
                let removed = followsConfiguredMachines && !configured.contains(machine)
                guard removed || (answered.contains(machine) && (!truncated.contains(machine) || listedURLs.contains(key))) else { return false }
            }
            return record.events.contains { !isCurrent($0, key) }
        }
        guard !pingRecords.isEmpty else { return }
        appStateStore.update { state in
            for key in pingRecords.keys.sorted() {
                leftBanners += state.notified.remove(itemID: key) { !isCurrent($0, key) }
            }
        }
    }

    private func removeLeftBanners() async {
        let banners = leftBanners
        leftBanners = []
        for id in banners {
            await notifier.removeDelivered(id: id)
        }
    }

    private static func hasLeft(_ ping: Ping, in configuration: Configuration, at now: Date) -> Bool {
        guard ping.seen != nil else { return false }
        let names = ping.machine != nil && ping.projects.isEmpty ? [ping.machine ?? ""] : ping.projects
        let windows = names.map { name in
            configuration.project(named: name)
                .map { configuration.settings(for: $0).pings.seenWindow }
                ?? configuration.defaults.pings.seenWindow
        }
        return windows.allSatisfy { !ping.isListed(seenWindow: $0, at: now) }
    }

    private func markPingsSeen(_ listed: [Ping]) {
        let now = clock.now
        for ping in listed { try? pingStore.markSeen(ping, at: now) }
        listPings()
    }

    /// The menu opened: the notes are read again, so one just written
    /// shows (`refreshNotes()`), and why a note couldn't be started last
    /// time goes. Nothing else is fetched: GitHub's items keep to their timer.
    public func panelOpened() async {
        if !newNoteErrors.isEmpty {
            newNoteErrors = [:]
            rebuildMenu(configStore.lastValid)
        }
        await refreshNotes()
    }

    /// The new-note icon on `project`'s header: creates the project's
    /// notes database under the entry page when it has none, then an empty
    /// note in it (`NotesReader.startNote`), opens the note in Notion
    /// through the action port, and reads the notes again so the menu
    /// lists it. A failure opens nothing and shows on the project as
    /// "new note: <why>". A click while a note is being started in the
    /// project does nothing. Answers whether a note was opened.
    @discardableResult
    public func startNote(in project: String) async -> Bool {
        guard !startingNotes.contains(project) else { return false }
        guard readsNotes, let notionRoute else {
            failNewNote(in: project, .notRead)
            return false
        }
        startingNotes.insert(project)
        newNoteErrors[project] = nil
        rebuildMenu(configStore.lastValid)
        let title = configStore.lastValid.projects.first { $0.slug == project }?.title ?? project
        let result = await notesReader.startNote(in: project, titled: title, client: NotionClient(transport: notionRoute))
        startingNotes.remove(project)
        switch result {
        case .success(let url):
            actions.open(url)
            rebuildMenu(configStore.lastValid)
            await refreshNotes()
            return true
        case .failure(let error):
            failNewNote(in: project, error)
            return false
        }
    }

    private func failNewNote(in project: String, _ error: NewNoteError) {
        newNoteErrors[project] = PanelText.newNoteError(error)
        rebuildMenu(configStore.lastValid)
    }

    private var notesMenuState: NotesMenuState {
        NotesMenuState(canStartNotes: canStartNotes, readErrors: noteErrors, startErrors: newNoteErrors, starting: startingNotes, databases: noteDatabases)
    }

    /// Reads every project's open notes from Notion (`NotesReader`): one
    /// query per project that shows notes and has a database, through
    /// `ntn`, and lists them. A project whose read failed keeps its last
    /// notes and gets an error row; a project without a database lists
    /// none. Then the notes timer comes back in `notesInterval`. A run that
    /// reads no notes (`readsNotes`) lists none. A call while a read runs
    /// makes one more after it.
    public func refreshNotes() async {
        guard readsNotes else {
            forgetNotes()
            notesTimer.disarm()
            return
        }
        guard notesGate.begin() else { return }
        repeat {
            await readNotes()
        } while notesGate.finish() && notesGate.begin()
        if readsNotes { armNotesTimer(after: Self.notesInterval) }
    }

    /// Checks the notes workspace through `ntn`, as the menu reads it, for
    /// each project that shows notes (`NotesCheck`); `nil` while the app
    /// reads no notes (Notion not connected, or a demo run), which never
    /// runs `ntn` for it.
    public func checkNotes() async -> NotesCheckReport? {
        guard readsNotes, let notionRoute else { return nil }
        let configuration = configStore.lastValid
        let projects = configuration.projects.filter { configuration.settings(for: $0).notes.show }.map(\.title)
        return await NotesCheck.run(projects: projects, client: NotionClient(transport: notionRoute))
    }

    /// Whether the app lists notes now: the user's, once Notion is
    /// connected, never in a demo run (`AppFiles.notionRoute`); a demo
    /// run's example notes, when it has example items (`demoItems`).
    public var readsNotes: Bool { demoItems != nil || (canReadNotes && notionConnected) }

    /// Whether this run can read notes at all: always in the app, never in
    /// a demo run, which has no route to Notion.
    public var canReadNotes: Bool { notionRoute != nil }

    private var canStartNotes: Bool {
        readsNotes && notesBlocked?.isNtn != true
    }

    /// Whether the settings menu marks Notion set up: connected, and ntn
    /// was there and logged in at the latest read.
    public var notionIsSetUp: Bool { canStartNotes }

    /// The Notion view's check: whether `ntn` is there and logged in, its
    /// workspace's name and whether that workspace has the Shipyard Notes
    /// page (`NotionStatus`), through the route the notes are read
    /// through. It runs `ntn` whether Notion is connected or not, since the
    /// user opened the view (or pressed Check again) to ask; nothing else
    /// does before Connect with ntn. A demo run asks nothing.
    public func checkNotion() async {
        notionCheck += 1
        let check = notionCheck
        notionStatus = nil
        guard let notionRoute else {
            notionStatus = .notRead
            return
        }
        let status = await NotionStatus.check(NotionClient(transport: notionRoute))
        guard check == notionCheck else { return }
        notionStatus = status
    }

    /// Connect with ntn: keeps the flag in the app state, so a restart
    /// reads the notes too, shows the new-note icons and reads the notes
    /// at once. A demo run, which reads no notes, changes nothing.
    public func connectNotion() async {
        guard canReadNotes, !notionConnected else { return }
        notesReader.reset()
        setNotionConnected(true)
        rebuildMenu(configStore.lastValid)
        await refreshNotes()
    }

    /// Disconnect: clears the flag, stops the notes' timer and lists no
    /// notes, notes banner or new-note icons; `ntn` doesn't run again until
    /// the next Connect with ntn.
    public func disconnectNotion() {
        guard notionConnected else { return }
        setNotionConnected(false)
        notesTimer.disarm()
        newNoteErrors = [:]
        forgetNotes()
        rebuildMenu(configStore.lastValid)
    }

    private func setNotionConnected(_ connected: Bool) {
        notionConnected = connected
        appStateStore.update { $0.notionConnected = connected }
    }

    private func readNotes() async {
        guard readsNotes else { return }
        let configuration = configStore.lastValid
        let shown = configuration.projects.filter { configuration.settings(for: $0).notes.show }
        let projects = shown.map(\.slug)
        let reading: NotesReading
        if shown.isEmpty {
            reading = .read([:])
        } else if let demoItems {
            reading = demoItems.notes(for: shown.map { ($0.slug, $0.title) })
        } else if let notionRoute {
            reading = await notesReader.read(projects: shown.map { ($0.slug, $0.title) }, client: NotionClient(transport: notionRoute))
        } else {
            return
        }
        guard readsNotes else { return }
        var read: [String: [Note]] = [:]
        var errors: [String: String] = [:]
        let blocked = NotesNotice(reading)
        if blocked != notesBlocked {
            notesBlocked = blocked
            rebuildMenu(configStore.lastValid)
        }
        switch reading {
        case _ where blocked != nil:
            break
        case .noEntryPage:
            break
        case .failed(let error):
            for project in projects {
                read[project] = notes[project]
                errors[project] = PanelText.noteError(error)
            }
        case .read(let results):
            for (project, result) in results {
                switch result {
                case .success(let listed):
                    read[project] = listed
                case .failure(let error):
                    read[project] = notes[project]
                    errors[project] = PanelText.noteError(error)
                }
            }
        }
        let databases = notesReader.databases.compactMapValues(NotionClient.pageURL)
        guard read != notes || errors != noteErrors || databases != noteDatabases else { return }
        notes = read
        noteErrors = errors
        noteDatabases = databases
        rebuildMenu(configStore.lastValid)
    }

    private func forgetNotes() {
        notesReader.reset()
        if notesBlocked != nil { notesBlocked = nil }
        noteDatabases = [:]
        guard !notes.isEmpty || !noteErrors.isEmpty else { return }
        notes = [:]
        noteErrors = [:]
        rebuildMenu(configStore.lastValid)
    }

    private func armNotesTimer(after seconds: TimeInterval) {
        notesTimer.arm(after: seconds) { [weak self] in
            await self?.refreshNotes()
        }
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

    private func updateAppState(_ body: (inout AppState) -> Void) {
        appStateStore.update(body)
        applyAttention(configStore.lastValid)
    }

    private func rebuildMenu(_ configuration: Configuration) {
        let listings = self.listings(for: configuration.projects.map(configuration.settings(for:)), in: snapshot, configuration: configuration)
        var rebuilt = MenuModel.build(
            listings: listings,
            snapshot: snapshot,
            configuration: configuration,
            state: appStateStore.state,
            expanded: expandedGroups,
            notes: notesMenuState,
            now: clock.now
        )
        rebuilt.fetchError = menu.fetchError
        rebuilt.refreshDelay = menu.refreshDelay
        rebuilt.rateIndicator = menu.rateIndicator
        rebuilt.machineNotices = MachineNotice.notices(remote)
        if phase != .ready { rebuilt.menuBarLabel = .hidden }
        menu = rebuilt
    }

    private func applyAttention(_ configuration: Configuration) {
        menu.applyAttention(appStateStore.state, configuration: configuration)
        if phase != .ready { menu.menuBarLabel = .hidden }
    }

    private var currentBanners: [PanelBanner] {
        PanelBanner.list(
            lease: lease,
            configError: configError,
            configWarnings: configWarnings,
            themeIssues: themeIssues,
            ready: phase == .ready,
            menu: menu,
            notes: notesNotice,
            notificationsOff: notificationsAreOff
        )
    }

    private var notesNotice: NotesNotice? {
        let configuration = configStore.lastValid
        guard readsNotes, configuration.projects.contains(where: { configuration.settings(for: $0).notes.show }) else { return nil }
        return notesBlocked
    }

    /// The banners the panel shows at `now`, in order: those whose
    /// condition holds, less the ones the user snoozed until after `now`.
    public func banners(at now: Date) -> [PanelBanner] {
        bannerSnoozes.shown(currentBanners, at: now)
    }

    /// When a snoozed banner may show again, soonest first, so an open
    /// panel brings it back at that moment without a refresh.
    public var bannerSnoozeEnds: [Date] { bannerSnoozes.endsAfter(clock.now) }

    /// The banner's dismiss button: hides the banner `key` for `[banners]
    /// snooze`, an hour by default. A banner that isn't shown is left alone.
    public func dismissBanner(_ key: String) {
        let now = clock.now
        guard banners(at: now).contains(where: { $0.id == key }) else { return }
        let length = configStore.lastValid.banners.snoozeDuration
        changeBannerSnoozes { $0.snooze(key, at: now, for: length) }
    }

    private func followBannerConditions() {
        guard !bannerSnoozes.ends.isEmpty else { return }
        restoredSnoozes = restoredSnoozes.filter { !bannerConditionIsKnown($0) }
        let current = Set(currentBanners.map(\.id)).union(restoredSnoozes)
        let now = clock.now
        changeBannerSnoozes { $0.follow(current: current, at: now) }
    }

    private func changeBannerSnoozes(_ body: (inout BannerSnoozes) -> Void) {
        var next = bannerSnoozes
        body(&next)
        guard next != bannerSnoozes else { return }
        bannerSnoozes = next
        appStateStore.update { $0.bannerSnoozes = next }
    }

    private func bannerConditionIsKnown(_ key: String) -> Bool {
        guard configurationRead else { return false }
        switch key {
        case "delay", "paused", "fetch":
            return refreshEnded
        case "notifications":
            return notifierReported
        case _ where key.hasPrefix(Self.machineBannerPrefix):
            let label = String(key.dropFirst(Self.machineBannerPrefix.count))
            return remote.machine(label).map { $0.answered != nil || $0.failure != nil } ?? false
        default:
            return true
        }
    }

    private static let machineBannerPrefix = "machine-"

    private func apply(_ event: LifecycleEvent) {
        phase = phase.after(event)
    }
}
