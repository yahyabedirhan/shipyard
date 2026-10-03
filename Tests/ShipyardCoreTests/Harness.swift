import Foundation
@testable import ShipyardCommand
import ShipyardConfig
@testable import ShipyardPings
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore

/// The main test seam: a real `Shipyard` driven end to end over in-memory
/// ports. The network is `StubHTTP` answering from recorded GitHub
/// responses (`Fixtures/`); the configuration lives in a temporary
/// directory and the app state in another; the clock, the refresh timer and
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
    let actions = RecordingActions()
    /// The Herdr a ping's `--herdr` action focuses, and the remote
    /// machines are asked through: no tabs or machines until added.
    let herdr = FakeHerdr()
    let notifier = RecordingNotifier()
    let loginItem = RecordingLoginItem()
    /// `config.toml` in a fresh temporary directory.
    let configURL: URL
    /// A fresh temporary directory for app state (`state.json`).
    let stateDirectory: URL
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
        self.init(configURL: configURL, stateDirectory: stateDirectory, store: InMemoryTokenStore(token: stored), gh: ghToken, clientID: clientID)
    }

    /// A harness over existing configuration and app-state directories.
    private init(configURL: URL, stateDirectory: URL, store: InMemoryTokenStore, gh ghToken: String?, clientID: String = "test-client-id") {
        self.configURL = configURL
        self.stateDirectory = stateDirectory
        self.store = store
        self.ghToken = ghToken
        gh = FakeGhLookup(token: ghToken)
        let clock = sleeper.clock
        // Read at the harness's time, so a ping's expiry counts from its clock.
        pingStore = PingStore(directory: stateDirectory.appendingPathComponent("Pings", isDirectory: true), now: { clock.now })
        repositoriesStore = ResolvedRepositoriesStore(directory: stateDirectory)
        shipyard = Shipyard(
            configStore: ConfigStore(url: configURL),
            appStateStore: AppStateStore(directory: stateDirectory),
            configStatusStore: ConfigStatusStore(directory: stateDirectory),
            pingStore: pingStore,
            repositoriesStore: repositoriesStore,
            tokenStore: store,
            actions: actions,
            notifier: notifier,
            loginItem: loginItem,
            gh: gh,
            herdr: herdr.focus,
            remote: herdr.remote,
            transport: stub,
            clock: sleeper.clock,
            timer: timer,
            machineTimer: machineTimer,
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
        let next = Harness(configURL: configURL, stateDirectory: stateDirectory, store: store, gh: ghToken)
        next.clock.set(clock.now)
        return next
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

    /// The commands the Mac's `shipyard` has, as its `main.swift` assembles
    /// them, over this harness's configuration file, resolved repositories
    /// and ping store: the harness is the Mac's app, so its CLI is the Mac's.
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

extension GroupID {
    /// The All tab's group of `key`: the All tab has no project.
    static func allTab(_ key: GroupKey) -> GroupID {
        GroupID(project: "", key: key)
    }
}

extension CommandTable {
    /// A `shipyard` build's commands as its `main.swift` assembles them:
    /// the pings' commands over `filing` (`Unfiled` on a machine without the
    /// app, `ProjectFiling` on the Mac) and `store`.
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
