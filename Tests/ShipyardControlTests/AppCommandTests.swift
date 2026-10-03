import Foundation
import ShipyardCommand
import ShipyardControl
import Testing

/// `shipyard app open | quit | status` as an agent runs it, through
/// `ShipyardCLI.run` with the Mac's table, an in-memory app at the end of
/// the socket and a recording launcher: what each command sends, prints and
/// exits with.
@Suite("The app command")
struct AppCommandTests {
    static let support = URL(fileURLWithPath: "/Users/agent/Library/Application Support/Shipyard", isDirectory: true)
    static let status = AppStatus(version: "0.1.0", panelOpen: false, layout: "tabs", projects: ["shop", "blog"])

    /// Waits recorded, never slept.
    let pauses = Locked<[TimeInterval]>([])

    /// Runs `shipyard <arguments>` in the Mac's build against `transport`.
    func shipyard(_ arguments: String..., transport: FakeTransport, launcher: RecordingLauncher = RecordingLauncher()) -> CommandResult {
        shipyard(arguments, transport: transport, launcher: launcher)
    }

    func shipyard(_ arguments: [String], transport: FakeTransport, launcher: RecordingLauncher = RecordingLauncher()) -> CommandResult {
        var table = CommandTable()
        let pauses = pauses
        table.add(ControlCommands.entries(
            support: Self.support,
            launcher: launcher,
            transport: transport,
            pause: { seconds in pauses.withValue { $0.append(seconds) } }
        ))
        return ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: [:]),
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
        #expect(String(decoding: exchange.request, as: UTF8.self) == #"{"command":"app.status","json":false,"version":1}"#)
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

    @Test("the status reads as lines, or as one JSON object")
    func statusFormats() {
        #expect(Self.status.text == """
            shipyard 0.1.0 is running
            panel: closed
            layout: tabs
            projects: shop, blog

            """)
        #expect(Self.status.json
            == #"{"layout":"tabs","panelOpen":false,"projects":["shop","blog"],"running":true,"version":"0.1.0"}"# + "\n")
        let none = AppStatus(version: "0.1.0", panelOpen: true, layout: "list", projects: [])
        #expect(none.text.contains("panel: open\n"))
        #expect(none.text.contains("projects: none\n"))
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

    @Test("open when the app runs launches nothing and prints its status")
    func openWhenRunning() {
        let launcher = RecordingLauncher()
        let app = FakeTransport(reply: .done(Self.status.text))

        let result = shipyard("app", "open", transport: app, launcher: launcher)

        #expect(result == CommandResult(output: Self.status.text))
        #expect(launcher.launches.current.isEmpty)
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
        #expect(app.requests == Array(repeating: .appStatus(json: false), count: 4))
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
        #expect(shipyard("--help", transport: app).output.contains("shipyard app open | quit | status [--json]"))
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
