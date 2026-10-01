import Foundation
import ShipyardCore

/// A `ShellRunning` standing in for the `herdr` command: a Herdr session
/// with the tabs and panes it was given, answering `herdr pane get <id>`
/// and `herdr tab focus <id>` with Herdr's JSON, and recording every run.
/// It's installed at `FakeHerdr.path` (one of `HerdrFocus.knownPaths`)
/// until `installed` is false; `running` false answers as Herdr does with
/// no server.
final class FakeHerdr: ShellRunning {
    static let path = "/usr/local/bin/herdr"

    private let state = Locked(State())

    private struct State {
        var installed = true
        var running = true
        var tabs: Set<String> = []
        /// Each pane's tab.
        var panes: [String: String] = [:]
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

    /// Opens the tab `tab` with the panes `panes` in it.
    func open(tab: String, panes: [String] = []) {
        state.withValue { state in
            state.tabs.insert(tab)
            for pane in panes { state.panes[pane] = tab }
        }
    }

    /// `HerdrFocus` over this Herdr, with no `PATH` to search.
    var focus: HerdrFocus {
        HerdrFocus(
            home: URL(fileURLWithPath: "/nonexistent-home"),
            pathEnvironment: nil,
            isExecutable: { [self] path in path == FakeHerdr.path && installed },
            runner: self
        )
    }

    func run(_ invocation: ShellInvocation) async -> ShellOutput? {
        state.withValue { state in
            state.runs.append(invocation.arguments)
            let id = invocation.arguments.last ?? ""
            guard state.running else {
                return Self.error("server_not_running", "no herdr server is running")
            }
            switch Array(invocation.arguments.dropLast()) {
            case ["pane", "get"]:
                guard let tab = state.panes[id] else { return Self.error("pane_not_found", "pane \(id) not found") }
                return ShellOutput(status: 0, output: #"{"id":"cli:pane:get","result":{"pane":{"pane_id":"\#(id)","tab_id":"\#(tab)"},"type":"pane_info"}}"# + "\n")
            case ["tab", "focus"]:
                guard state.tabs.contains(id) else { return Self.error("tab_not_found", "tab \(id) not found") }
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
