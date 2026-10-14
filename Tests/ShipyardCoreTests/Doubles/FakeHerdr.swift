import Foundation
import ShipyardCommand
import ShipyardCore
import ShipyardNotices
import ShipyardPings

final class FakeHerdr: ShellRunning {
    static let path = "/usr/local/bin/herdr"

    private let state = Locked(State())

    private struct State {
        var installed = true
        var running = true
        var tabs: [String: String] = [:]
        var panes: [String: String] = [:]
        var folders: [String: String] = [:]
        var statuses: [String: String] = [:]
        var runs: [[String]] = []
        var focused: [String] = []
        var sessions: [String: [String: String]] = [:]
        var focusedInSessions: [String: [String]] = [:]
        var machines: [String: Machine] = [:]
        var nextLog = 1
        var timingOut = false
    }

    enum Reach {
        case up
        case disabled
        case unreachable
        case hanging
    }

    private struct Machine {
        var output: String
        var runningFor = 0
        var logs: [Log] = []
        var panes: [String: String] = [:]
        var tabs: Set<String> = []
        var agents: Set<String> = []
        var reach = Reach.up
        var notices: [String] = []
        var handed: [String] = []
        var holdsNotices = true
    }

    private struct Log {
        var id: String
        var action = RemotePingReader.actionID
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

    var runs: [[String]] { state.current.runs }
    var focused: [String] { state.current.focused }

    func open(tab: String, panes: [String] = []) {
        state.withValue { state in
            state.tabs[tab] = ""
            for pane in panes { state.panes[pane] = tab }
        }
    }

    func open(tab: String, panes: [String] = [], inSession session: String) {
        state.withValue { state in
            state.sessions[session, default: [:]][tab] = tab
            for pane in panes { state.sessions[session, default: [:]][pane] = tab }
        }
    }

    func focused(inSession session: String) -> [String] {
        state.current.focusedInSessions[session] ?? []
    }

    func open(pane: String, tab: String, label: String = "", folder: URL? = nil, status: String? = nil) {
        state.withValue { state in
            state.tabs[tab] = label
            state.panes[pane] = tab
            state.folders[pane] = folder?.path
            state.statuses[pane] = status
        }
    }

    func close(tab: String) {
        state.withValue { state in
            state.tabs[tab] = nil
            state.panes = state.panes.filter { $0.value != tab }
        }
    }

    func close(workspace: String) {
        state.withValue { state in
            state.tabs = state.tabs.filter { !$0.key.hasPrefix(workspace + ":") }
            state.panes = state.panes.filter { !$0.key.hasPrefix(workspace + ":") }
        }
    }

    var isExecutable: @Sendable (String) -> Bool {
        { [self] path in path == FakeHerdr.path && installed }
    }

    var focus: HerdrFocus {
        HerdrFocus(
            home: URL(fileURLWithPath: "/nonexistent-home"),
            pathEnvironment: nil,
            isExecutable: isExecutable,
            runner: self
        )
    }

    func addMachine(_ label: String, pings: [Ping] = [], runningFor: Int = 0) {
        state.withValue { $0.machines[label] = Machine(output: PingList.encode(pings), runningFor: runningFor) }
    }

    func setPings(_ pings: [Ping], on label: String) {
        setListOutput(PingList.encode(pings), on: label)
    }

    func setListOutput(_ output: String, on label: String) {
        state.withValue { $0.machines[label]?.output = output }
    }

    func open(pane: String, tab: String, agent: Bool = true, on label: String) {
        state.withValue { state in
            state.machines[label]?.panes[pane] = tab
            state.machines[label]?.tabs.insert(tab)
            if agent { state.machines[label]?.agents.insert(pane) }
        }
    }

    func queue(_ notice: QueuedNotice, on label: String) {
        queue(String(decoding: notice.encoded(), as: UTF8.self), on: label)
    }

    func queue(_ json: String, on label: String) {
        state.withValue { $0.machines[label]?.notices.append(json) }
    }

    func queued(on label: String) -> [String] {
        state.current.machines[label]?.notices ?? []
    }

    func withoutNotices(on label: String) {
        state.withValue { $0.machines[label]?.holdsNotices = false }
    }

    func setReach(_ reach: Reach, on label: String) {
        state.withValue { $0.machines[label]?.reach = reach }
    }

    func timeOutReads() {
        state.withValue { $0.timingOut = true }
    }

    func runs(on label: String) -> [[String]] {
        runs.filter { $0.starts(with: ["--machine", label]) }.map { Array($0.dropFirst(2)) }
    }

    var remote: RemotePingReader {
        RemotePingReader(
            home: URL(fileURLWithPath: "/nonexistent-home"),
            pathEnvironment: nil,
            isExecutable: isExecutable,
            runner: self,
            sleep: { [state] _ in
                while !state.withValue({ $0.timingOut }) {
                    try await Task.sleep(for: .milliseconds(2))
                }
            },
            wait: { _ in try Task.checkCancellation() }
        )
    }

    var command: GhCLI.Run {
        { [self] executable, arguments in
            guard executable == FakeHerdr.path, installed else { return nil }
            let output = answer(arguments)
            return CommandOutput(status: output.status, standardOutput: output.output)
        }
    }

    func run(_ invocation: ShellInvocation) async -> ShellOutput? {
        let arguments = invocation.arguments
        if arguments.first == "--machine", arguments.count > 1, state.current.machines[arguments[1]]?.reach == .hanging {
            state.withValue { $0.runs.append(arguments) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
            }
            return ShellOutput(status: 143, output: "Terminated")
        }
        return answer(arguments)
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
            if arguments.first == "--session", arguments.count > 1, arguments[1] != "default" {
                return Self.answer(Array(arguments.dropFirst(2)), inSession: arguments[1], in: &state)
            }
            let arguments = arguments.first == "--session" ? Array(arguments.dropFirst(2)) : arguments
            if arguments == ["pane", "list"] {
                let panes = state.panes.sorted { $0.key < $1.key }.map { #"{"pane_id":"\#($0.key)","tab_id":"\#($0.value)"}"# }
                return ShellOutput(status: 0, output: #"{"id":"cli:pane:list","result":{"panes":[\#(panes.joined(separator: ","))],"type":"pane_list"}}"# + "\n")
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

    private static func answer(_ arguments: [String], inSession session: String, in state: inout State) -> ShellOutput {
        // Herdr's words when no server listens on the session's socket (`cli/server_not_running.rs`).
        guard let known = state.sessions[session] else {
            return error("server_not_running", "no herdr server is running at /herdr/sessions/\(session)/herdr.sock; run `herdr session attach \(session)` to start or attach it")
        }
        let id = arguments.last ?? ""
        switch arguments {
        case ["pane", "get", id] where !isTab(id):
            guard let tab = known[id] else { return error("pane_not_found", "pane \(id) not found") }
            return json(["id": "cli:pane:get", "result": ["type": "pane_info", "pane": ["pane_id": id, "tab_id": tab]] as [String: Any]])
        case ["tab", "focus", id] where isTab(id):
            guard known[id] != nil else { return error("tab_not_found", "tab \(id) not found") }
            state.focusedInSessions[session, default: []].append(id)
            return json(["id": "cli:tab:focus", "result": ["type": "ok"]])
        default:
            return ShellOutput(status: 2, output: "usage: herdr …\n")
        }
    }

    private static func isTab(_ id: String) -> Bool {
        id.range(of: ":t[0-9]+$", options: .regularExpression) != nil
    }

    private static func answer(_ arguments: [String], on label: String, in state: inout State) -> ShellOutput {
        guard var machine = state.machines[label] else {
            return ShellOutput(status: 2, output: "error: unknown machine '\(label)'; use `herdr machine list`\n")
        }
        switch machine.reach {
        case .up, .hanging:
            break
        case .disabled:
            return ShellOutput(status: 2, output: "error: machine '\(label)' is disabled\n")
        case .unreachable:
            // `main` returns the connection's io::Error, which Rust prints
            // in its Debug form; the inner text stands in for ssh's.
            return ShellOutput(status: 1, output: #"Error: Custom { kind: Other, error: "machine '\#(label)' (session default): ssh: connect to host \#(label) port 22: Connection timed out" }"# + "\n")
        }
        defer { state.machines[label] = machine }
        let plugin = RemotePingReader.pluginID
        switch arguments {
        case ["agent", "focus", arguments.last ?? ""]:
            let pane = arguments[2]
            guard machine.agents.contains(pane) else { return error("agent_not_found", "agent target \(pane) not found") }
            return json(["id": "cli:agent:focus", "result": ["type": "agent_info", "agent": ["pane_id": pane]] as [String: Any]])
        case ["pane", "get", arguments.last ?? ""]:
            let pane = arguments[2]
            guard let tab = machine.panes[pane] else { return error("pane_not_found", "pane \(pane) not found") }
            return json(["id": "cli:pane:get", "result": ["type": "pane_info", "pane": ["pane_id": pane, "tab_id": tab]] as [String: Any]])
        case ["tab", "focus", arguments.last ?? ""]:
            let tab = arguments[2]
            guard machine.tabs.contains(tab) else { return error("tab_not_found", "tab \(tab) not found") }
            return json(["id": "cli:tab:focus", "result": ["type": "ok"]])
        case ["plugin", "action", "invoke", arguments.count > 3 ? arguments[3] : "", "--plugin", plugin]:
            let action = arguments[3]
            let stdout: String
            switch action {
            case RemotePingReader.actionID:
                stdout = machine.output
            case RemotePingReader.noticesActionID where machine.holdsNotices:
                machine.handed = machine.notices
                stdout = #"{"version":1,"truncated":false,"notices":["# + machine.notices.joined(separator: ",") + "]}\n"
            case RemotePingReader.noticesReadActionID where machine.holdsNotices:
                let removed = machine.notices.filter { machine.handed.contains($0) }.count
                machine.notices.removeAll { machine.handed.contains($0) }
                machine.handed = []
                stdout = #"{"version":1,"removed":\#(removed)}"# + "\n"
            default:
                return error("plugin_action_not_found", "plugin action \(action) not found for plugin \(plugin)")
            }
            let log = Log(id: "plugin-log-\(state.nextLog)", action: action, stdout: stdout, runningFor: machine.runningFor, started: 1_790_966_526_794 + state.nextLog)
            state.nextLog += 1
            machine.logs.append(log)
            let result: [String: Any] = [
                "type": "plugin_action_invoked",
                "action": ["action_id": action, "plugin_id": plugin],
                "context": [:] as [String: Any],
                "log": record(log),
            ]
            return json(["id": "cli:plugin", "result": result])
        case ["plugin", "log", "list", "--plugin", plugin, "--limit", arguments.last ?? ""]:
            // Herdr's newest `--limit` records, oldest first (handle_plugin_log_list).
            guard let limit = Int(arguments.last ?? "") else { return error("invalid_limit", "invalid --limit value") }
            let listed = machine.logs.suffix(max(1, min(limit, 200))).map(record)
            for index in machine.logs.indices where machine.logs[index].runningFor > 0 {
                machine.logs[index].runningFor -= 1
            }
            return json(["id": "cli:plugin", "result": ["type": "plugin_log_list", "logs": listed] as [String: Any]])
        default:
            return ShellOutput(status: 2, output: "usage: herdr …\n")
        }
    }

    private static func record(_ log: Log) -> [String: Any] {
        var record: [String: Any] = [
            "log_id": log.id,
            "plugin_id": RemotePingReader.pluginID,
            "action_id": log.action,
            "command": ["sh", "\(log.action).sh"],
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
