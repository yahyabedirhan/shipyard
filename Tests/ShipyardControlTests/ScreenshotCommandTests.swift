import Foundation
import ShipyardCommand
import ShipyardControl
import Testing

/// `shipyard screenshot …` as an agent runs it, through `ShipyardCLI.run`
/// with the Mac's table and an in-memory app at the end of the socket: the
/// request it sends (its path made absolute against the working folder),
/// what it prints and how it exits.
@Suite("The screenshot command")
struct ScreenshotCommandTests {
    func shipyard(_ arguments: String..., transport: FakeTransport) -> CommandResult {
        shipyard(arguments, transport: transport)
    }

    func shipyard(_ arguments: [String], transport: FakeTransport) -> CommandResult {
        var table = CommandTable()
        table.add(ControlCommands.entries(
            support: URL(fileURLWithPath: "/Users/agent/Library/Application Support/Shipyard", isDirectory: true),
            launcher: RecordingLauncher(),
            transport: transport,
            processes: FakeProcessTable.agent,
            pause: { _ in }
        ))
        return ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work/shop", isDirectory: true), variables: [:]),
            now: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("the request names an absolute path, the appearance, whether it's the menu bar icon and whether the indicator stays", arguments: [
        (["/tmp/x.png"], ControlRequest.screenshot(path: "/tmp/x.png", appearance: nil, menuBarIcon: false, withIndicator: false),
         #"{"command":"screenshot",\#(FakeProcessTable.wire(place: "/work/shop")),"menuBarIcon":false,"path":"\/tmp\/x.png","version":2,"withIndicator":false}"#),
        (["shots/x.PNG", "--appearance", "dark"],
         .screenshot(path: "/work/shop/shots/x.PNG", appearance: .dark, menuBarIcon: false, withIndicator: false),
         #"{"appearance":"dark","command":"screenshot",\#(FakeProcessTable.wire(place: "/work/shop")),"menuBarIcon":false,"path":"\/work\/shop\/shots\/x.PNG","version":2,"withIndicator":false}"#),
        (["--menu-bar-icon", "--appearance", "light", "../icon.png"],
         .screenshot(path: "/work/icon.png", appearance: .light, menuBarIcon: true, withIndicator: false),
         #"{"appearance":"light","command":"screenshot",\#(FakeProcessTable.wire(place: "/work/shop")),"menuBarIcon":true,"path":"\/work\/icon.png","version":2,"withIndicator":false}"#),
        (["/tmp/x.png", "--with-indicator"], .screenshot(path: "/tmp/x.png", appearance: nil, menuBarIcon: false, withIndicator: true),
         #"{"command":"screenshot",\#(FakeProcessTable.wire(place: "/work/shop")),"menuBarIcon":false,"path":"\/tmp\/x.png","version":2,"withIndicator":true}"#),
        (["--with-indicator", "--menu-bar-icon", "/tmp/i.png"], .screenshot(path: "/tmp/i.png", appearance: nil, menuBarIcon: true, withIndicator: true),
         #"{"command":"screenshot",\#(FakeProcessTable.wire(place: "/work/shop")),"menuBarIcon":true,"path":"\/tmp\/i.png","version":2,"withIndicator":true}"#),
    ])
    func sends(arguments: [String], request: ControlRequest, wire: String) throws {
        let app = FakeTransport(reply: .done("/tmp/x.png\n"))

        let result = shipyard(["screenshot"] + arguments, transport: app)

        #expect(result == CommandResult(output: "/tmp/x.png\n"))
        let exchange = try #require(app.exchanges.current.only)
        #expect(String(decoding: exchange.request, as: UTF8.self) == wire)
        #expect(app.requests == [request])
    }

    @Test("a rendered panel prints the path and the fallback's note on standard error, exit 0")
    func rendered() {
        let app = FakeTransport(reply: .done("/tmp/x.png\n", note: "captured by rendering: ScreenCaptureKit: declined\n"))

        let result = shipyard("screenshot", "/tmp/x.png", transport: app)

        #expect(result == CommandResult(output: "/tmp/x.png\n", error: "captured by rendering: ScreenCaptureKit: declined\n"))
    }

    @Test("both ways failing exits 1 with the app's reason; no app exits 1 saying how to open it")
    func failed() {
        let app = FakeTransport(reply: .refused("couldn't capture the panel (no window) or render it"))

        #expect(shipyard("screenshot", "/tmp/x.png", transport: app)
            == CommandResult(error: "couldn't capture the panel (no window) or render it\n", status: 1))
        #expect(shipyard("screenshot", "/tmp/x.png", transport: .nothingListens)
            == CommandResult(error: "shipyard isn't running; `shipyard app open`\n", status: 1))
    }

    @Test("arguments that don't read exit 2 with the screenshot usage and send nothing", arguments: [
        ([String](), "shipyard screenshot: missing <file.png>\n"),
        (["x.jpg"], "shipyard screenshot: `x.jpg` isn't a .png file\n"),
        (["x.png", "y.png"], "shipyard screenshot: unexpected `y.png`\n"),
        (["x.png", "--appearance"], "shipyard screenshot: --appearance needs light or dark\n"),
        (["x.png", "--appearance", "sepia"], "shipyard screenshot: no appearance `sepia`; it's light or dark\n"),
        (["x.png", "--dark"], "shipyard screenshot: unknown option `--dark`\n"),
    ])
    func misread(arguments: [String], line: String) {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(["screenshot"] + arguments, transport: app)

        #expect(result == CommandResult(error: line + ScreenshotCommand.usageText, status: 2))
        #expect(app.exchanges.current.isEmpty)
    }

    @Test("screenshot --help prints its usage; shipyard --help lists screenshot")
    func help() {
        let app = FakeTransport(reply: .done(""))

        #expect(shipyard("screenshot", "--help", transport: app) == CommandResult(output: ScreenshotCommand.usageText))
        let help = shipyard("--help", transport: app).output
        #expect(help.contains("shipyard screenshot <file.png> [--appearance light|dark] [--menu-bar-icon]\n"))
        #expect(help.contains("[--with-indicator]"))
        #expect(app.exchanges.current.isEmpty)
    }

    @Test("a build without app control refuses screenshot with a pointer to the Mac, exit 2")
    func withoutControl() {
        let environment = CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: [:])

        let result = ShipyardCLI.run(["screenshot", "x.png"], table: CommandTable(), environment: environment, now: Date())

        #expect(result == CommandResult(error: "shipyard: `shipyard screenshot` runs on the Mac, where the app is\n", status: 2))
    }
}
