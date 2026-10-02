import Foundation

/// Runs a ping's Herdr action (`--herdr`): focuses the tab or pane it
/// names through the `herdr` command, so `Shipyard` can then bring
/// `[herdr] terminal` forward. Herdr has no command that focuses a pane by
/// its id, so a pane's tab is looked up (`herdr pane get`) and focused
/// (`herdr tab focus`); a tab is focused at once.
///
/// It runs `herdr` itself, not through a shell, behind the `ShellRunning`
/// port the skill installer uses (standard output and error together), so
/// tests answer for `herdr`. An `.app` starts with an almost empty `PATH`,
/// so `herdr` is looked for where its installer and Homebrew put it first,
/// then on `PATH`, as `gh` is.
public struct HerdrFocus: Sendable {
    /// Where `herdr` is looked for before `PATH`, under the home folder `home`.
    public static func knownPaths(home: URL) -> [String] {
        [
            home.appendingPathComponent(".local/bin/herdr").path,
            "/opt/homebrew/bin/herdr",
            "/usr/local/bin/herdr",
        ]
    }

    private let home: URL
    private let pathEnvironment: String?
    private let isExecutable: @Sendable (String) -> Bool
    private let runner: any ShellRunning
    private let timeout: TimeInterval
    private let sleep: Sleep

    /// How long one `herdr` run may take before it's stopped and the
    /// action fails: Herdr answers at once when it's well.
    public static let defaultTimeout: TimeInterval = 5

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        runner: any ShellRunning = ProcessShellRunner(),
        timeout: TimeInterval = HerdrFocus.defaultTimeout,
        sleep: @escaping Sleep = systemSleep
    ) {
        self.home = home
        self.pathEnvironment = pathEnvironment
        self.isExecutable = isExecutable
        self.runner = runner
        self.timeout = timeout
        self.sleep = sleep
    }

    /// Whether `id` is a tab's id (`w1:t2`); any other is taken for a pane's.
    static func isTab(_ id: String) -> Bool {
        id.range(of: ":t[0-9]+$", options: .regularExpression) != nil
    }

    /// The first `herdr` found: the known paths, then each `PATH` directory.
    func locate() -> String? {
        if let known = Self.knownPaths(home: home).first(where: isExecutable) { return known }
        for directory in (pathEnvironment ?? "").split(separator: ":") {
            let candidate = directory.hasSuffix("/") ? "\(directory)herdr" : "\(directory)/herdr"
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// Focuses the tab `id` names, or the tab of the pane it names, and
    /// says how it went: `failed` when `herdr` isn't found or won't run,
    /// when Herdr isn't running or doesn't answer within `timeout`, and
    /// when the tab or pane is gone.
    public func focus(_ id: String) async -> ActionOutcome {
        guard let herdr = locate() else { return .failed("No herdr", detail: "Couldn't find herdr") }
        var tab = id
        if !Self.isTab(id) {
            switch await run(herdr, ["pane", "get", id], about: id) {
            case .failure(let reason): return reason.outcome
            case .success(let answer):
                guard let found = (answer["pane"] as? [String: Any])?["tab_id"] as? String else {
                    return .failed("No tab", detail: "Herdr didn't say which tab pane \(id) is in")
                }
                tab = found
            }
        }
        switch await run(herdr, ["tab", "focus", tab], about: tab) {
        case .failure(let reason): return reason.outcome
        case .success: return .done
        }
    }

    /// Why a `herdr` command failed: in a few words for the ping's row,
    /// and whole for its hover card.
    struct Failure: Error {
        var reason: String
        var detail: String

        var outcome: ActionOutcome { .failed(reason, detail: detail) }
    }

    /// Runs `herdr` with `arguments` and reads its answer, one JSON object:
    /// its `result` when it worked, else why not, for the tab or pane `id`.
    private func run(_ herdr: String, _ arguments: [String], about id: String) async -> Result<[String: Any], Failure> {
        let output: ShellOutput?
        switch await runInTime(ShellInvocation(executable: herdr, arguments: arguments)) {
        case .timedOut: return .failure(Failure(reason: "No answer", detail: "Herdr didn't answer"))
        case .finished(let finished): output = finished
        }
        guard let output else {
            return .failure(Failure(reason: "No herdr", detail: "Couldn't run herdr"))
        }
        let answer = (try? JSONSerialization.jsonObject(with: Data(output.output.utf8))) as? [String: Any]
        if output.status == 0 {
            return .success(answer?["result"] as? [String: Any] ?? [:])
        }
        let error = answer?["error"] as? [String: Any]
        switch error?["code"] as? String {
        case "pane_not_found": return .failure(Failure(reason: "Pane gone", detail: "Herdr pane \(id) is gone"))
        case "tab_not_found": return .failure(Failure(reason: "Tab gone", detail: "Herdr tab \(id) is gone"))
        case "server_not_running": return .failure(Failure(reason: "Herdr off", detail: "Herdr isn't running"))
        default: return .failure(Failure(reason: "No focus", detail: "Herdr couldn't focus \(id)"))
        }
    }

    private enum Run: Sendable {
        case finished(ShellOutput?)
        case timedOut
    }

    /// Runs `invocation`, racing it against `timeout`: whichever ends first
    /// stops the other (the runner returns at once when cancelled, and
    /// `ProcessShellRunner` stops the process).
    private func runInTime(_ invocation: ShellInvocation) async -> Run {
        let runner = runner, timeout = timeout, sleep = sleep
        return await withTaskGroup(of: Run?.self) { group in
            group.addTask { .finished(await runner.run(invocation)) }
            group.addTask {
                // `nil` when the sleep is cancelled: herdr answered first.
                guard (try? await sleep(timeout)) != nil else { return nil }
                return .timedOut
            }
            var first: Run?
            for await run in group where first == nil {
                first = run
                if run != nil { group.cancelAll() }
            }
            return first ?? .timedOut
        }
    }
}
