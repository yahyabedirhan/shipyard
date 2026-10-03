import Foundation

/// The commands one `shipyard` build has, by name. Each module that brings
/// commands gives its entries (`PingCommands`), and the executable adds
/// those its build links, so what a build can do is decided when it's
/// assembled, never by asking the platform at run time.
public struct CommandTable: Sendable {
    /// One command: `shipyard <name> …`.
    public struct Entry: Sendable {
        public var name: String
        /// Its lines under `commands:` in `shipyard --help`, each indented
        /// two spaces and ending in a newline.
        public var help: String
        /// Runs it with the arguments after its name, at `now`.
        public var run: @Sendable (_ arguments: [String], _ environment: CommandEnvironment, _ now: Date) -> CommandResult

        public init(
            name: String,
            help: String,
            run: @escaping @Sendable (_ arguments: [String], _ environment: CommandEnvironment, _ now: Date) -> CommandResult
        ) {
            self.name = name
            self.help = help
            self.run = run
        }
    }

    /// The commands, in the order `shipyard --help` lists them.
    public private(set) var entries: [Entry] = []

    public init() {}

    /// Adds `entry` after those already there. Two commands can't share a
    /// name: that's a mistake in how the build is assembled.
    public mutating func add(_ entry: Entry) {
        precondition(self.entry(named: entry.name) == nil, "shipyard has two commands named \(entry.name)")
        entries.append(entry)
    }

    /// Adds each of `entries`, in order.
    public mutating func add(_ entries: [Entry]) {
        entries.forEach { add($0) }
    }

    /// The command `name` names, if this build has it.
    public func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    /// The commands that control the Mac's app, which only the Mac's build
    /// links (ShipyardControl). A build without one of them refuses it with
    /// a pointer to the Mac instead of calling it unknown. Each name joins
    /// when its command exists on the Mac, so the Mac never answers "runs
    /// on the Mac" for a command it lacks.
    public static let macOnly: Set<String> = ["app"]
}

/// The `shipyard` command line (ADR 0004), bundled in `Shipyard.app` and
/// built alone for machines without the app (ADR 0005). Its commands and
/// flags are a public contract agents depend on, like the configuration's
/// schema. It routes over the build's `CommandTable`; the executable is a
/// thin wrapper that assembles the table and prints what `run` returns.
public enum ShipyardCLI {
    /// What `shipyard --help` prints for `table`.
    public static func usage(_ table: CommandTable) -> String {
        """
        usage: shipyard <command> [options]

        commands:
        \(table.entries.map(\.help).joined())
        options:
          --help     show this help (shipyard ping --help for the command's)
          --version  show shipyard's version

        """
    }

    /// Runs `arguments` (without the program's name) at `now`: `--help`
    /// and `--version` here, anything else by the command of `table` it
    /// names first, with the arguments after the name.
    public static func run(
        _ arguments: [String],
        table: CommandTable,
        environment: CommandEnvironment,
        now: Date
    ) -> CommandResult {
        guard let command = arguments.first else {
            return CommandResult(error: usage(table), status: CommandResult.usageStatus)
        }
        switch command {
        case "--help", "-h", "help":
            return CommandResult(output: usage(table))
        case "--version":
            return CommandResult(output: "shipyard \(ShipyardVersion.current)\n")
        default:
            guard let entry = table.entry(named: command) else {
                if CommandTable.macOnly.contains(command) {
                    return .usage("shipyard: `shipyard \(command)` runs on the Mac, where the app is")
                }
                return CommandResult(error: "shipyard: unknown command `\(command)`\n" + usage(table), status: CommandResult.usageStatus)
            }
            return entry.run(Array(arguments.dropFirst()), environment, now)
        }
    }
}
