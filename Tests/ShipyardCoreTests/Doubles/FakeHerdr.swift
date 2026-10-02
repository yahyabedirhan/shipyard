import Foundation
import ShipyardCore

/// A `ShellRunning` standing in for the `herdr` command: a Herdr session
/// with the tabs and panes it was given, answering `herdr pane get <id>`,
/// `herdr tab get <id>` and `herdr tab focus <id>` with Herdr's JSON, and
/// recording every run. It's installed at `FakeHerdr.path` (one of
/// `HerdrFocus.knownPaths`) until `installed` is false; `running` false
/// answers as Herdr does with no server. `command` answers the same way for
/// the `shipyard` command, which runs programs synchronously.
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

    private static func error(_ code: String, _ message: String) -> ShellOutput {
        ShellOutput(status: 1, output: #"{"error":{"code":"\#(code)","message":"\#(message)"},"id":"cli"}"# + "\n")
    }
}
