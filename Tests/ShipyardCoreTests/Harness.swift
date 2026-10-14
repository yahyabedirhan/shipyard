import Foundation
import ShipyardCLISettings
@testable import ShipyardCommand
import ShipyardConfig
@testable import ShipyardPings
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

@MainActor
struct Harness {
    nonisolated static let now = Date(timeIntervalSince1970: 1_790_337_600)
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
    let machineTimer = ManualTimer()
    let notesTimer = ManualTimer()
    let ntn: FakeNtnRoute
    let actions = RecordingActions()
    let herdr = FakeHerdr()
    let notifier = RecordingNotifier()
    let tailnet = FakeTailnet()
    let loginItem = RecordingLoginItem()
    let files: AppFiles
    nonisolated var configURL: URL { files.config }
    nonisolated var stateDirectory: URL { files.support }
    let pingStore: PingStore
    let repositoriesStore: ResolvedRepositoriesStore
    let shipyard: Shipyard

    var clock: ManualClock { sleeper.clock }
    var stateURL: URL { shipyard.appStateStore.url }

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

    init(launchedWith environment: [String: String], home: URL) {
        self.init(files: AppFiles(environment: environment, home: home), store: InMemoryTokenStore(token: "gho_stored"), ntn: .loggedIn, gh: nil)
    }

    private init(files: AppFiles, store: InMemoryTokenStore, ntn state: FakeNtnRoute.State?, gh ghToken: String?, clientID: String = "test-client-id") {
        self.files = files
        self.store = store
        ntn = FakeNtnRoute(state ?? .missing, notion: stub)
        self.ghToken = ghToken
        gh = FakeGhLookup(token: ghToken)
        let clock = sleeper.clock
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

    static func started(config: String, graphQL answers: StubHTTP.Answer...) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(userURL, viewerAnswer)
        if !answers.isEmpty { harness.graphQL(answers) }
        await harness.shipyard.start()
        return harness
    }

    func relaunched() -> Harness {
        let next = Harness(files: files, store: store, ntn: ntn.current, gh: ghToken)
        next.clock.set(clock.now)
        return next
    }

    func connectNotionBeforeStart() {
        shipyard.appStateStore.update { $0.notionConnected = true }
    }

    nonisolated static func fixture(
        _ name: String,
        status: Int = 200,
        remaining: Int = 4990,
        reset: Date = rateLimitReset
    ) throws -> StubHTTP.Answer {
        try .fixture(name, status: status, headers: rateLimitHeaders(remaining: remaining, reset: reset))
    }

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

    func graphQL(_ answers: [StubHTTP.Answer]) {
        stub.on("POST", GitHubClient.graphQLURL, answers: answers)
    }

    func refresh(answering answer: StubHTTP.Answer) async {
        graphQL([answer])
        clock.advance(by: 120)
        await shipyard.refresh()
    }

    var graphQLRequests: [URLRequest] { stub.requests("POST", GitHubClient.graphQLURL) }

    var authorizations: [String?] {
        stub.requests("GET", Self.userURL).map { $0.value(forHTTPHeaderField: "Authorization") }
    }

    func writeConfig(_ text: String) throws {
        try Data(text.utf8).write(to: configURL)
    }

    var workingFolder: URL { stateDirectory.deletingLastPathComponent().appendingPathComponent("work", isDirectory: true) }

    @discardableResult
    func cli(_ arguments: String..., origin: String? = nil, herdrPane: String? = nil, variables: [String: String] = [:]) -> CommandResult {
        cli(arguments, origin: origin, herdrPane: herdrPane, variables: variables)
    }

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

    var macCommands: CommandTable {
        var table = CommandTable.commands(filing: macFiling, store: pingStore)
        let configURL = configURL
        let settings = CLISettingsFile.beside(config: configURL)
        table.add(ConfigurationCommands.entries(checks: [
            { now in ConfigurationStore.check(configURL, at: now) },
            { now in settings.check(at: now) },
        ]))
        return table
    }

    var macFiling: ProjectFiling {
        ProjectFiling(configURL: configURL, repositories: repositoriesStore)
    }

    func section(_ name: String) -> MenuSection? {
        shipyard.menu.sections.first { $0.name == name }
    }
}

extension Harness {
    var pingNotifications: [PostedNotification] { notifier.posted.filter { $0.event == .pingSent } }

    func titles(_ name: String) -> [String] {
        section(name)?.rows.map(\.title) ?? []
    }

    func startWithMachines(graphQL answer: StubHTTP.Answer, hetzner: [Ping] = [], netcup: [Ping] = [], polled: Bool = false) async {
        stub.on(Harness.userURL, Harness.viewerAnswer)
        graphQL([answer])
        herdr.addMachine("hetzner-vps", pings: hetzner)
        herdr.addMachine("netcup-vps", pings: netcup)
        await shipyard.start()
        if polled { await poll() }
    }

    func poll(sourceLocation: SourceLocation = #_sourceLocation) async {
        let fired = await machineTimer.fire()
        #expect(fired, "the machine timer wasn't armed", sourceLocation: sourceLocation)
    }
}

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
    static func allTab(_ key: GroupKey) -> GroupID {
        GroupID(project: "", key: key)
    }
}

extension CommandTable {
    static func commands(filing: any PingFiling, store: PingStore) -> CommandTable {
        var table = CommandTable()
        table.add(PingCommands.entries(filing: filing, store: store))
        return table
    }
}

extension CommandResult {
    var pingID: String {
        output.trimmingCharacters(in: .newlines)
    }
}

func date(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}
