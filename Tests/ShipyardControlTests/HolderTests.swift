import Foundation
import ShipyardCommand
import ShipyardControl
import Testing

/// The holder every app control request carries, as the `shipyard` command
/// works it out on each call: through `ShipyardCLI.run` with the Mac's
/// table, an in-memory app and a fake process table, what each command
/// sends as its `holder`.
@Suite("The holder")
struct HolderTests {
    /// Runs `shipyard <arguments>` in `/work/shop` with `variables`, in the
    /// process tree `processes`, and returns the holders the app was sent.
    func holders(
        _ arguments: [String],
        variables: [String: String] = [:],
        processes: FakeProcessTable = .agent
    ) -> [Holder] {
        let app = FakeTransport(reply: .done("done\n"))
        var table = CommandTable()
        table.add(ControlCommands.entries(
            support: URL(fileURLWithPath: "/Users/agent/Library/Application Support/Shipyard", isDirectory: true),
            launcher: RecordingLauncher(),
            transport: app,
            processes: processes,
            pause: { _ in }
        ))
        let result = ShipyardCLI.run(
            arguments,
            table: table,
            environment: CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/work/shop", isDirectory: true), variables: variables),
            now: Date(timeIntervalSince1970: 0)
        )
        #expect(result.status == 0)
        return app.messages.map(\.holder)
    }

    static let commands = [
        ["app", "status"], ["app", "status", "--json"], ["app", "open"], ["panel", "open"], ["panel", "fold", "shop"],
        ["screenshot", "/tmp/x.png"], ["screenshot", "/tmp/i.png", "--menu-bar-icon"],
        ["control", "take"], ["control", "take", "--wait", "30"], ["control", "release"],
    ]

    @Test("in a Claude Code session, every command is sent as that session, whatever process runs it", arguments: commands)
    func session(arguments: [String]) {
        let sent = holders(arguments, variables: ["CLAUDE_CODE_SESSION_ID": "5f1c", "HOME": "/Users/agent"])

        #expect(!sent.isEmpty)
        #expect(sent.allSatisfy { $0 == Holder(key: "CLAUDE_CODE_SESSION_ID=5f1c", name: "Claude Code", place: "/work/shop") })
    }

    @Test("without a session, every command is sent as the nearest ancestor that isn't a shell, by pid and start time", arguments: commands)
    func process(arguments: [String]) {
        let sent = holders(arguments, variables: ["CLAUDE_CODE_SESSION_ID": ""])

        #expect(!sent.isEmpty)
        #expect(sent.allSatisfy { $0 == Holder(key: "process:300@800250000", name: "claude", place: "/work/shop") })
    }

    @Test("a login shell, or several shells, between the command and the agent are passed over")
    func shells() {
        let tree = FakeProcessTable(currentPID: 900, processes: [
            ProcessRecord(pid: 900, parent: 800, started: Date(timeIntervalSince1970: 50), name: "shipyard"),
            ProcessRecord(pid: 800, parent: 700, started: Date(timeIntervalSince1970: 40), name: "bash"),
            ProcessRecord(pid: 700, parent: 600, started: Date(timeIntervalSince1970: 30), name: "-zsh"),
            ProcessRecord(pid: 600, parent: 1, started: Date(timeIntervalSince1970: 20), name: "codex"),
        ])

        #expect(holders(["panel", "open"], processes: tree) == [Holder(key: "process:600@20000000", name: "codex", place: "/work/shop")])
    }

    @Test("with nothing but shells up to launchd, the farthest shell holds; with no process to read, an unknown agent")
    func noAgent() {
        let shells = FakeProcessTable(currentPID: 900, processes: [
            ProcessRecord(pid: 900, parent: 800, started: Date(timeIntervalSince1970: 50), name: "shipyard"),
            ProcessRecord(pid: 800, parent: 700, started: Date(timeIntervalSince1970: 40), name: "bash"),
            ProcessRecord(pid: 700, parent: 1, started: Date(timeIntervalSince1970: 30), name: "-zsh"),
        ])
        #expect(holders(["panel", "open"], processes: shells) == [Holder(key: "process:700@30000000", name: "-zsh", place: "/work/shop")])

        let unreadable = FakeProcessTable(currentPID: 900, processes: [])
        #expect(holders(["panel", "open"], processes: unreadable)
            == [Holder(key: "process:unknown", name: "an unknown agent", place: "/work/shop")])
    }

    @Test("in a Herdr pane the place is the pane, never part of the key")
    func herdrPane() {
        let sent = holders(["panel", "open"], variables: ["HERDR_PANE_ID": "w1-2", "CLAUDE_CODE_SESSION_ID": "5f1c"])

        #expect(sent == [Holder(key: "CLAUDE_CODE_SESSION_ID=5f1c", name: "Claude Code", place: "Herdr pane w1-2")])
    }

    @Test("--key names the holder's key for that command only; its name and place stay the ones worked out")
    func key() {
        let session = ["CLAUDE_CODE_SESSION_ID": "5f1c"]

        let taken = holders(["control", "take", "--key", "my-run", "--wait", "5"], variables: session)
        let released = holders(["control", "release", "--key", "my-run"], variables: session)
        let next = holders(["panel", "open"], variables: session)

        #expect(taken == [Holder(key: "my-run", name: "Claude Code", place: "/work/shop")])
        #expect(released == taken)
        #expect(next == [Holder(key: "CLAUDE_CODE_SESSION_ID=5f1c", name: "Claude Code", place: "/work/shop")])
    }
}
