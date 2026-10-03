import Foundation

/// Runs the `herdr` command for shipyard: on this computer, or on a saved
/// machine through Herdr's own connection to it (`herdr --machine <label>
/// …`). The app's `HerdrFocus` focuses a ping's tab with it and its
/// `RemotePingReader` asks a machine for its pings; `shipyard herdr-event`
/// finds `herdr` with `locate`.
///
/// It runs `herdr` itself, not through a shell, behind the `ShellRunning`
/// port the skill installer uses (standard output and error together), so
/// tests answer for `herdr`. An `.app` starts with an almost empty `PATH`,
/// so `herdr` is looked for where its installer and Homebrew put it first,
/// then on `PATH`, as `gh` is. Each run races `timeout`.
public struct HerdrCommand: Sendable {
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

    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        runner: any ShellRunning = ProcessShellRunner(),
        timeout: TimeInterval,
        sleep: @escaping Sleep = systemSleep
    ) {
        self.home = home
        self.pathEnvironment = pathEnvironment
        self.isExecutable = isExecutable
        self.runner = runner
        self.timeout = timeout
        self.sleep = sleep
    }

    /// The first `herdr` found: the known paths, then each `PATH` directory.
    package func locate() -> String? {
        Self.locate(home: home, pathEnvironment: pathEnvironment, isExecutable: isExecutable)
    }

    /// The first `herdr` found under the home folder `home`: the known
    /// paths, then each directory of `pathEnvironment`.
    public static func locate(home: URL, pathEnvironment: String?, isExecutable: (String) -> Bool) -> String? {
        if let known = knownPaths(home: home).first(where: isExecutable) { return known }
        for directory in (pathEnvironment ?? "").split(separator: ":") {
            let candidate = directory.hasSuffix("/") ? "\(directory)herdr" : "\(directory)/herdr"
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// How a run went.
    package enum Outcome: Sendable {
        /// No `herdr` was found.
        case notFound
        /// `herdr` was found but wouldn't start.
        case couldNotRun
        /// It didn't finish within `timeout`, and was stopped.
        case timedOut
        /// It finished, with this status and output.
        case finished(ShellOutput)
    }

    /// Runs `herdr` with `arguments`, on the saved machine `machine` when
    /// it's given (`--machine <label>` first).
    package func run(_ arguments: [String], on machine: String? = nil) async -> Outcome {
        guard let herdr = locate() else { return .notFound }
        let prefix = machine.map { ["--machine", $0] } ?? []
        let invocation = ShellInvocation(executable: herdr, arguments: prefix + arguments)
        let runner = runner, timeout = timeout, sleep = sleep
        // Whichever ends first stops the other (the runner returns at once
        // when cancelled, and `ProcessShellRunner` stops the process).
        return await withTaskGroup(of: Outcome?.self) { group in
            group.addTask { await runner.run(invocation).map(Outcome.finished) ?? .couldNotRun }
            group.addTask {
                // `nil` when the sleep is cancelled: herdr answered first.
                guard (try? await sleep(timeout)) != nil else { return nil }
                return .timedOut
            }
            var first: Outcome?
            for await outcome in group where first == nil {
                first = outcome
                if outcome != nil { group.cancelAll() }
            }
            return first ?? .timedOut
        }
    }

    /// `output` read as Herdr's one JSON object: its `result` when the run
    /// worked; else its error's `code` and `message`, when it says.
    package static func answer(_ output: ShellOutput) -> Result<[String: Any], HerdrError> {
        let answer = (try? JSONSerialization.jsonObject(with: Data(output.output.utf8))) as? [String: Any]
        if output.status == 0 {
            return .success(answer?["result"] as? [String: Any] ?? [:])
        }
        let error = answer?["error"] as? [String: Any]
        return .failure(HerdrError(code: error?["code"] as? String, message: error?["message"] as? String))
    }

    /// Why Herdr refused the saved machine `label` before asking it, from
    /// the plain line (not JSON) it prints then, when it's one of these; the
    /// poll and a click both say it. As Herdr's `cli/target.rs`
    /// (`resolve_machine`, at commit 65e35a3) words them, after `error: `,
    /// with exit status 2.
    package static func refusal(_ output: String, machine label: String) -> String? {
        let line = output.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        switch line {
        case "error: unknown machine '\(label)'; use `herdr machine list`":
            return "Herdr has no saved machine named \(label)"
        case "error: machine '\(label)' is disabled":
            return "\(label) is disabled in Herdr"
        case "error: machine label '\(label)' is ambiguous; use its profile ID":
            return "Herdr has more than one machine named \(label)"
        default:
            return nil
        }
    }

    /// The error Herdr answered with; both `nil` when it didn't say.
    package struct HerdrError: Error {
        package var code: String?
        package var message: String?
    }
}
