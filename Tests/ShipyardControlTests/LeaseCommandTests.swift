import Foundation
import ShipyardCommand
import ShipyardControl
import Testing

/// `shipyard control take [--wait <seconds>] [--key <k>] | release [--key <k>]`
/// as an agent runs it, through `ShipyardCLI.run` with the Mac's table and
/// an in-memory app at the end of the socket: what each command sends,
/// with which timeout, prints and exits with. The lease's rules are the
/// app's, in `ControlLeaseTests`; its holder's key in `HolderTests`.
@Suite("The control command")
struct LeaseCommandTests {
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

    @Test("take and release each send one request, a take that waits reading its reply for the wait plus 15 seconds", arguments: [
        (["take"], ControlRequest.controlTake(waitSeconds: nil),
         #"{"command":"control.take",\#(FakeProcessTable.wire()),"version":2}"#, 15.0),
        (["take", "--wait", "30"], .controlTake(waitSeconds: 30),
         #"{"command":"control.take",\#(FakeProcessTable.wire()),"version":2,"waitSeconds":30}"#, 45),
        (["take", "--key", "k", "--wait", "0"], .controlTake(waitSeconds: 0),
         #"{"command":"control.take","holder":{"key":"k","name":"claude","place":"\/work"},"version":2,"waitSeconds":0}"#, 15),
        (["release"], .controlRelease, #"{"command":"control.release",\#(FakeProcessTable.wire()),"version":2}"#, 15),
    ])
    func sends(arguments: [String], request: ControlRequest, wire: String, timeout: TimeInterval) throws {
        let app = FakeTransport(reply: .done("done\n"))

        let result = shipyard(["control"] + arguments, transport: app)

        #expect(result == CommandResult(output: "done\n"))
        let exchange = try #require(app.exchanges.current.only)
        #expect(String(decoding: exchange.request, as: UTF8.self) == wire)
        #expect(exchange.timeout == timeout)
        #expect(app.requests == [request])
    }

    @Test("the app's answer prints as it is: held, released, or refused with exit 1")
    func answers() {
        let held = shipyard("control", "take", transport: FakeTransport(reply: .done("you hold shipyard until 12:05:00\n")))
        #expect(held == CommandResult(output: "you hold shipyard until 12:05:00\n"))

        let released = shipyard("control", "release", transport: FakeTransport(reply: .done("released shipyard\n")))
        #expect(released == CommandResult(output: "released shipyard\n"))

        let waited = "waited 30s; shipyard is still in use by codex in Herdr pane w1-2 until 12:05:00 (40s left)"
        let refused = shipyard("control", "take", "--wait", "30", transport: FakeTransport(reply: .refused(waited)))
        #expect(refused == CommandResult(error: waited + "\n", status: 1))

        let slow = shipyard("control", "take", "--wait", "30", transport: FakeTransport { _, _ in .failure(.timedOut) })
        #expect(slow == CommandResult(error: "shipyard didn't answer within 45 seconds\n", status: 1))

        let notRunning = shipyard("control", "release", transport: .nothingListens)
        #expect(notRunning == CommandResult(error: "shipyard isn't running; `shipyard app open`\n", status: 1))
    }

    @Test("arguments that don't read exit 2 with the control usage and send nothing", arguments: [
        (["control"], ""),
        (["control", "hold"], "shipyard control: unknown command `hold`\n"),
        (["control", "take", "now"], "shipyard control take: unexpected `now`\n"),
        (["control", "take", "--wait"], "shipyard control take: --wait needs a number of seconds\n"),
        (["control", "take", "--wait", "soon"], "shipyard control take: --wait takes whole seconds from 0 to 3600, not `soon`\n"),
        (["control", "take", "--wait", "-5"], "shipyard control take: --wait takes whole seconds from 0 to 3600, not `-5`\n"),
        (["control", "take", "--wait", "1.5"], "shipyard control take: --wait takes whole seconds from 0 to 3600, not `1.5`\n"),
        (["control", "take", "--wait", "3601"], "shipyard control take: --wait takes whole seconds from 0 to 3600, not `3601`\n"),
        (["control", "take", "--wait", "9223372036854775807"],
         "shipyard control take: --wait takes whole seconds from 0 to 3600, not `9223372036854775807`\n"),
        (["control", "take", "--wait", "5", "--wait", "6"], "shipyard control take: unexpected `--wait`\n"),
        (["control", "take", "--key"], "shipyard control take: --key needs a key\n"),
        (["control", "take", "--key", ""], "shipyard control take: --key needs a key\n"),
        (["control", "release", "--wait", "5"], "shipyard control release: unexpected `--wait`\n"),
        (["control", "release", "now"], "shipyard control release: unexpected `now`\n"),
    ])
    func misread(arguments: [String], line: String) {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(arguments, transport: app)

        #expect(result == CommandResult(error: line + LeaseCommand.usageText, status: 2))
        #expect(app.exchanges.current.isEmpty)
    }

    @Test("--wait is control take's alone: other commands refuse it at once", arguments: [
        ["panel", "open", "--wait", "5"], ["app", "status", "--wait", "5"], ["screenshot", "/tmp/x.png", "--wait", "5"],
    ])
    func waitElsewhere(arguments: [String]) {
        let app = FakeTransport(reply: .done(""))

        let result = shipyard(arguments, transport: app)

        #expect(result.status == 2)
        #expect(app.exchanges.current.isEmpty)
    }

    @Test("control --help prints the control usage; shipyard --help lists control")
    func help() {
        let app = FakeTransport(reply: .done(""))

        #expect(shipyard("control", "--help", transport: app) == CommandResult(output: LeaseCommand.usageText))
        #expect(shipyard("control", "take", "-h", transport: app) == CommandResult(output: LeaseCommand.usageText))
        #expect(shipyard("--help", transport: app).output
            .contains("shipyard control take [--wait <seconds>] [--key <k>] | release [--key <k>]"))
        #expect(app.exchanges.current.isEmpty)
    }

    @Test("a build without app control refuses control with a pointer to the Mac, exit 2")
    func withoutControl() {
        let environment = CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work"), variables: [:])

        let result = ShipyardCLI.run(["control", "take"], table: CommandTable(), environment: environment, now: Date())

        #expect(result == CommandResult(error: "shipyard: `shipyard control` runs on the Mac, where the app is\n", status: 2))
    }
}
