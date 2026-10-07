import Foundation
import ShipyardCommand
import ShipyardControl
import Testing

/// `shipyard app open [--demo <folder>] | quit | status` as an agent runs it, through
/// `ShipyardCLI.run` with the Mac's table, an in-memory app at the end of
/// the socket and a recording launcher: what each command sends, prints and
/// exits with.
@Suite("The app command")
struct AppCommandTests {
    static let support = URL(fileURLWithPath: "/Users/agent/Library/Application Support/Shipyard", isDirectory: true)
    static let status = AppStatus(version: "0.2.0", panelOpen: false, layout: "tabs", projects: ["shop", "blog"])
    /// The lease an app hands back when it quits: held by the tests' agent
    /// (`FakeProcessTable.agent` in `/work`), taken at 1000, ending at 1060.
    static let held = ControlLease.Term(
        holder: Holder(key: "process:300@800250000", name: "claude", place: "/work"),
        taken: Date(timeIntervalSince1970: 1000),
        ends: Date(timeIntervalSince1970: 1060)
    )
    /// `held` as a relaunch hands it over in the launched app's environment.
    static let handover = #"{"ends":1060,"holder":{"key":"process:300@800250000","name":"claude","place":"/work"},"taken":1000}"#

    /// Waits recorded, never slept.
    let pauses = Locked<[TimeInterval]>([])

    /// Runs `shipyard <arguments>` in the Mac's build against `transport`.
    func shipyard(_ arguments: String..., transport: FakeTransport, launcher: RecordingLauncher = RecordingLauncher()) -> CommandResult {
        shipyard(arguments, transport: transport, launcher: launcher)
    }

    func shipyard(
        _ arguments: [String],
        transport: FakeTransport,
        launcher: RecordingLauncher = RecordingLauncher(),
        support: URL = Self.support,
        variables: [String: String] = [:]
    ) -> CommandResult {
        var table = CommandTable()
        let pauses = pauses
        table.add(ControlCommands.entries(
            support: support,
            launcher: launcher,
            transport: transport,
            processes: FakeProcessTable.agent,
            pause: { seconds in pauses.withValue { $0.append(seconds) } }
        ))
        return ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: variables),
            now: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - Status

    @Test("status sends one versioned request to control.sock in the support folder and prints the app's reply")
    func status() throws {
        let app = FakeTransport(reply: .done(Self.status.text))

        let result = shipyard("app", "status", transport: app)

        #expect(result == CommandResult(output: Self.status.text))
        let exchange = try #require(app.exchanges.current.only)
        #expect(String(decoding: exchange.request, as: UTF8.self)
            == #"{"command":"app.status",\#(FakeProcessTable.wire()),"json":false,"version":2}"#)
        #expect(exchange.socket.path == "/Users/agent/Library/Application Support/Shipyard/control.sock")
        #expect(exchange.timeout == 15)
    }

    @Test("status --json asks the app for its JSON")
    func statusJSON() {
        let app = FakeTransport(reply: .done(Self.status.json))

        let result = shipyard("app", "status", "--json", transport: app)

        #expect(result == CommandResult(output: Self.status.json))
        #expect(app.requests == [.appStatus(json: true)])
    }

    @Test("the status reads as lines, or as one JSON object, with the view shown and the lease's holder, place, time left and waiters")
    func statusFormats() {
        let tabs = AppStatus(
            version: "0.2.0", panelOpen: false, view: "cli", layout: "tabs", tab: "shop", projects: ["shop", "blog"],
            folded: ["blog"], showingAll: [.init(project: "shop", kind: "pull-requests")],
            lease: .init(holder: "Claude Code", place: "Herdr pane w1-2", secondsLeft: 48, waiting: 1)
        )
        #expect(tabs.text == """
            shipyard 0.2.0 is running
            lease: Claude Code in Herdr pane w1-2, 48s left, 1 waiting
            panel: closed
            view: cli
            layout: tabs
            tab: shop
            projects: shop, blog
            folded: blog
            showing all: pull-requests in shop

            """)
        #expect(tabs.json == #"{"demo":null,"folded":["blog"],"layout":"tabs","#
            + #""lease":{"holder":"Claude Code","place":"Herdr pane w1-2","secondsLeft":48,"waiting":1},"#
            + #""panelOpen":false,"projects":["shop","blog"],"#
            + #""running":true,"showingAll":[{"kind":"pull-requests","project":"shop"}],"tab":"shop","version":"0.2.0","view":"cli"}"# + "\n")
        // The list layout has no tab: no line, and null in the JSON. A free lease is `free`, and null.
        let list = AppStatus(version: "0.2.0", panelOpen: true, layout: "list", projects: [])
        #expect(list.text == """
            shipyard 0.2.0 is running
            lease: free
            panel: open
            view: projects
            layout: list
            projects: none
            folded: none
            showing all: none

            """)
        #expect(list.json.contains(#""tab":null"#))
        #expect(list.json.contains(#""lease":null"#))
        #expect(list.json.contains(#""view":"projects""#))
    }

    @Test("a demo run's status names its folder, as a line and in the JSON")
    func demoStatus() {
        var demo = Self.status
        demo.demo = "/Users/agent/demo"

        #expect(demo.text == """
            shipyard 0.2.0 is running
            demo: /Users/agent/demo
            lease: free
            panel: closed
            view: projects
            layout: tabs
            projects: shop, blog
            folded: none
            showing all: none

            """)
        #expect(demo.json
            == #"{"demo":"/Users/agent/demo","folded":[],"layout":"tabs","lease":null,"panelOpen":false,"projects":["shop","blog"],"#
            + #""running":true,"showingAll":[],"tab":null,"version":"0.2.0","view":"projects"}"# + "\n")
    }

    // MARK: - Not running, refusals and failures

    @Test("when the app isn't running, every command but open exits 1 saying how to open it", arguments: [
        ["app", "status"], ["app", "status", "--json"], ["app", "quit"],
    ])
    func notRunning(arguments: [String]) {
        let launcher = RecordingLauncher()

        let result = shipyard(arguments, transport: .nothingListens, launcher: launcher)

        #expect(result == CommandResult(error: "shipyard isn't running; `shipyard app open`\n", status: 1))
        #expect(launcher.launches.current.isEmpty)
    }

    @Test("a refusal, no answer in time, or a reply that doesn't read exits 1 with one line")
    func failures() {
        let refused = shipyard("app", "status", transport: FakeTransport(reply: .refused("the app is busy")))
        #expect(refused == CommandResult(error: "the app is busy\n", status: 1))

        let slow = shipyard("app", "status", transport: FakeTransport { _, _ in .failure(.timedOut) })
        #expect(slow == CommandResult(error: "shipyard didn't answer within 15 seconds\n", status: 1))

        let garbled = shipyard("app", "status", transport: FakeTransport { _, _ in .success(Data("{\"done\":1}".utf8)) })
        #expect(garbled.status == 1)
        #expect(garbled.error.hasPrefix("couldn't ask shipyard: the app's reply doesn't read; is the app from the same build as this shipyard ("))
    }

    @Test("a note the app sends with a reply that worked goes to standard error, exit 0")
    func note() {
        let result = shipyard("app", "status", transport: FakeTransport(reply: .done("done\n", note: "a note\n")))
        #expect(result == CommandResult(output: "done\n", error: "a note\n"))
    }

    // MARK: - Open

    @Test("open when the app runs launches nothing, and prints its status through the leased app.open, which renews the lease")
    func openWhenRunning() {
        let launcher = RecordingLauncher()
        let app = FakeTransport(reply: .done(Self.status.text))

        let result = shipyard("app", "open", transport: app, launcher: launcher)

        #expect(result == CommandResult(output: Self.status.text))
        #expect(launcher.launches.current.isEmpty)
        #expect(app.requests == [.appOpen])
        #expect(ControlRequest.appOpen.isLeased)
    }

    @Test("open launches the app by bundle id, then looks every quarter second, briefly each time, until it answers")
    func openLaunches() {
        let launcher = RecordingLauncher()
        // Not running when asked first or at the first look; then listening but too busy to answer once.
        let app = FakeTransport { _, index in
            switch index {
            case 0, 1: .failure(.notRunning)
            case 2: .failure(.timedOut)
            default: .success(ControlReply.done(Self.status.text).encoded())
            }
        }

        let result = shipyard("app", "open", transport: app, launcher: launcher)

        #expect(result == CommandResult(output: Self.status.text))
        #expect(launcher.launches.current == [.init(bundleID: "com.yahyabedirhan.shipyard", environment: [:])])
        #expect(app.requests == [.appOpen] + Array(repeating: .appStatus(json: false), count: 3))
        #expect(app.exchanges.current.map(\.timeout) == [15, 1, 1, 1])
        #expect(pauses.current == [0.25, 0.25, 0.25])
    }

    @Test("open exits 1 when the launched app never answers within about 10 seconds")
    func openNeverAnswers() {
        let result = shipyard("app", "open", transport: .nothingListens)

        #expect(result == CommandResult(error: "shipyard didn't answer within 10 seconds of launching\n", status: 1))
        #expect(pauses.current.reduce(0, +) == 10)
    }

    @Test("open exits 1 with the reason when the app can't be launched")
    func openFailsToLaunch() {
        let launcher = RecordingLauncher(failure: AppLaunchFailure("no app with the bundle id com.yahyabedirhan.shipyard is installed"))

        let result = shipyard("app", "open", transport: .nothingListens, launcher: launcher)

        #expect(result == CommandResult(
            error: "shipyard app open: no app with the bundle id com.yahyabedirhan.shipyard is installed\n",
            status: 1
        ))
        #expect(pauses.current.isEmpty)
    }

    // MARK: - Demo

    /// A support folder and a demo folder of their own, short enough for a
    /// socket's path, removed when `body` returns.
    func inFolders(_ body: (_ support: URL, _ demo: URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("sy-\(UUID().uuidString.prefix(8))", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support", isDirectory: true)
        let demo = root.appendingPathComponent("demo", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: demo.appendingPathComponent("shipyard"), withIntermediateDirectories: true)
        try body(support.standardizedFileURL, demo.standardizedFileURL)
    }

    /// The user's app at `support`'s socket, running until it's asked to
    /// quit (or from the start when `normalRuns` is false, never), and the
    /// demo's at `demo`'s, running once `launcher` launched it with an
    /// environment, and until it's asked to quit. Each quit hands back the
    /// agent's lease: `held` from the user's app, and from the demo's
    /// `held` renewed to 1120.
    func apps(support: URL, demo: URL, launcher: RecordingLauncher) -> FakeTransport {
        let normal = ControlSocket.url(in: support)
        let demoSocket = ControlSocket.url(in: demo.appendingPathComponent("support", isDirectory: true))
        let normalRunning = Locked(true)
        let demoQuit = Locked(false)
        var demoStatus = Self.status
        demoStatus.demo = demo.path
        let demoText = demoStatus.text
        return FakeTransport { request, socket, _ in
            let text: String
            switch socket {
            case normal where normalRunning.current:
                text = Self.status.text
            case demoSocket where launcher.launches.current.contains(where: { !$0.environment.isEmpty }) && !demoQuit.current:
                text = demoText
            default:
                return .failure(.notRunning)
            }
            if request == .appQuit {
                var lease = Self.held
                if socket == normal {
                    normalRunning.withValue { $0 = false }
                } else {
                    demoQuit.withValue { $0 = true }
                    lease.ends = Date(timeIntervalSince1970: 1120)
                }
                return .success(ControlReply(ok: true, output: "shipyard quit\n", lease: lease).encoded())
            }
            return .success(ControlReply.done(text).encoded())
        }
    }

    @Test("open --demo quits the running app, points the command at the demo, launches it on the folder with the lease handed over, and waits for it there")
    func openDemo() throws {
        try inFolders { support, demo in
            let launcher = RecordingLauncher()
            let app = apps(support: support, demo: demo, launcher: launcher)
            let demoSupport = demo.appendingPathComponent("support", isDirectory: true)

            let result = shipyard(["app", "open", "--demo", demo.path], transport: app, launcher: launcher,
                                  support: support, variables: ["HOME": "/Users/agent"])

            #expect(result.status == 0, "\(result)")
            #expect(result.output.contains("demo: \(demo.path)\n"))
            #expect(launcher.launches.current == [.init(bundleID: "com.yahyabedirhan.shipyard", environment: [
                "XDG_CONFIG_HOME": demo.path,
                "SHIPYARD_SUPPORT_DIR": demoSupport.path,
                "GH_CONFIG_DIR": "/Users/agent/.config/gh",
                "SHIPYARD_CONTROL_LEASE": Self.handover,
            ])])
            // The user's app was asked to quit before the launch, and the launched one asked at the demo's socket.
            #expect(app.requests.contains(.appQuit))
            #expect(app.exchanges.current.last?.socket == ControlSocket.url(in: demoSupport))
            #expect(DemoPointer.recorded(in: support) == demoSupport)
            // The pointer is the only file in the user's support folder.
            let files = try FileManager.default.contentsOfDirectory(atPath: support.path)
            #expect(files == [DemoPointer.fileName])
        }
    }

    @Test("while a demo runs, every command reaches it; once its socket is gone, the user's app again")
    func demoIsFound() throws {
        try inFolders { support, demo in
            let demoSupport = demo.appendingPathComponent("support", isDirectory: true)
            try DemoPointer.record(demoSupport, in: support)
            try FileManager.default.createDirectory(at: demoSupport, withIntermediateDirectories: true)
            try Data().write(to: ControlSocket.url(in: demoSupport))
            let app = FakeTransport(reply: .done(Self.status.text))

            _ = shipyard(["app", "status"], transport: app, support: support)
            #expect(app.exchanges.current.last?.socket == ControlSocket.url(in: demoSupport))

            // The demo quit from its own menu: its socket is gone, the pointer left behind.
            try FileManager.default.removeItem(at: ControlSocket.url(in: demoSupport))
            _ = shipyard(["app", "status"], transport: app, support: support)
            #expect(app.exchanges.current.last?.socket == ControlSocket.url(in: support))
        }
    }

    @Test("plain open while a demo runs quits it, removes the pointer and launches the user's app with the demo's lease handed over")
    func openAfterDemo() throws {
        try inFolders { support, demo in
            let launcher = RecordingLauncher()
            let app = apps(support: support, demo: demo, launcher: launcher)
            let opened = shipyard(["app", "open", "--demo", demo.path], transport: app, launcher: launcher, support: support)
            try #require(opened.status == 0, "\(opened)")
            let demoSupport = demo.appendingPathComponent("support", isDirectory: true)
            // The demo app listens.
            try FileManager.default.createDirectory(at: demoSupport, withIntermediateDirectories: true)
            try Data().write(to: ControlSocket.url(in: demoSupport))

            let result = shipyard(["app", "open"], transport: app, launcher: launcher, support: support)

            // No demo variables; the lease as the demo's quit renewed it.
            #expect(launcher.launches.current.map(\.environment).last == [
                "SHIPYARD_CONTROL_LEASE": Self.handover.replacingOccurrences(of: #""ends":1060"#, with: #""ends":1120"#),
            ])
            #expect(DemoPointer.recorded(in: support) == nil)
            let files = try FileManager.default.contentsOfDirectory(atPath: support.path)
            #expect(files.isEmpty)
            // The user's app quit for the demo, then the demo for the user's app.
            #expect(app.requests.filter { $0 == .appQuit }.count == 2)
            // The fake's user app stays quit, so the wait at the user's socket runs out.
            #expect(result == CommandResult(error: "shipyard didn't answer within 10 seconds of launching\n", status: 1))
            #expect(app.exchanges.current.last?.socket == ControlSocket.url(in: support))
        }
    }

    @Test("while another agent holds the lease, quit, open and open --demo are refused with its line, exit 1, and nothing is launched",
          arguments: [["app", "quit"], ["app", "open"], ["app", "open", "--demo"]])
    func refusedToNonHolder(arguments: [String]) throws {
        try inFolders { support, demo in
            let launcher = RecordingLauncher()
            let inUse = "shipyard is in use by codex in Herdr pane w1-2 until 12:01:00 (48s left); `shipyard control take --wait <seconds>` to queue"
            // The app answers its free status, and refuses every leased request.
            let app = FakeTransport { request, _ in
                request.isLeased
                    ? .success(ControlReply.refused(inUse).encoded())
                    : .success(ControlReply.done(Self.status.text).encoded())
            }
            let arguments = arguments.last == "--demo" ? arguments + [demo.path] : arguments

            let result = shipyard(arguments, transport: app, launcher: launcher, support: support)

            #expect(result == CommandResult(error: inUse + "\n", status: 1))
            #expect(launcher.launches.current.isEmpty)
            #expect(DemoPointer.recorded(in: support) == nil)
        }
    }

    @Test("open --demo that can't launch exits 1 and leaves no pointer")
    func openDemoFails() throws {
        try inFolders { support, demo in
            let launcher = RecordingLauncher(failure: AppLaunchFailure("no app with the bundle id com.yahyabedirhan.shipyard is installed"))

            let result = shipyard(["app", "open", "--demo", demo.path], transport: .nothingListens, launcher: launcher, support: support)

            #expect(result.status == 1)
            #expect(DemoPointer.recorded(in: support) == nil)
        }
    }

    @Test("the demo app reads gh's folder as the agent's shell does, since moving XDG_CONFIG_HOME would move it", arguments: [
        (["GH_CONFIG_DIR": "/cfg/gh", "XDG_CONFIG_HOME": "/xdg"], "/cfg/gh"),
        (["XDG_CONFIG_HOME": "/xdg", "HOME": "/Users/agent"], "/xdg/gh"),
        (["GH_CONFIG_DIR": "", "HOME": "/Users/agent"], "/Users/agent/.config/gh"),
        (["XDG_CONFIG_HOME": "rel", "HOME": "/Users/agent"], "/work/rel/gh"),
    ])
    func demoGhConfig(variables: [String: String], expected: String) throws {
        try inFolders { support, demo in
            let launcher = RecordingLauncher()

            _ = shipyard(["app", "open", "--demo", demo.path], transport: apps(support: support, demo: demo, launcher: launcher),
                         launcher: launcher, support: support, variables: variables)

            #expect(launcher.launches.current.first?.environment["GH_CONFIG_DIR"] == expected)
        }
    }

    @Test("a demo folder that's missing, a file or too deep for a socket exits 2 and sends nothing")
    func demoMisread() throws {
        try inFolders { support, demo in
            let app = FakeTransport(reply: .done(""))
            let file = demo.appendingPathComponent("shipyard/config.toml")
            try Data().write(to: file)
            let deep = demo.appendingPathComponent(String(repeating: "d", count: 100), isDirectory: true)
            try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)

            let missing = shipyard(["app", "open", "--demo", "/nonexistent"], transport: app, support: support)
            #expect(missing == CommandResult(error: "shipyard app open: no folder at /nonexistent\n" + ControlCommand.usageText, status: 2))
            #expect(shipyard(["app", "open", "--demo", file.path], transport: app, support: support).status == 2)
            let tooDeep = shipyard(["app", "open", "--demo", deep.path], transport: app, support: support)
            #expect(tooDeep.status == 2)
            #expect(tooDeep.error.contains("use a folder with a shorter path"))
            #expect(app.exchanges.current.isEmpty)
            #expect(DemoPointer.recorded(in: support) == nil)
        }
    }

    // MARK: - Quit

    @Test("quit asks the app to quit, then returns once nothing answers, looking with a short timeout")
    func quit() {
        // The quit is answered; the app still answers one look, then it's gone.
        let app = FakeTransport { request, index in
            switch (request, index) {
            case (.appQuit, _): .success(ControlReply.done("shipyard quit\n").encoded())
            case (_, 1): .success(ControlReply.done(Self.status.text).encoded())
            default: .failure(.notRunning)
            }
        }

        let result = shipyard("app", "quit", transport: app)

        #expect(result == CommandResult(output: "shipyard quit\n"))
        #expect(app.requests == [.appQuit, .appStatus(json: false), .appStatus(json: false)])
        #expect(app.exchanges.current.map(\.timeout) == [15, 1, 1])
    }

    @Test("quit exits 1 when the app still answers 10 seconds after saying it would quit")
    func quitNeverGoes() {
        let result = shipyard("app", "quit", transport: FakeTransport(reply: .done("shipyard quit\n")))

        #expect(result == CommandResult(error: "shipyard said it would quit, but it still answers after 10 seconds\n", status: 1))
    }

    // MARK: - Arguments

    @Test("arguments that don't read exit 2 with the usage and send nothing", arguments: [
        (["app"], ""),
        (["app", "spin"], "shipyard app: unknown command `spin`\n"),
        (["app", "status", "--yaml"], "shipyard app status: unexpected `--yaml`\n"),
        (["app", "status", "--json", "now"], "shipyard app status: unexpected `now`\n"),
        (["app", "quit", "now"], "shipyard app quit: unexpected `now`\n"),
        (["app", "open", "--fast"], "shipyard app open: unexpected `--fast`\n"),
        (["app", "open", "--demo"], "shipyard app open: --demo needs a folder\n"),
        (["app", "open", "--demo", "/tmp", "now"], "shipyard app open: unexpected `now`\n"),
    ])
    func misread(arguments: [String], line: String) {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(arguments, transport: app)

        #expect(result == CommandResult(error: line + ControlCommand.usageText, status: 2))
        #expect(app.exchanges.current.isEmpty)
    }

    @Test("app --help prints the app usage; shipyard --help lists app")
    func help() {
        let app = FakeTransport(reply: .done(""))

        #expect(shipyard("app", "--help", transport: app) == CommandResult(output: ControlCommand.usageText))
        #expect(shipyard("app", "status", "-h", transport: app) == CommandResult(output: ControlCommand.usageText))
        #expect(shipyard("--help", transport: app).output.contains("shipyard app open [--demo <folder>] | quit | status [--json]"))
        #expect(app.exchanges.current.isEmpty)
    }

    // MARK: - A build without app control

    @Test("a build without app control refuses app with a pointer to the Mac, exit 2, and doesn't list it")
    func withoutControl() {
        let table = CommandTable()
        let environment = CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: [:])

        let result = ShipyardCLI.run(["app", "status"], table: table, environment: environment, now: Date())

        #expect(result == CommandResult(error: "shipyard: `shipyard app` runs on the Mac, where the app is\n", status: 2))
        #expect(!ShipyardCLI.usage(table).contains("shipyard app"))
    }
}

extension Array {
    /// The one element, or nil when there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
