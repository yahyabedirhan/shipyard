import Foundation
import ShipyardCommand
import ShipyardConfig
import ShipyardControl
import ShipyardPings
@testable import ShipyardCore
import Testing

/// A demo run end to end: `shipyard app open --demo <folder>` as the agent
/// runs it, the app launched with the environment it passed (its files
/// where `AppFiles` puts them, as `AppServices` builds them), and the
/// user's own configuration, state and ping store beside it, which the run
/// must leave as they were.
@Suite("A demo run")
@MainActor
struct DemoRunTests {
    @Test("SHIPYARD_SUPPORT_DIR moves the app's support folder when it's an absolute path", arguments: [
        (["SHIPYARD_SUPPORT_DIR": "/demo/support"], "/demo/support"),
        (["SHIPYARD_SUPPORT_DIR": "demo/support"], nil),
        (["SHIPYARD_SUPPORT_DIR": ""], nil),
        ([:], nil),
    ] as [([String: String], String?)])
    func supportFolder(environment: [String: String], moved: String?) {
        let normal = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shipyard", isDirectory: true)
        #expect(SupportFolder.app(environment: environment).path == moved ?? normal.path)
    }

    @Test("a launch without the demo's variables is the user's own app, not a demo")
    func normalLaunch() {
        let files = AppFiles(environment: [:], home: URL(fileURLWithPath: "/Users/me", isDirectory: true))

        #expect(files.config.path == "/Users/me/.config/shipyard/config.toml")
        #expect(files.support == SupportFolder.app(environment: [:]))
        #expect(files.demo == nil)
    }

    @Test("open --demo launches the app on the folder: configuration, state, resolved repositories, pings and socket stay in it, and the user's (login item included) are untouched")
    func demoRun() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sy-\(UUID().uuidString.prefix(8))", isDirectory: true).standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        // The user's own folders: their config.toml and state.json, which the demo must leave byte for byte.
        let home = root.appendingPathComponent("home", isDirectory: true)
        let userConfig = home.appendingPathComponent(".config/shipyard/config.toml")
        let userSupport = home.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: userConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userSupport, withIntermediateDirectories: true)
        let userConfigText = Data("[[projects]]\nname = \"shop\"\nrepositories = [\"yahyabedirhan/shop\"]\n".utf8)
        let userState = Data(#"{"knownItems":{}}"#.utf8)
        try userConfigText.write(to: userConfig)
        try userState.write(to: userSupport.appendingPathComponent(AppStateStore.fileName))
        // The demo folder, as an agent taking screenshots would use it.
        let demo = root.appendingPathComponent("demo", isDirectory: true)
        let demoSupport = demo.appendingPathComponent("support", isDirectory: true)
        let demoConfig = demo.appendingPathComponent("shipyard/config.toml")
        try FileManager.default.createDirectory(at: demoConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[[projects]]\nname = \"shipyard\"\nrepositories = [\"yahyabedirhan/shipyard\"]\n".utf8).write(to: demoConfig)

        // 1. The agent opens the demo; the user's app isn't running.
        let launcher = Launches()
        let app = Sockets(answering: ControlSocket.url(in: demoSupport), once: launcher)
        let opened = shipyard(["app", "open", "--demo", demo.path], support: userSupport, home: home, launcher: launcher, transport: app)
        try #require(opened.status == 0, "\(opened)")
        let environment = try #require(launcher.environments.current.only)

        // 2. The app, launched with that environment, starts and is used.
        let harness = Harness(launchedWith: environment, home: home)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([PullRequestsResponse.answer([PullRequestsResponse("yahyabedirhan/shipyard", [])])])
        await harness.shipyard.start()
        harness.shipyard.toggleCollapsed("shipyard")
        let demoPing = harness.cli("ping", "In the demo", origin: "git@github.com:yahyabedirhan/shipyard.git")
        try #require(demoPing.status == 0, "\(demoPing.error)")
        await harness.shipyard.reloadPings()

        #expect(harness.files == AppFiles(config: demoConfig, support: demoSupport, demo: demo))
        // The login item is the user's app's: the demo's launch-at-login doesn't touch it.
        #expect(harness.loginItem.settings.isEmpty)
        #expect(harness.shipyard.configStore.lastValid.projects.map(\.name) == ["shipyard"])
        #expect(harness.section("shipyard")?.rows.filter { $0.kind == .ping }.map(\.title) == ["In the demo"])
        let written = try FileManager.default.contentsOfDirectory(atPath: demoSupport.path).sorted()
        #expect(written == [
            AppStateStore.fileName, "Pings", ConfigLocation.fileName, ConfigStatusStore.fileName, ResolvedRepositoriesStore.fileName,
        ].sorted())
        #expect(ConfigLocation.recorded(in: demoSupport) == demoConfig)
        // The socket the command waited at is the one this app listens on, and later commands find it.
        #expect(app.asked.current.last == ControlSocket.url(in: harness.files.support))
        try Data().write(to: ControlSocket.url(in: harness.files.support))   // the app's server listening
        #expect(ControlSocket.locate(support: userSupport) == ControlSocket.url(in: demoSupport))

        // 3. Meanwhile an agent's ping, from a shell without the variable, goes to the user's store, against their config.
        let userPings = PingStore(directory: PingStore.appDirectory(in: userSupport))
        var userTable = CommandTable()
        userTable.add(PingCommands.entries(
            filing: ProjectFiling(configURL: ConfigLocation.current(environment: [:], home: home, support: userSupport),
                                  repositories: ResolvedRepositoriesStore(directory: userSupport)),
            store: userPings
        ))
        let agentPing = ShipyardCLI.run(
            ["ping", "Outside the demo", "--repo", "yahyabedirhan/shop"],
            table: userTable,
            environment: CommandEnvironment(workingDirectory: root, variables: [:]),
            now: Harness.now
        )
        try #require(agentPing.status == 0, "\(agentPing.error)")
        await harness.shipyard.reloadPings()
        #expect(userPings.all().map(\.title) == ["Outside the demo"])
        #expect(harness.pingStore.all().map(\.title) == ["In the demo"])

        // 4. Plain open brings the user's app back (nothing here plays it, so its wait runs out).
        _ = shipyard(["app", "open"], support: userSupport, home: home, launcher: launcher, transport: app)

        // The user's config.toml and state.json are byte for byte as they were; their folder holds only their pings besides.
        #expect(try Data(contentsOf: userConfig) == userConfigText)
        #expect(try Data(contentsOf: userSupport.appendingPathComponent(AppStateStore.fileName)) == userState)
        let left = try FileManager.default.contentsOfDirectory(atPath: userSupport.path).sorted()
        #expect(left == [AppStateStore.fileName, "Pings"].sorted())
    }

    /// `shipyard <arguments>` with the Mac's `app` command, the user's
    /// support folder `support` and `HOME` at `home`.
    private func shipyard(_ arguments: [String], support: URL, home: URL, launcher: Launches, transport: Sockets) -> CommandResult {
        var table = CommandTable()
        table.add(ControlCommands.entries(support: support, launcher: launcher, transport: transport, pause: { _ in }))
        return ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(workingDirectory: home, variables: ["HOME": home.path]),
            now: Harness.now
        )
    }
}

/// A launcher that records each launch's environment.
private final class Launches: AppLaunching {
    let environments = Locked<[[String: String]]>([])

    func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure) {
        environments.withValue { $0.append(environment) }
    }
}

/// The app's end of the sockets: nothing answers, except a demo app at
/// `socket` once `launcher` launched one, until it's asked to quit.
private final class Sockets: ControlTransport {
    let asked = Locked<[URL]>([])
    private let quit = Locked(false)
    private let socket: URL
    private let launcher: Launches

    init(answering socket: URL, once launcher: Launches) {
        self.socket = socket
        self.launcher = launcher
    }

    func exchange(_ request: Data, socket: URL, timeout: TimeInterval) throws(ControlTransportFailure) -> Data {
        asked.withValue { $0.append(socket) }
        guard socket == self.socket, launcher.environments.current.contains(where: { !$0.isEmpty }), !quit.current else {
            throw .notRunning
        }
        if (try? ControlMessage.decode(request))?.request == .appQuit {
            quit.withValue { $0 = true }
            return ControlReply.done("shipyard quit\n").encoded()
        }
        return ControlReply.done("shipyard is running\n").encoded()
    }
}

extension Array {
    /// The one element, or nil when there are none or several.
    fileprivate var only: Element? { count == 1 ? first : nil }
}
