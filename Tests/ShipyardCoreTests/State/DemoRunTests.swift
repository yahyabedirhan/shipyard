import Foundation
import ShipyardCommand
import ShipyardConfig
import ShipyardControl
import ShipyardPings
@testable import ShipyardCore
import Testing

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

    @Test("open --demo launches the app on the folder: configuration, state, resolved repositories, pings and socket stay in it, and the user's (login item and notes included) are untouched")
    func demoRun() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sy-\(UUID().uuidString.prefix(8))", isDirectory: true).standardizedFileURL
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let userConfig = home.appendingPathComponent(".config/shipyard/config.toml")
        let userSupport = home.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: userConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userSupport, withIntermediateDirectories: true)
        let userConfigText = Data("[[projects]]\nslug = \"shop\"\nrepositories = [\"yahyabedirhan/shop\"]\n".utf8)
        let userState = Data(#"{"knownItems":{}}"#.utf8)
        try userConfigText.write(to: userConfig)
        try userState.write(to: userSupport.appendingPathComponent(AppStateStore.fileName))
        let demo = root.appendingPathComponent("demo", isDirectory: true)
        let demoSupport = demo.appendingPathComponent("support", isDirectory: true)
        let demoConfig = demo.appendingPathComponent("shipyard/config.toml")
        try FileManager.default.createDirectory(at: demoConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[[projects]]\nslug = \"shipyard\"\nrepositories = [\"yahyabedirhan/shipyard\"]\n".utf8).write(to: demoConfig)

        let launcher = Launches()
        let app = Sockets(answering: ControlSocket.url(in: demoSupport), once: launcher)
        let opened = shipyard(["app", "open", "--demo", demo.path], support: userSupport, home: home, launcher: launcher, transport: app)
        try #require(opened.status == 0, "\(opened)")
        let environment = try #require(launcher.environments.current.only)

        let harness = Harness(launchedWith: environment, home: home)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([PullRequestsResponse.answer([PullRequestsResponse("yahyabedirhan/shipyard", [])])])
        await harness.shipyard.start()
        harness.shipyard.toggleCollapsed("shipyard")
        let demoPing = harness.cli("ping", "send", "In the demo", origin: "git@github.com:yahyabedirhan/shipyard.git")
        try #require(demoPing.status == 0, "\(demoPing.error)")
        await harness.shipyard.reloadPings()

        #expect(harness.files == AppFiles(config: demoConfig, support: demoSupport, demo: demo))
        #expect(harness.loginItem.settings.isEmpty)
        #expect(!harness.shipyard.readsNotes)
        #expect(harness.stub.notionRequests.isEmpty)
        #expect(harness.shipyard.configStore.lastValid.projects.map(\.slug) == ["shipyard"])
        #expect(harness.section("shipyard")?.rows.filter { $0.kind == .ping }.map(\.title) == ["In the demo"])
        let written = try FileManager.default.contentsOfDirectory(atPath: demoSupport.path).sorted()
        #expect(written == [
            AppStateStore.fileName, "Pings", ConfigurationLocation.fileName, ConfigStatusStore.fileName, ResolvedRepositoriesStore.fileName,
        ].sorted())
        #expect(ConfigurationLocation.recorded(in: demoSupport) == demoConfig)
        #expect(app.asked.current.last == ControlSocket.url(in: harness.files.support))
        try Data().write(to: ControlSocket.url(in: harness.files.support))
        #expect(ControlSocket.locate(support: userSupport) == ControlSocket.url(in: demoSupport))

        let userPings = PingStore(directory: PingStore.appDirectory(in: userSupport))
        var userTable = CommandTable()
        userTable.add(PingCommands.entries(
            filing: ProjectFiling(configURL: ConfigurationLocation.current(environment: [:], home: home, support: userSupport),
                                  repositories: ResolvedRepositoriesStore(directory: userSupport)),
            store: userPings
        ))
        let agentPing = ShipyardCLI.run(
            ["ping", "send", "Outside the demo", "--repo", "yahyabedirhan/shop"],
            table: userTable,
            environment: CommandEnvironment(workingDirectory: root, variables: [:]),
            now: Harness.now
        )
        try #require(agentPing.status == 0, "\(agentPing.error)")
        await harness.shipyard.reloadPings()
        #expect(userPings.all().map(\.title) == ["Outside the demo"])
        #expect(harness.pingStore.all().map(\.title) == ["In the demo"])

        _ = shipyard(["app", "open"], support: userSupport, home: home, launcher: launcher, transport: app)

        #expect(try Data(contentsOf: userConfig) == userConfigText)
        #expect(try Data(contentsOf: userSupport.appendingPathComponent(AppStateStore.fileName)) == userState)
        let left = try FileManager.default.contentsOfDirectory(atPath: userSupport.path).sorted()
        #expect(left == [AppStateStore.fileName, "Pings"].sorted())
    }

    @Test("a demo folder with demo-items.json lists its items, runs and notes as its account, asks GitHub, gh and Notion nothing, and signing out leaves the token alone")
    func demoItems() async throws {
        let demo = try DemoFolder(config: """
        [[projects]]
        slug = "shipyard"
        title = "Shipyard"
        repositories = ["yahyabedirhan/shipyard"]
        issues = { show = true }
        workflow-runs = { show = true }
        """, items: #"""
        {
          "account": { "login": "mira-dev", "name": "Mira", "avatar": "mira-dev.png" },
          "repositories": {
            "yahyabedirhan/shipyard": {
              "pullRequests": [
                { "number": 7, "title": "feat(focus): mute a project for an hour", "author": "sam-okafor", "state": "open",
                  "checks": "passed", "reviewRequested": true, "branch": "feat/focus-mode", "age": "3h", "updated": "20m" },
                { "number": 8, "title": "fix(focus): keep the count steady", "author": "mira-dev", "state": "open",
                  "checks": "failed", "branch": "fix/focus-count", "age": "1d" }
              ],
              "issues": [
                { "number": 5, "title": "Focus mode forgets the mute after a restart", "author": "dependabot[bot]", "state": "open", "age": "2d" }
              ],
              "runs": [
                { "workflow": "ci", "number": 90, "branch": "feat/focus-mode", "state": "running", "actor": "mira-dev", "age": "4m" },
                { "workflow": "ci", "number": 91, "branch": "someone-elses-branch", "state": "failed", "actor": "mira-dev", "age": "1h" }
              ]
            }
          },
          "notes": {
            "Shipyard": [ { "number": "SHIP-3", "title": "What the count shows while muted", "labels": ["design"], "age": "5h" } ]
          }
        }
        """#)
        defer { demo.remove() }
        let harness = demo.harness()
        await harness.shipyard.start()
        await harness.shipyard.refreshNotes()

        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.viewer?.login == "mira-dev")
        #expect(harness.shipyard.viewer?.avatarURL == demo.folder.appendingPathComponent("mira-dev.png"))
        #expect(harness.shipyard.gitHubConnection == GitHubConnection(login: "mira-dev", source: .demoItems))
        let rows = try #require(harness.section("shipyard")).rows
        #expect(Set(rows.map(\.title)) == [
            "feat(focus): mute a project for an hour",
            "fix(focus): keep the count steady",
            "Focus mode forgets the mute after a restart",
            "ci",
            "What the count shows while muted",
        ])
        let review = try #require(rows.first { $0.kind == .pullRequest && $0.number == 7 })
        #expect(review.attentionReasons.contains(.reviewRequested))
        #expect(review.item.updatedAt == Harness.now.addingTimeInterval(-20 * 60))
        let failing = try #require(rows.first { $0.kind == .pullRequest && $0.number == 8 })
        #expect(failing.authorKind == .me)
        #expect(failing.attentionReasons.contains(.checksFailed))
        #expect(rows.first { $0.kind == .issue }?.authorKind == .bot)
        #expect(rows.filter { $0.kind == .workflowRun }.map(\.number) == [90])
        #expect(rows.first { $0.kind == .note }?.item.note?.reference == "SHIP-3")
        #expect(harness.stub.requests.isEmpty)
        #expect(harness.gh.lookups == 0)

        harness.shipyard.signOut()
        #expect(try harness.store.token() == "gho_stored")
    }

    @Test("the launch screenshots' demo folder, assets/demo, reads cleanly: its configuration, its avatar, and demo-items.json with items and notes for every project")
    func launchDemo() async throws {
        let folder = repositoryRoot.appendingPathComponent("assets/demo", isDirectory: true)
        let store = ConfigurationStore(url: folder.appendingPathComponent("shipyard/config.toml"))
        store.reload()
        #expect(store.error == nil)
        #expect(store.warnings.isEmpty)
        let items = try #require(DemoItems.read(in: folder, at: Harness.now))
        #expect(items.problem == nil)
        let avatar = try #require(try await items.viewer().avatarURL)
        #expect(FileManager.default.fileExists(atPath: avatar.path))

        let configuration = store.lastValid
        let projects = configuration.projects.map(configuration.settings(for:))
        let snapshot = try await items.fetch(projects: projects, resolved: [:], at: Harness.now)
        guard case .read(let notes) = items.notes(for: projects.map { ($0.slug, $0.title) }) else {
            Issue.record("the notes don't read")
            return
        }
        for project in projects {
            #expect(snapshot.items[project.slug]?.isEmpty == false, "\(project.slug) lists no items")
            #expect((try? notes[project.slug]?.get())?.isEmpty == false, "\(project.slug) lists no notes")
        }
    }

    @Test("a demo-items.json that doesn't read fails every refresh with its reason, and never falls back to the user's GitHub")
    func unreadableDemoItems() async throws {
        let demo = try DemoFolder(
            config: "[[projects]]\nslug = \"shipyard\"\nrepositories = [\"yahyabedirhan/shipyard\"]\n",
            items: #"{ "account": { "login": "mira-dev" }, "repositories": { "yahyabedirhan/shipyard": { "issues": [ { "number": 1, "title": "t", "author": "a", "state": "open", "age": "soon" } ] } } }"#
        )
        defer { demo.remove() }
        let harness = demo.harness()
        await harness.shipyard.start()

        guard case .graphQL(let message) = harness.shipyard.fetchError else {
            Issue.record("expected the file's problem, got \(String(describing: harness.shipyard.fetchError))")
            return
        }
        #expect(message.contains("demo-items.json doesn't read"))
        #expect(message.contains("`soon` isn't an age"))
        #expect(harness.stub.requests.isEmpty)
        #expect(harness.gh.lookups == 0)
    }

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

/// A demo folder in a temporary folder, as `app open --demo` launches the
/// app on it: its configuration and its `demo-items.json`.
private struct DemoFolder {
    let root: URL
    var folder: URL { root.appendingPathComponent("demo", isDirectory: true) }

    init(config: String, items: String) throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sy-\(UUID().uuidString.prefix(8))", isDirectory: true).standardizedFileURL
        let configURL = folder.appendingPathComponent("shipyard/config.toml")
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(config.utf8).write(to: configURL)
        try Data(items.utf8).write(to: folder.appendingPathComponent(DemoItems.fileName))
    }

    @MainActor
    func harness() -> Harness {
        Harness(
            launchedWith: ["XDG_CONFIG_HOME": folder.path, "SHIPYARD_SUPPORT_DIR": folder.appendingPathComponent("support").path],
            home: root.appendingPathComponent("home", isDirectory: true)
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}

private final class Launches: AppLaunching {
    let environments = Locked<[[String: String]]>([])

    func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure) {
        environments.withValue { $0.append(environment) }
    }
}

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
    fileprivate var only: Element? { count == 1 ? first : nil }
}
