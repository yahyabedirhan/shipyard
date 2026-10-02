import Foundation
import ShipyardCore

/// A `ShellRunning` standing in for the `herdr` command: a Herdr session
/// with the tabs and panes it was given, answering `herdr pane get <id>`,
/// `herdr tab get <id>` and `herdr tab focus <id>` with Herdr's JSON, and
/// recording every run. It's installed at `FakeHerdr.path` (one of
/// `HerdrFocus.knownPaths`) until `installed` is false; `running` false
/// answers as Herdr does with no server. `command` answers the same way for
/// the `shipyard` command, which runs programs synchronously.
///
/// It knows saved machines too (`addMachine`): `herdr --machine <label>
/// plugin action invoke list --plugin yahyabedirhan.herdr-shipyard` starts
/// a command log record of the machine's pings as `shipyard ping list
/// --json` prints them, and `… plugin log list --plugin …` lists the
/// machine's records, as Herdr 0.9.3 does. A record can stay `running` for
/// a number of log lists first. A label it doesn't know is refused.
final class FakeHerdr: ShellRunning {
    static let path = "/usr/local/bin/herdr"

    private let state = Locked(State())

    private struct State {
        var installed = true
        var running = true
        /// Each tab's label (empty for none).
        var tabs: [String: String] = [:]
        /// Each pane's tab.
        var panes: [String: String] = [:]
        /// Each pane's working folder, when it has one.
        var folders: [String: String] = [:]
        /// Each pane's agent status, when it has one.
        var statuses: [String: String] = [:]
        var runs: [[String]] = []
        var focused: [String] = []
        var machines: [String: Machine] = [:]
        var nextLog = 1
    }

    /// A saved machine with the herdr-shipyard plugin installed.
    private struct Machine {
        /// What its `list` action prints.
        var output: String
        /// How many log lists a new record stays `running` for.
        var runningFor = 0
        /// Its command log records, oldest first.
        var logs: [Log] = []
    }

    private struct Log {
        var id: String
        var stdout: String
        var runningFor: Int
        var started: Int
    }

    var installed: Bool {
        get { state.current.installed }
        set { state.withValue { $0.installed = newValue } }
    }

    var running: Bool {
        get { state.current.running }
        set { state.withValue { $0.running = newValue } }
    }

    /// Every `herdr` run's arguments, in order.
    var runs: [[String]] { state.current.runs }
    /// The tabs focused, in order.
    var focused: [String] { state.current.focused }

    /// Opens the tab `tab`, labelled `label`, with the panes `panes` in it.
    func open(tab: String, label: String = "", panes: [String] = []) {
        state.withValue { state in
            state.tabs[tab] = label
            for pane in panes { state.panes[pane] = tab }
        }
    }

    /// Opens the pane `pane` in tab `tab` (labelled `label`), working in
    /// `folder`, its agent's status `status`.
    func open(pane: String, tab: String, label: String = "", folder: URL? = nil, status: String? = nil) {
        state.withValue { state in
            state.tabs[tab] = label
            state.panes[pane] = tab
            state.folders[pane] = folder?.path
            state.statuses[pane] = status
        }
    }

    /// Whether `path` is this `herdr`, while it's installed.
    var isExecutable: @Sendable (String) -> Bool {
        { [self] path in path == FakeHerdr.path && installed }
    }

    /// `HerdrFocus` over this Herdr, with no `PATH` to search.
    var focus: HerdrFocus {
        HerdrFocus(
            home: URL(fileURLWithPath: "/nonexistent-home"),
            pathEnvironment: nil,
            isExecutable: isExecutable,
            runner: self
        )
    }

    /// Saves the machine `label`, with the plugin's `list` action listing
    /// `pings` (as the machine's `shipyard` encodes them), each new record
    /// staying `running` for `runningFor` log lists.
    func addMachine(_ label: String, pings: [Ping] = [], runningFor: Int = 0) {
        state.withValue { $0.machines[label] = Machine(output: PingList.encode(pings), runningFor: runningFor) }
    }

    /// What the machine `label`'s `list` action lists from now on.
    func setPings(_ pings: [Ping], on label: String) {
        setListOutput(PingList.encode(pings), on: label)
    }

    /// What the machine `label`'s `list` action prints from now on, as is.
    func setListOutput(_ output: String, on label: String) {
        state.withValue { $0.machines[label]?.output = output }
    }

    /// The runs made on the machine `label` (`--machine <label>` and what followed).
    func runs(on label: String) -> [[String]] {
        runs.filter { $0.starts(with: ["--machine", label]) }.map { Array($0.dropFirst(2)) }
    }

    /// `RemotePingReader` over this Herdr, with no `PATH` to search, asking
    /// again at once while a record is running.
    var remote: RemotePingReader {
        RemotePingReader(
            home: URL(fileURLWithPath: "/nonexistent-home"),
            pathEnvironment: nil,
            isExecutable: isExecutable,
            runner: self,
            wait: { _ in try Task.checkCancellation() }
        )
    }

    /// Runs this `herdr` as the `shipyard` command runs a program: at once.
    var command: GhCLI.Run {
        { [self] executable, arguments in
            guard executable == FakeHerdr.path, installed else { return nil }
            let output = answer(arguments)
            return CommandOutput(status: output.status, standardOutput: output.output)
        }
    }

    func run(_ invocation: ShellInvocation) async -> ShellOutput? {
        answer(invocation.arguments)
    }

    private func answer(_ arguments: [String]) -> ShellOutput {
        state.withValue { state in
            state.runs.append(arguments)
            let id = arguments.last ?? ""
            guard state.running else {
                return Self.error("server_not_running", "no herdr server is running")
            }
            if arguments.first == "--machine", arguments.count > 1 {
                return Self.answer(Array(arguments.dropFirst(2)), on: arguments[1], in: &state)
            }
            switch Array(arguments.dropLast()) {
            case ["pane", "get"]:
                guard let tab = state.panes[id] else { return Self.error("pane_not_found", "pane \(id) not found") }
                let cwd = state.folders[id].map { #","cwd":"\#($0)""# } ?? ""
                let status = state.statuses[id].map { #","agent_status":"\#($0)""# } ?? ""
                return ShellOutput(status: 0, output: #"{"id":"cli:pane:get","result":{"pane":{"pane_id":"\#(id)","tab_id":"\#(tab)"\#(cwd)\#(status)},"type":"pane_info"}}"# + "\n")
            case ["tab", "get"]:
                guard let label = state.tabs[id] else { return Self.error("tab_not_found", "tab \(id) not found") }
                return ShellOutput(status: 0, output: #"{"id":"cli:tab:get","result":{"tab":{"label":"\#(label)","tab_id":"\#(id)"},"type":"tab_info"}}"# + "\n")
            case ["tab", "focus"]:
                guard state.tabs[id] != nil else { return Self.error("tab_not_found", "tab \(id) not found") }
                state.focused.append(id)
                return ShellOutput(status: 0, output: #"{"id":"cli:tab:focus","result":{"type":"ok"}}"# + "\n")
            default:
                return ShellOutput(status: 2, output: "usage: herdr …\n")
            }
        }
    }

    /// Answers `arguments` run with `--machine <label>`.
    private static func answer(_ arguments: [String], on label: String, in state: inout State) -> ShellOutput {
        guard var machine = state.machines[label] else {
            // What Herdr says for a label it has no saved machine for isn't
            // pinned down; an error of this shape stands in for it.
            return error("machine_not_found", "no saved machine named \(label)")
        }
        defer { state.machines[label] = machine }
        let plugin = RemotePingReader.pluginID
        switch arguments {
        case ["plugin", "action", "invoke", RemotePingReader.actionID, "--plugin", plugin]:
            let log = Log(id: "plugin-log-\(state.nextLog)", stdout: machine.output, runningFor: machine.runningFor, started: 1_790_966_526_794 + state.nextLog)
            state.nextLog += 1
            machine.logs.append(log)
            let result: [String: Any] = [
                "type": "plugin_action_invoked",
                "action": ["action_id": RemotePingReader.actionID, "plugin_id": plugin],
                "context": [:] as [String: Any],
                "log": record(log),
            ]
            return json(["id": "cli:plugin", "result": result])
        case ["plugin", "log", "list", "--plugin", plugin]:
            let listed = machine.logs.map(record)
            for index in machine.logs.indices where machine.logs[index].runningFor > 0 {
                machine.logs[index].runningFor -= 1
            }
            return json(["id": "cli:plugin", "result": ["type": "plugin_log_list", "logs": listed] as [String: Any]])
        default:
            return ShellOutput(status: 2, output: "usage: herdr …\n")
        }
    }

    /// A command log record as Herdr lists it: no output while it's running.
    private static func record(_ log: Log) -> [String: Any] {
        var record: [String: Any] = [
            "log_id": log.id,
            "plugin_id": RemotePingReader.pluginID,
            "action_id": RemotePingReader.actionID,
            "command": ["sh", "list.sh"],
            "started_unix_ms": log.started,
            "status": log.runningFor > 0 ? "running" : "succeeded",
        ]
        if log.runningFor == 0 {
            record["finished_unix_ms"] = log.started + 3
            record["exit_code"] = 0
            record["stdout"] = log.stdout
            record["stderr"] = ""
        }
        return record
    }

    private static func json(_ object: [String: Any]) -> ShellOutput {
        let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return ShellOutput(status: 0, output: String(decoding: data, as: UTF8.self) + "\n")
    }

    private static func error(_ code: String, _ message: String) -> ShellOutput {
        ShellOutput(status: 1, output: #"{"error":{"code":"\#(code)","message":"\#(message)"},"id":"cli"}"# + "\n")
    }
}
