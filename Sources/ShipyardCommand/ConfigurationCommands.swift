import Foundation

/// `shipyard config check`: the verdict on each settings file the build
/// reads, without the app. The executable hands it checks in the order it
/// prints them: on the Mac `config.toml` (read as the app reads it), each
/// theme file in the `themes` folder beside it, and `cli.toml`; on a machine
/// without the app `cli.toml` alone, so this module never links the reader
/// of a file its build lacks.
public enum ConfigurationCommands {
    /// Reads its files at the time it's given: one, or a folder's worth.
    public typealias Check = @Sendable (_ now: Date) -> [ConfigurationCheck]

    public static func entries(checks: [Check]) -> [CommandTable.Entry] {
        [
            CommandTable.Entry(name: "config", section: .checks, commands: commands) { arguments, _, now in
                run(arguments, checks: checks, now: now)
            },
        ]
    }

    private static func run(_ arguments: [String], checks: [Check], now: Date) -> CommandResult {
        if arguments.contains("--help") || arguments.contains("-h") { return CommandResult(output: usageText) }
        guard let verb = arguments.first else { return CommandResult(error: usageText, status: CommandResult.usageStatus) }
        guard verb == "check" else {
            return .usage("shipyard config: unknown command `\(verb)`. Run `shipyard config --help` for usage.")
        }
        var json = false
        for argument in arguments.dropFirst() {
            guard argument == "--json" else {
                return .usage("shipyard config check: unknown option `\(argument)`. Run `shipyard config --help` for usage.")
            }
            json = true
        }
        let results = checks.flatMap { $0(now) }
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

    private static func text(_ check: ConfigurationCheck) -> String {
        let verdict = !check.accepted ? "rejected" : check.modified == nil ? "accepted (no file: the defaults)" : "accepted"
        let lines = ["\(check.file.path): \(verdict)"]
            + check.problems.map { "  problem: " + ConfigurationCheck.banner($0, in: check.name) }
            + check.warnings.map { "  warning: " + ConfigurationCheck.banner($0, in: check.name) }
        return lines.map { $0 + "\n" }.joined()
    }

    static let usageText = """
        Check the settings files after an edit.

        Usage: shipyard config check [--json]

        Examples:
          shipyard config check
          shipyard config check --json

        Reads each settings file this shipyard uses, config.toml as the app
        reads it and each theme file in the themes folder beside it, and
        prints whether it's accepted, with each problem and warning and its
        line.

        Options:
          --json  print each file's result by its name, in config-status.json's fields

        Exit codes: 1 when a file has a problem.

        """

    static let commands = [
        CommandTable.Command("check [--json]", "check the settings files, each problem and warning with its line"),
    ]
}
