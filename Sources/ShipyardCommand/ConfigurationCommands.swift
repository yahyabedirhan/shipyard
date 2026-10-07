import Foundation

/// `shipyard config check`: the verdict on each settings file the build
/// reads, without the app. The executable hands it one check per file, in
/// the order it prints them: on the Mac `config.toml` (read as the app
/// reads it) and `cli.toml`, on a machine without the app `cli.toml` alone,
/// so this module never links the reader of a file its build lacks.
public enum ConfigurationCommands {
    /// Reads one file at the time it's given.
    public typealias Check = @Sendable (_ now: Date) -> ConfigurationCheck

    public static func entries(checks: [Check]) -> [CommandTable.Entry] {
        [
            CommandTable.Entry(name: "config", help: help) { arguments, _, now in
                run(arguments, checks: checks, now: now)
            },
        ]
    }

    private static func run(_ arguments: [String], checks: [Check], now: Date) -> CommandResult {
        if arguments.contains("--help") || arguments.contains("-h") { return CommandResult(output: usageText) }
        guard arguments.first == "check" else {
            return .usage("shipyard config: expected `check`\n" + usageText)
        }
        var json = false
        for argument in arguments.dropFirst() {
            guard argument == "--json" else {
                return .usage("shipyard config check: unknown argument `\(argument)`\n" + usageText)
            }
            json = true
        }
        let results = checks.map { $0(now) }
        let status = results.allSatisfy(\.accepted) ? 0 : CommandResult.failedStatus
        guard json else {
            return CommandResult(output: results.map(text).joined(), status: status)
        }
        do {
            let byName = Dictionary(results.map { ($0.name, $0) }) { first, _ in first }
            let data = try ConfigurationCheck.json(byName)
            return CommandResult(output: String(decoding: data, as: UTF8.self), status: status)
        } catch {
            return .failed("shipyard config check: can't write the JSON: \(error.localizedDescription)")
        }
    }

    /// One file's lines: its path and verdict, then each problem or warning
    /// as the panel's banner words it.
    private static func text(_ check: ConfigurationCheck) -> String {
        let verdict = !check.accepted ? "rejected" : check.modified == nil ? "accepted (no file: the defaults)" : "accepted"
        let lines = ["\(check.file.path): \(verdict)"]
            + check.problems.map { "  problem: " + ConfigurationCheck.banner($0, in: check.name) }
            + check.warnings.map { "  warning: " + ConfigurationCheck.banner($0, in: check.name) }
        return lines.map { $0 + "\n" }.joined()
    }

    static let usageText = """
        usage: shipyard config check [--json]

        Reads each settings file this shipyard uses, config.toml as the app
        reads it, and prints whether it's accepted, with each problem and
        warning and its line. Exits 1 when a file has a problem.

          --json  print each file's result by its name, in config-status.json's fields

        """

    static let help = """
          config  check the settings files after an edit, each problem and warning with its line:
                  shipyard config check [--json]

        """
}
