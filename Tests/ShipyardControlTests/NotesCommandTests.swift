import Foundation
import ShipyardCommand
import ShipyardControl
import Testing

/// `shipyard notes check` as an agent runs it, through `ShipyardCLI.run`
/// with the Mac's table and an in-memory app at the end of the socket: the
/// app reads Notion through ntn and answers with the report.
@Suite("The notes command")
struct NotesCommandTests {
    func shipyard(_ arguments: String..., transport: FakeTransport) -> CommandResult {
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
            environment: CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: [:]),
            now: Date(timeIntervalSince1970: 0)
        )
    }

    @Test("notes check sends one unleased request, waits for Notion's reads, and prints the report the app answers with, exit 0")
    func inOrder() throws {
        let app = FakeTransport(reply: .done("shop  SHOP  3 open notes\n\nthe notes workspace is in order\n"))

        let result = shipyard("notes", "check", transport: app)

        #expect(result == CommandResult(output: "shop  SHOP  3 open notes\n\nthe notes workspace is in order\n"))
        let exchange = try #require(app.exchanges.current.only)
        #expect(String(decoding: exchange.request, as: UTF8.self) == #"{"command":"notes.check",\#(FakeProcessTable.wire()),"version":2}"#)
        #expect(app.requests == [.notesCheck])
        #expect(!ControlRequest.notesCheck.isLeased)
        #expect(ControlRequest.notesCheck.wait == 45)
    }

    @Test("a report with errors, or a run that reads no notes, exits 1 with the app's words")
    func errors() {
        let app = FakeTransport(reply: .refused("error: \"Shop\" has no Status property (select)\n\n1 error, 0 warnings"))

        let result = shipyard("notes", "check", transport: app)

        #expect(result == CommandResult(error: "error: \"Shop\" has no Status property (select)\n\n1 error, 0 warnings\n", status: 1))
    }

    @Test("notes --help prints its usage, other arguments exit 2 with it, and shipyard --help lists notes; none asks the app")
    func usage() {
        let app = FakeTransport(reply: .done(""))

        #expect(shipyard("notes", "--help", transport: app) == CommandResult(output: ControlCommands.notesUsage))
        #expect(shipyard("notes", "list", transport: app).status == CommandResult.usageStatus)
        #expect(shipyard("notes", transport: app).status == CommandResult.usageStatus)
        #expect(shipyard("--help", transport: app).output.contains("shipyard notes check"))
        #expect(app.exchanges.current.isEmpty)
    }

    @Test("a build without app control refuses notes with a pointer to the Mac, exit 2")
    func withoutControl() {
        let environment = CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: [:])

        let result = ShipyardCLI.run(["notes", "check"], table: CommandTable(), environment: environment, now: Date())

        #expect(result == CommandResult(error: "shipyard: `shipyard notes` runs on the Mac, where the app is\n", status: 2))
    }
}
