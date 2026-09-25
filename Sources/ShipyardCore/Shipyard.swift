import Foundation

/// The orchestrator: owns the lifecycle phase and handles the user's actions.
/// The app builds one with its adapters and the panel draws from it.
///
/// This holds the sign-in part of the lifecycle: finding a token, the device
/// flow, sign-out, and signing out when GitHub answers 401. The refresh
/// pipeline builds on it.
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

    public let configStore: ConfigStore
    private let tokenStore: any TokenStore
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
        gh: any GhTokenLookup = GhCLI(),
        transport: any HTTPTransport = URLSessionTransport(),
        clock: any WallClock = SystemClock(),
        sleep: @escaping DeviceFlow.Sleep = DeviceFlow.systemSleep,
        oauthClientID: String = OAuthApp.clientID
    ) {
        self.configStore = configStore
        self.tokenStore = tokenStore
        self.tokenProvider = TokenProvider(store: tokenStore, gh: gh)
        self.deviceFlow = DeviceFlow(clientID: oauthClientID, transport: transport, clock: clock, sleep: sleep)
        self.transport = transport
    }

    /// Loads the configuration and signs in with the token store's token or
    /// `gh`'s, if either has one; otherwise stays signed out.
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
        apply(.signedOut)
    }

    private func apply(_ event: LifecycleEvent) {
        phase = phase.after(event)
    }
}
