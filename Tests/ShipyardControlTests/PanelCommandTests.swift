import Foundation
import ShipyardCommand
import ShipyardControl
import Testing

/// `shipyard panel …` as an agent runs it, through `ShipyardCLI.run` with
/// the Mac's table and an in-memory app at the end of the socket: what each
/// command sends, prints and exits with. Whether a project, kind or tab
/// exists is the app's to say; its refusals come back as replies.
@Suite("The panel command")
struct PanelCommandTests {
    /// Runs `shipyard <arguments>` in the Mac's build against `transport`.
    func shipyard(_ arguments: String..., transport: FakeTransport) -> CommandResult {
        shipyard(arguments, transport: transport)
    }

    func shipyard(_ arguments: [String], transport: FakeTransport) -> CommandResult {
        var table = CommandTable()
        table.add(ControlCommands.entries(
            support: URL(fileURLWithPath: "/Users/agent/Library/Application Support/Shipyard", isDirectory: true),
            launcher: RecordingLauncher(),
            transport: transport,
            pause: { _ in }
        ))
        return ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: [:]),
            now: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("each command sends its one request and prints the app's reply", arguments: [
        (["open"], ControlRequest.panelOpen, #"{"command":"panel.open","version":1}"#),
        (["close"], .panelClose, #"{"command":"panel.close","version":1}"#),
        (["fold", "shop"], .panelFold(project: "shop"), #"{"command":"panel.fold","project":"shop","version":1}"#),
        (["unfold", "my shop"], .panelUnfold(project: "my shop"), #"{"command":"panel.unfold","project":"my shop","version":1}"#),
        (["show-more", "shop", "pull-requests"], .panelShowMore(project: "shop", kind: "pull-requests"),
         #"{"command":"panel.showMore","kind":"pull-requests","project":"shop","version":1}"#),
        (["tab", "All"], .panelTab(name: "All"), #"{"command":"panel.tab","name":"All","version":1}"#),
    ])
    func sends(arguments: [String], request: ControlRequest, wire: String) throws {
        let app = FakeTransport(reply: .done("done\n"))

        let result = shipyard(["panel"] + arguments, transport: app)

        #expect(result == CommandResult(output: "done\n"))
        let exchange = try #require(app.exchanges.current.only)
        #expect(String(decoding: exchange.request, as: UTF8.self) == wire)
        #expect(app.requests == [request])
    }

    @Test("the app's refusal, naming what exists, exits 1 with its line")
    func refused() {
        let app = FakeTransport(reply: .refused("no tab is named `x`; the tabs are `All`, `shop`"))

        let result = shipyard("panel", "tab", "x", transport: app)

        #expect(result == CommandResult(error: "no tab is named `x`; the tabs are `All`, `shop`\n", status: 1))
    }

    @Test("when the app isn't running, a panel command exits 1 saying how to open it")
    func notRunning() {
        let result = shipyard("panel", "open", transport: .nothingListens)

        #expect(result == CommandResult(error: "shipyard isn't running; `shipyard app open`\n", status: 1))
    }

    @Test("arguments that don't read exit 2 with the panel usage and send nothing", arguments: [
        (["panel"], ""),
        (["panel", "spin"], "shipyard panel: unknown command `spin`\n"),
        (["panel", "tab"], "shipyard panel tab: missing <name>\n"),
        (["panel", "show-more", "shop"], "shipyard panel show-more: missing <kind>\n"),
        (["panel", "show-more"], "shipyard panel show-more: missing <project> <kind>\n"),
        (["panel", "fold", "shop", "blog"], "shipyard panel fold: unexpected `blog`\n"),
        (["panel", "open", "now"], "shipyard panel open: unexpected `now`\n"),
    ])
    func misread(arguments: [String], line: String) {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(arguments, transport: app)

        #expect(result == CommandResult(error: line + PanelCommand.usageText, status: 2))
        #expect(app.exchanges.current.isEmpty)
    }

    @Test("panel --help prints the panel usage; shipyard --help lists panel")
    func help() {
        let app = FakeTransport(reply: .done(""))

        #expect(shipyard("panel", "--help", transport: app) == CommandResult(output: PanelCommand.usageText))
        #expect(shipyard("panel", "fold", "-h", transport: app) == CommandResult(output: PanelCommand.usageText))
        #expect(shipyard("--help", transport: app).output.contains("shipyard panel open | close | fold <project>"))
        #expect(app.exchanges.current.isEmpty)
    }

    @Test("a build without app control refuses panel with a pointer to the Mac, exit 2")
    func withoutControl() {
        let environment = CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: [:])

        let result = ShipyardCLI.run(["panel", "open"], table: CommandTable(), environment: environment, now: Date())

        #expect(result == CommandResult(error: "shipyard: `shipyard panel` runs on the Mac, where the app is\n", status: 2))
    }
}
