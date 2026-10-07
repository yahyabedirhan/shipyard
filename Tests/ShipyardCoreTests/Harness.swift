import Foundation
@testable import ShipyardCommand
import ShipyardConfig
@testable import ShipyardPings
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

/// The main test seam: a real `Shipyard` driven end to end over in-memory
/// ports. The network is `StubHTTP` answering from recorded GitHub
/// responses (`Fixtures/`); the configuration lives in a temporary
/// directory and the support folder (app state, pings, resolved
/// repositories) in another, each store where the app puts it (`AppFiles`); the clock, the refresh timer and
/// waiting are manual; the action port, notifier and login item record what
/// they're asked.
///
/// A scenario writes a configuration, registers answers, drives the
/// orchestrator (`start`, `timer.fire()`, `reloadConfiguration`, clicks) and
/// asserts on `shipyard.menu` and what the ports recorded (URLs opened,
/// notifications posted, the login item).
@MainActor
struct Harness {
    /// 2026-09-25 12:00:00 UTC, the "now" the fixtures are written against.
    nonisolated static let now = Date(timeIntervalSince1970: 1_790_337_600)
    /// `x-ratelimit-reset` the fixtures' headers carry: 12:42 the same day.
    nonisolated static let rateLimitReset = Date(timeIntervalSince1970: 1_790_340_120)

    nonisolated static let userURL = GitHubClient.apiURL.appendingPathComponent("user")
    nonisolated static let viewerAnswer = StubHTTP.Answer.json(#"{"login":"yabepa","id":42,"type":"User"}"#)
    nonisolated static let unauthorized = StubHTTP.Answer.json(
        #"{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}"#, status: 401
    )

    let stub = StubHTTP()
    let store: InMemoryTokenStore
    let gh: FakeGhLookup
    private let ghToken: String?
    let sleeper = InstantSleeper(clock: ManualClock(Harness.now))
    let timer = ManualTimer()
    /// The remote machines' poll timer, apart from the refresh's.
    let machineTimer = ManualTimer()
    /// The notes' timer, apart from the refresh's.
    let notesTimer = ManualTimer()
    /// ntn, the notes' route into Notion: not installed (no notes) until a
    /// scenario installs and logs it in; logged in, `stub` answers for Notion.
    let ntn: FakeNtnRoute
    let actions = RecordingActions()
    /// The Herdr a ping's `--herdr` action focuses, and the remote
    /// machines are asked through: no tabs or machines until added.
    let herdr = FakeHerdr()
    let notifier = RecordingNotifier()
    /// The Mac's own Tailscale login, as the tailnet listener checks it:
    /// none until a scenario sets one.
    let tailnet = FakeTailnet()
    let loginItem = RecordingLoginItem()
    /// Where this app reads and writes, as the app decides it.
    let files: AppFiles
    /// `config.toml` in a fresh temporary directory.
    nonisolated var configURL: URL { files.config }
    /// The support folder, a fresh temporary directory: app state
    /// (`state.json`), pings, resolved repositories.
    nonisolated var stateDirectory: URL { files.support }
    /// The ping store the CLI and the app share, in `stateDirectory`.
    let pingStore: PingStore
    /// The repositories the app last resolved, for the CLI, in `stateDirectory`.
    let repositoriesStore: ResolvedRepositoriesStore
    let shipyard: Shipyard

    var clock: ManualClock { sleeper.clock }
    /// `state.json` in `stateDirectory`.
    var stateURL: URL { shipyard.appStateStore.url }

    /// A harness with the given token store and `gh` tokens and, when
    /// `config` isn't `nil`, that configuration file.
    /// `clientID` is the OAuth App client ID the device flow uses.
    init(stored: String? = nil, gh ghToken: String? = nil, config: String? = nil, clientID: String = "test-client-id") throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-tests-\(UUID().uuidString)", isDirectory: true)
        let configURL = root.appendingPathComponent("config", isDirectory: true).appendingPathComponent("config.toml")
        let stateDirectory = root.appendingPathComponent("state", isDirectory: true)
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        if let config { try Data(config.utf8).write(to: configURL) }
        self.init(files: AppFiles(config: configURL, support: stateDirectory), store: InMemoryTokenStore(token: stored), ntn: nil, gh: ghToken, clientID: clientID)
    }

    /// The app as launched with `environment` (with `home` for the
    /// user's own folders), signed in with a stored token: its files where
    /// `AppFiles` puts them, as `AppServices` builds them.
    init(launchedWith environment: [String: String], home: URL) {
        // The user's own ntn is installed and logged in, as on the maintainer's Mac.
        self.init(files: AppFiles(environment: environment, home: home), store: InMemoryTokenStore(token: "gho_stored"), ntn: .loggedIn, gh: nil)
    }

    /// A harness over existing configuration and support folders.
    private init(files: AppFiles, store: InMemoryTokenStore, ntn state: FakeNtnRoute.State?, gh ghToken: String?, clientID: String = "test-client-id") {
        self.files = files
        self.store = store
        ntn = FakeNtnRoute(state ?? .missing, notion: stub)
        self.ghToken = ghToken
        gh = FakeGhLookup(token: ghToken)
        let clock = sleeper.clock
        // Read at the harness's time, so a ping's expiry counts from its clock.
        pingStore = PingStore(directory: files.pings, now: { clock.now })
        repositoriesStore = ResolvedRepositoriesStore(directory: files.support)
        shipyard = Shipyard(
            configStore: ConfigurationStore(url: files.config),
            appStateStore: AppStateStore(directory: files.support),
            configStatusStore: ConfigStatusStore(directory: files.support),
            pingStore: pingStore,
            repositoriesStore: repositoriesStore,
            tokenStore: store,
            actions: actions,
            notifier: notifier,
            loginItem: files.loginItem(loginItem),
            gh: gh,
            herdr: herdr.focus,
            remote: herdr.remote,
            transport: stub,
            clock: sleeper.clock,
            timer: timer,
            machineTimer: machineTimer,
            notionRoute: files.notionRoute(ntn),
            notesTimer: notesTimer,
            tailnet: tailnet,
            sleep: sleeper.sleep,
            oauthClientID: clientID
        )
    }

    /// A harness signed in with a stored token, with `config` on disk and
    /// GraphQL answering `answers` in order, after `start()` (which runs the
    /// first refresh when there are projects).
    static func started(config: String, graphQL answers: StubHTTP.Answer...) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(userURL, viewerAnswer)
        if !answers.isEmpty { harness.graphQL(answers) }
        await harness.shipyard.start()
        return harness
    }

    /// The app quit and started again: a new `Shipyard` (and doubles) over
    /// the same configuration file, app-state directory and token store,
    /// with the clock where this one's is, not started yet.
    func relaunched() -> Harness {
        let next = Harness(files: files, store: store, ntn: ntn.current, gh: ghToken)
        next.clock.set(clock.now)
        return next
    }

    /// Notion connected before the app starts, as after Connect with ntn
    /// in an earlier run: the flag in `state.json`, which `start()` reads.
    func connectNotionBeforeStart() {
        shipyard.appStateStore.update { $0.notionConnected = true }
    }

    /// A recorded GraphQL answer from `Fixtures/`, with GitHub's rate-limit headers.
    nonisolated static func fixture(
        _ name: String,
        status: Int = 200,
        remaining: Int = 4990,
        reset: Date = rateLimitReset
    ) throws -> StubHTTP.Answer {
        try .fixture(name, status: status, headers: rateLimitHeaders(remaining: remaining, reset: reset))
    }

    /// The `x-ratelimit-*` headers of a GraphQL response (or, with
    /// `resource: "core"`, a REST one).
    nonisolated static func rateLimitHeaders(
        remaining: Int,
        reset: Date = rateLimitReset,
        resource: String = "graphql"
    ) -> [String: String] {
        [
            "x-ratelimit-limit": "5000",
            "x-ratelimit-remaining": String(remaining),
            "x-ratelimit-used": String(5000 - remaining),
            "x-ratelimit-reset": String(Int(reset.timeIntervalSince1970)),
            "x-ratelimit-resource": resource,
        ]
    }

    /// Answers `POST /graphql` with `answers` in order, the last repeating.
    func graphQL(_ answers: [StubHTTP.Answer]) {
        stub.on("POST", GitHubClient.graphQLURL, answers: answers)
    }

    /// Refreshes, two minutes later, with GitHub answering `answer`.
    func refresh(answering answer: StubHTTP.Answer) async {
        graphQL([answer])
        clock.advance(by: 120)
        await shipyard.refresh()
    }

    /// Every GraphQL request sent.
    var graphQLRequests: [URLRequest] { stub.requests("POST", GitHubClient.graphQLURL) }

    /// The `Authorization` header of every `GET /user`.
    var authorizations: [String?] {
        stub.requests("GET", Self.userURL).map { $0.value(forHTTPHeaderField: "Authorization") }
    }

    /// Replaces the configuration file with `text`.
    func writeConfig(_ text: String) throws {
        try Data(text.utf8).write(to: configURL)
    }

    /// The folder the CLI runs in, as an agent's terminal would be.
    var workingFolder: URL { stateDirectory.deletingLastPathComponent().appendingPathComponent("work", isDirectory: true) }

    /// Runs the `shipyard` CLI with `arguments` (without the program's
    /// name) against this harness's configuration file, resolved
    /// repositories and ping store, at the clock's time, as an agent would
    /// in a terminal: in `workingFolder`, whose git remote `origin` is
    /// `origin` (`nil`: not a git repository), in the Herdr pane
    /// `herdrPane` (`HERDR_PANE_ID`; `nil`: not in Herdr), with any other
    /// environment `variables` (`TERM_PROGRAM`, say).
    @discardableResult
    func cli(_ arguments: String..., origin: String? = nil, herdrPane: String? = nil, variables: [String: String] = [:]) -> CommandResult {
        cli(arguments, origin: origin, herdrPane: herdrPane, variables: variables)
    }

    /// `cli(_:origin:herdrPane:)` with the arguments as a list.
    @discardableResult
    func cli(_ arguments: [String], origin: String? = nil, herdrPane: String? = nil, variables: [String: String] = [:]) -> CommandResult {
        ShipyardCLI.run(
            arguments,
            table: macCommands,
            environment: CommandEnvironment(
                workingDirectory: workingFolder,
                variables: (herdrPane.map { ["HERDR_PANE_ID": $0] } ?? [:]).merging(variables) { $1 },
                git: FakeGitRemote(origin.map { [workingFolder: $0] } ?? [:])
            ),
            now: clock.now
        )
    }

    /// The pings' commands the Mac's `shipyard` has, as its `main.swift`
    /// assembles them, over this harness's configuration file, resolved
    /// repositories and ping store: the harness is the Mac's app, so its CLI
    /// is the Mac's. The Mac's `app` and `panel` commands talk to a running
    /// app over its socket; `ShipyardControlTests` drives them.
    var macCommands: CommandTable {
        .commands(filing: macFiling, store: pingStore)
    }

    /// The Mac's filing, against this harness's configuration file and
    /// resolved repositories.
    var macFiling: ProjectFiling {
        ProjectFiling(configURL: configURL, repositories: repositoriesStore)
    }

    /// The section named `name` in the current menu.
    func section(_ name: String) -> MenuSection? {
        shipyard.menu.sections.first { $0.name == name }
    }
}

// MARK: - Pings

extension Harness {
    /// The pings' notifications posted so far, local and remote.
    var pingNotifications: [PostedNotification] { notifier.posted.filter { $0.event == .pingSent } }

    /// The titles of the rows in the section `name` (a project or a machine).
    func titles(_ name: String) -> [String] {
        section(name)?.rows.map(\.title) ?? []
    }

    /// Signs in with GitHub answering `answer`, saves `hetzner-vps` and
    /// `netcup-vps` in this harness's Herdr, listing `hetzner` and `netcup`,
    /// and starts; then, when `polled`, polls the machines once. Only the
    /// machines `[remote] machines` names are asked.
    func startWithMachines(graphQL answer: StubHTTP.Answer, hetzner: [Ping] = [], netcup: [Ping] = [], polled: Bool = false) async {
        stub.on(Harness.userURL, Harness.viewerAnswer)
        graphQL([answer])
        herdr.addMachine("hetzner-vps", pings: hetzner)
        herdr.addMachine("netcup-vps", pings: netcup)
        await shipyard.start()
        if polled { await poll() }
    }

    /// Fires the machine timer, which must be armed, and waits for the poll.
    func poll(sourceLocation: SourceLocation = #_sourceLocation) async {
        let fired = await machineTimer.fire()
        #expect(fired, "the machine timer wasn't armed", sourceLocation: sourceLocation)
    }
}

/// A ping as a machine's `shipyard ping list --json` lists it, sent
/// `minutes` before the harness's now, as the sending `instance` (`i-<id>`
/// by default).
func remotePing(
    _ id: String,
    _ title: String,
    minutes: Double = 5,
    projects: [String] = [],
    repository: String? = nil,
    sender: String? = nil,
    action: PingAction? = nil,
    instance: String? = nil
) -> Ping {
    Ping(
        id: id,
        title: title,
        projects: projects,
        sent: Harness.now.addingTimeInterval(-minutes * 60),
        repository: repository,
        sender: sender,
        action: action,
        instance: instance ?? "i-\(id)"
    )
}

extension GroupID {
    /// The All tab's group of `key`: the All tab has no project.
    static func allTab(_ key: GroupKey) -> GroupID {
        GroupID(project: "", key: key)
    }
}

extension CommandTable {
    /// A `shipyard` build's pings' commands as its `main.swift` assembles
    /// them, over `filing` (`Unfiled` on a machine without the app,
    /// `ProjectFiling` on the Mac) and `store`.
    static func commands(filing: any PingFiling, store: PingStore) -> CommandTable {
        var table = CommandTable()
        table.add(PingCommands.entries(filing: filing, store: store))
        return table
    }
}

extension CommandResult {
    /// The id a `shipyard ping` that worked printed, its only line.
    var pingID: String {
        output.trimmingCharacters(in: .newlines)
    }
}

/// An ISO 8601 date, for comparing with the fixtures.
func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}
