import Foundation

/// The orchestrator: owns the lifecycle phase and handles the user's actions.
/// The app builds one with its adapters and the panel draws from it.
///
/// It signs in (a stored or `gh` token, else the device flow), signs out on
/// any 401, follows the configuration between `needsProjects` and `ready`,
/// and in `ready` runs the refresh pipeline: fetch every project's items in
/// one GraphQL request, publish the menu model, and ask the rate budget when
/// to run next.
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
    private let tokenStore: any TokenStore
    private let urlOpener: any URLOpening
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
        tokenStore: any TokenStore,
        urlOpener: any URLOpening,
        gh: any GhTokenLookup = GhCLI(),
        transport: any HTTPTransport = URLSessionTransport(),
        clock: any WallClock = SystemClock(),
        timer: any RefreshTimer = TaskRefreshTimer(),
        sleep: @escaping DeviceFlow.Sleep = DeviceFlow.systemSleep,
        oauthClientID: String = OAuthApp.clientID
    ) {
        self.configStore = configStore
        self.tokenStore = tokenStore
        self.urlOpener = urlOpener
        self.clock = clock
        self.timer = timer
        self.tokenProvider = TokenProvider(store: tokenStore, gh: gh)
        self.deviceFlow = DeviceFlow(clientID: oauthClientID, transport: transport, clock: clock, sleep: sleep)
        self.transport = transport
    }

    /// Loads the configuration and signs in with the token store's token or
    /// `gh`'s, if either has one; otherwise stays signed out. Signing in with
    /// projects runs the first refresh.
    public func start() async {
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
        if case .changed(let configuration) = result {
            apply(.configurationChanged(hasProjects: configuration.hasProjects))
            if phase.canRefresh {
                await refresh()
            } else {
                timer.disarm()
            }
        }
        return result
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
            menu = MenuModel.build(snapshot: snapshot, configuration: configuration, now: clock.now)
            publishRateStatus()
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

    /// Opens the row's item on GitHub in the browser.
    public func open(_ row: MenuRow) {
        urlOpener.open(row.url)
    }

    private func apply(_ event: LifecycleEvent) {
        phase = phase.after(event)
    }
}
