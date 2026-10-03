import Foundation
import ShipyardCommand

/// Runs a ping's Herdr action (`--herdr`): focuses the tab or pane it
/// names through the `herdr` command (`HerdrCommand`), so `Shipyard` can
/// then bring `[herdr] terminal` forward. Herdr has no command that
/// focuses a pane by its id, so a pane's tab is looked up (`herdr pane
/// get`) and focused (`herdr tab focus`); a tab is focused at once. A
/// ping sent from a named Herdr session is focused on that session's
/// server (`herdr --session <name>`), since each session numbers its tabs
/// and panes alike.
///
/// A remote ping's tab or pane is on its machine, so it's focused through
/// `herdr --machine <label>`: a pane by its agent (`herdr agent focus`),
/// or by its tab, as above, when no agent occupies it. The Mac's Herdr
/// window moves to it only when it already shows that machine; otherwise
/// the machine's workspace turns red in Herdr's sidebar, and opening it
/// lands there.
public struct HerdrFocus: Sendable {
    /// Where `herdr` is looked for before `PATH`, under the home folder `home`.
    public static func knownPaths(home: URL) -> [String] {
        HerdrCommand.knownPaths(home: home)
    }

    private let herdr: HerdrCommand
    /// `herdr` for a run on a saved machine, timed by `machineTimeout`.
    private let remote: HerdrCommand

    /// How long one `herdr` run may take before it's stopped and the
    /// action fails: Herdr answers at once when it's well.
    public static let defaultTimeout: TimeInterval = 5
    /// How long one `herdr --machine` run may take: Herdr may first have
    /// to connect to the machine.
    public static let defaultMachineTimeout: TimeInterval = 15

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        runner: any ShellRunning = ProcessShellRunner(),
        timeout: TimeInterval = HerdrFocus.defaultTimeout,
        machineTimeout: TimeInterval = HerdrFocus.defaultMachineTimeout,
        sleep: @escaping Sleep = systemSleep
    ) {
        herdr = HerdrCommand(
            home: home,
            pathEnvironment: pathEnvironment,
            isExecutable: isExecutable,
            runner: runner,
            timeout: timeout,
            sleep: sleep
        )
        remote = HerdrCommand(
            home: home,
            pathEnvironment: pathEnvironment,
            isExecutable: isExecutable,
            runner: runner,
            timeout: machineTimeout,
            sleep: sleep
        )
    }

    /// Whether `id` is a tab's id (`w1:t2`); any other is taken for a pane's.
    static func isTab(_ id: String) -> Bool {
        id.range(of: ":t[0-9]+$", options: .regularExpression) != nil
    }

    /// The first `herdr` found: the known paths, then each `PATH` directory.
    func locate() -> String? {
        herdr.locate()
    }

    /// Focuses the tab `id` names, or the tab of the pane it names, and
    /// says how it went: `failed` when `herdr` isn't found or won't run,
    /// when Herdr isn't running or doesn't answer within `timeout`, and
    /// when the tab or pane is gone. In the named local session `session`,
    /// each `herdr` run targets that session's server.
    ///
    /// On the saved machine `machine`, a pane is focused by its agent
    /// first (`herdr --machine <label> agent focus <pane>`), and by its
    /// tab only when Herdr finds no agent there; it fails too when the
    /// machine can't be reached or doesn't answer within `machineTimeout`.
    public func focus(_ id: String, on machine: String? = nil, inSession session: String? = nil) async -> ActionOutcome {
        // A saved machine is reached in the session it names.
        let session = machine == nil ? session : nil
        var tab = id
        if !Self.isTab(id) {
            if machine != nil {
                switch await run(["agent", "focus", id], about: id, on: machine) {
                case .success: return .done
                case .failure(let failure) where failure.code != "agent_not_found": return failure.outcome
                case .failure: break
                }
            }
            switch await run(["pane", "get", id], about: id, on: machine, inSession: session) {
            case .failure(let failure): return failure.outcome
            case .success(let answer):
                guard let found = (answer["pane"] as? [String: Any])?["tab_id"] as? String else {
                    return .failed("No tab", detail: "Herdr didn't say which tab pane \(id) is in")
                }
                tab = found
            }
        }
        switch await run(["tab", "focus", tab], about: tab, on: machine, inSession: session) {
        case .failure(let failure): return failure.outcome
        case .success: return .done
        }
    }

    /// Why a `herdr` command failed: in a few words for the ping's row,
    /// whole for its hover card, with Herdr's error code when it gave one.
    struct Failure: Error {
        var reason: String
        var detail: String
        var code: String?

        var outcome: ActionOutcome { .failed(reason, detail: detail) }
    }

    /// Runs `herdr` with `arguments`, on the saved machine `machine` when
    /// it's given, else in the named local session `session`, and reads
    /// its answer, one JSON object: its `result` when it worked, else why
    /// not, for the tab or pane `id`.
    private func run(_ arguments: [String], about id: String, on machine: String?, inSession session: String? = nil) async -> Result<[String: Any], Failure> {
        switch await (machine == nil ? herdr : remote).run(arguments, on: machine, inSession: session) {
        case .notFound: return .failure(Failure(reason: "No herdr", detail: "Couldn't find herdr"))
        case .couldNotRun: return .failure(Failure(reason: "No herdr", detail: "Couldn't run herdr"))
        case .timedOut: return .failure(Failure(reason: "No answer", detail: machine.map { "\($0) didn't answer in time" } ?? "Herdr didn't answer"))
        case .finished(let output):
            return HerdrCommand.answer(output).mapError { error in
                Failure(
                    reason: Self.shortReason(error.code, on: machine, output: output.output),
                    detail: Self.reason(error.code, about: id, on: machine, inSession: session, output: output.output),
                    code: error.code
                )
            }
        }
    }

    /// What a failed run's row says in a few words, to fit its narrow
    /// column, from Herdr's error `code`, run on `machine` (if any); the
    /// hover card has the whole of it (`reason`).
    private static func shortReason(_ code: String?, on machine: String?, output: String) -> String {
        switch code {
        case "pane_not_found", "agent_not_found": "Pane gone"
        case "tab_not_found": "Tab gone"
        case "server_not_running": "Herdr off"
        case nil where machine != nil:
            // Herdr refused the label, or the machine never answered.
            HerdrCommand.refusal(output, machine: machine!) == nil ? "Offline" : "No machine"
        default: "No focus"
        }
    }

    /// What a failed run's hover card says, from Herdr's error `code` for the tab
    /// or pane `id`, run on `machine` or in the named session `session` (if
    /// either) with `output`.
    private static func reason(_ code: String?, about id: String, on machine: String?, inSession session: String?, output: String) -> String {
        let on = machine.map { " on \($0)" } ?? ""
        switch code {
        case "pane_not_found", "agent_not_found": return "Herdr pane \(id) is gone\(on)"
        case "tab_not_found": return "Herdr tab \(id) is gone\(on)"
        case "server_not_running": return session.map { "Herdr session \($0) isn't running" } ?? "Herdr isn't running\(on)"
        default:
            // Without Herdr's JSON error the machine never answered: Herdr
            // refused its label (`HerdrCommand.refusal`), or the connection failed.
            if let machine, code == nil {
                return HerdrCommand.refusal(output, machine: machine) ?? "Couldn't reach \(machine) through Herdr"
            }
            return "Herdr couldn't focus \(id)\(on)"
        }
    }
}
