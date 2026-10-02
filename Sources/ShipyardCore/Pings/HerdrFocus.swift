import Foundation

/// Runs a ping's Herdr action (`--herdr`): focuses the tab or pane it
/// names through the `herdr` command (`HerdrCommand`), so `Shipyard` can
/// then bring `[herdr] terminal` forward. Herdr has no command that
/// focuses a pane by its id, so a pane's tab is looked up (`herdr pane
/// get`) and focused (`herdr tab focus`); a tab is focused at once.
public struct HerdrFocus: Sendable {
    /// Where `herdr` is looked for before `PATH`, under the home folder `home`.
    public static func knownPaths(home: URL) -> [String] {
        HerdrCommand.knownPaths(home: home)
    }

    private let herdr: HerdrCommand

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
        herdr = HerdrCommand(
            home: home,
            pathEnvironment: pathEnvironment,
            isExecutable: isExecutable,
            runner: runner,
            timeout: timeout,
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

    /// The first `herdr` found under the home folder `home`: the known
    /// paths, then each directory of `pathEnvironment`.
    static func locate(home: URL, pathEnvironment: String?, isExecutable: (String) -> Bool) -> String? {
        HerdrCommand.locate(home: home, pathEnvironment: pathEnvironment, isExecutable: isExecutable)
    }

    /// Focuses the tab `id` names, or the tab of the pane it names, and
    /// says how it went: `failed` when `herdr` isn't found or won't run,
    /// when Herdr isn't running or doesn't answer within `timeout`, and
    /// when the tab or pane is gone.
    public func focus(_ id: String) async -> ActionOutcome {
        var tab = id
        if !Self.isTab(id) {
            switch await run(["pane", "get", id], about: id) {
            case .failure(let reason): return .failed(reason.message)
            case .success(let answer):
                guard let found = (answer["pane"] as? [String: Any])?["tab_id"] as? String else {
                    return .failed("Herdr didn't say which tab pane \(id) is in")
                }
                tab = found
            }
        }
        switch await run(["tab", "focus", tab], about: tab) {
        case .failure(let reason): return .failed(reason.message)
        case .success: return .done
        }
    }

    /// Why a `herdr` command failed, as the ping's row says it.
    struct Failure: Error {
        var message: String
    }

    /// Runs `herdr` with `arguments` and reads its answer, one JSON object:
    /// its `result` when it worked, else why not, for the tab or pane `id`.
    private func run(_ arguments: [String], about id: String) async -> Result<[String: Any], Failure> {
        switch await herdr.run(arguments) {
        case .notFound: return .failure(Failure(message: "Couldn't find herdr"))
        case .couldNotRun: return .failure(Failure(message: "Couldn't run herdr"))
        case .timedOut: return .failure(Failure(message: "Herdr didn't answer"))
        case .finished(let output):
            return HerdrCommand.answer(output).mapError { error in
                switch error.code {
                case "pane_not_found": Failure(message: "Herdr pane \(id) is gone")
                case "tab_not_found": Failure(message: "Herdr tab \(id) is gone")
                case "server_not_running": Failure(message: "Herdr isn't running")
                default: Failure(message: "Herdr couldn't focus \(id)")
                }
            }
        }
    }
}
