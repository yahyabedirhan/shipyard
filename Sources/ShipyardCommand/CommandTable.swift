import Foundation

/// The commands one `shipyard` build has, by group. Each module that brings
/// commands gives its groups (`PingCommands`), and the executable adds
/// those its build links, so what a build can do is decided when it's
/// assembled, never by asking the platform at run time. The top help and
/// `shipyard help --json` are made from it, so they list what the build
/// runs and nothing else (docs/cli-design.md).
public struct CommandTable: Sendable {
    /// Where a group is listed in the top help: one heading per job.
    public enum Section: String, CaseIterable, Sendable {
        case messages
        case app
        case checks
        case plumbing

        var heading: String {
            switch self {
            case .messages: "Tell the user (any machine):"
            case .app: "Drive the app (on the Mac):"
            case .checks: "Check the setup:"
            case .plumbing: "Plumbing (run by Herdr's plugin hooks, not by hand):"
            }
        }
    }

    /// One command of a group: `shipyard <group> <verb> …`.
    public struct Command: Equatable, Sendable {
        /// What follows the group's name, the verb first: `send <title> [options]`.
        /// Empty for a group that is its own command (`herdr-event`).
        public var usage: String
        /// One line, starting with a verb, on what it achieves.
        public var summary: String

        public init(_ usage: String, _ summary: String) {
            self.usage = usage
            self.summary = summary
        }
    }

    /// One group: `shipyard <name> …`.
    public struct Entry: Sendable {
        public var name: String
        public var section: Section
        /// Its commands, in the order the help lists them.
        public var commands: [Command]
        /// Runs it with the arguments after its name, at `now`. `--help`
        /// among them prints the group's own help.
        public var run: @Sendable (_ arguments: [String], _ environment: CommandEnvironment, _ now: Date) -> CommandResult

        public init(
            name: String,
            section: Section,
            commands: [Command],
            run: @escaping @Sendable (_ arguments: [String], _ environment: CommandEnvironment, _ now: Date) -> CommandResult
        ) {
            self.name = name
            self.section = section
            self.commands = commands
            self.run = run
        }
    }

    /// The groups, in the order `shipyard --help` lists them within a section.
    public private(set) var entries: [Entry] = []

    public init() {}

    /// Adds `entry` after those already there. Two groups can't share a
    /// name: that's a mistake in how the build is assembled.
    public mutating func add(_ entry: Entry) {
        precondition(self.entry(named: entry.name) == nil, "shipyard has two commands named \(entry.name)")
        entries.append(entry)
    }

    /// Adds each of `entries`, in order.
    public mutating func add(_ entries: [Entry]) {
        entries.forEach { add($0) }
    }

    /// The group `name` names, if this build has it.
    public func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    /// The groups that control the Mac's app, which only the Mac's build
    /// links (ShipyardControl). A build without one of them refuses it with
    /// a pointer to the Mac instead of calling it unknown. Each name joins
    /// when its group exists on the Mac, so the Mac never answers "runs
    /// on the Mac" for a command it lacks. `notice` isn't one: every build
    /// has a route for it.
    public static let macOnly: Set<String> = ["app", "panel", "lease", "notes"]
}

/// The `shipyard` command line (ADR 0004), bundled in `Shipyard.app` and
/// built alone for machines without the app (ADR 0005). Its commands and
/// flags are a public contract agents depend on, like the configuration's
/// schema; docs/cli-design.md is its design. It routes over the build's
/// `CommandTable`; the executable is a thin wrapper that assembles the
/// table and prints what `run` returns.
public enum ShipyardCLI {
    /// What `shipyard --help` prints for `table`: each section's commands,
    /// one line each, from the table.
    public static func usage(_ table: CommandTable) -> String {
        var lines = [
            "shipyard: your pull requests, issues, runs and agents' pings, from the menu bar",
            "",
            "Usage: shipyard <group> <command> [options]",
        ]
        for section in CommandTable.Section.allCases {
            let rows = table.entries.filter { $0.section == section }.flatMap { entry in
                entry.commands.map { (left: words(entry.name, $0.usage), right: $0.summary) }
            }
            guard !rows.isEmpty else { continue }
            lines += ["", section.heading] + columns(rows)
        }
        lines += ["", "Options:"]
        lines += columns([
            ("-h, --help", "show help; `shipyard <group> --help` for a group's commands"),
            ("--version", "print the version"),
        ])
        lines += ["", "Environment:"]
        lines += columns([("SHIPYARD_CONTROL_KEY", "the holder key app, panel and lease commands are sent as")])
        lines += [
            "",
            "Exit codes: 0 success, 1 failed or refused, 2 wrong usage.",
            "",
            "Agents: `shipyard help --json` lists every command as JSON.",
            "Learn more: docs/cli-design.md in github.com/yahyabedirhan/shipyard.",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    private static func words(_ group: String, _ usage: String) -> String {
        usage.isEmpty ? group : group + " " + usage
    }

    private static func columns(_ rows: [(left: String, right: String)]) -> [String] {
        let width = rows.map(\.left.count).max() ?? 0
        return rows.map { "  " + $0.left.padding(toLength: width, withPad: " ", startingAt: 0) + "   " + $0.right }
    }

    /// What `shipyard help --json` prints for `table`: every command with
    /// its usage and summary.
    public static func json(_ table: CommandTable) -> String {
        struct Listing: Encodable {
            struct Command: Encodable {
                var group: String
                var usage: String
                var summary: String
                var section: String
            }
            var version: String
            var commands: [Command]
        }
        let listing = Listing(
            version: ShipyardVersion.current,
            commands: CommandTable.Section.allCases.flatMap { section in
                table.entries.filter { $0.section == section }.flatMap { entry in
                    entry.commands.map {
                        Listing.Command(group: entry.name, usage: "shipyard " + words(entry.name, $0.usage), summary: $0.summary, section: section.rawValue)
                    }
                }
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(listing)) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// Runs `arguments` (without the program's name) at `now`: `--help`,
    /// `help` and `--version` here, anything else by the group of `table`
    /// it names first, with the arguments after the name.
    public static func run(
        _ arguments: [String],
        table: CommandTable,
        environment: CommandEnvironment,
        now: Date
    ) -> CommandResult {
        guard let first = arguments.first else {
            return CommandResult(error: usage(table), status: CommandResult.usageStatus)
        }
        switch first {
        case "--help", "-h":
            return CommandResult(output: usage(table))
        case "help":
            return help(Array(arguments.dropFirst()), table: table, environment: environment, now: now)
        case "--version":
            return CommandResult(output: "shipyard \(ShipyardVersion.current)\n")
        default:
            break
        }
        guard let entry = table.entry(named: first) else {
            if CommandTable.macOnly.contains(first) {
                return .usage("shipyard: `shipyard \(first)` runs on the Mac, where the app is")
            }
            return unknown(first, table: table)
        }
        return entry.run(Array(arguments.dropFirst()), environment, now)
    }

    private static func help(_ arguments: [String], table: CommandTable, environment: CommandEnvironment, now: Date) -> CommandResult {
        switch arguments {
        case []: CommandResult(output: usage(table))
        case ["--json"]: CommandResult(output: json(table))
        case let words where words.count == 1 && !words[0].hasPrefix("-"):
            run([words[0], "--help"], table: table, environment: environment, now: now)
        default:
            .usage("shipyard help: takes one group, or --json: shipyard help [<group> | --json]")
        }
    }

    private static func unknown(_ group: String, table: CommandTable) -> CommandResult {
        let near = (table.entries.map(\.name) + ["help"])
            .map { (name: $0, distance: distance($0, group)) }
            .filter { $0.distance <= 2 }
            .min { $0.distance < $1.distance }
        let hint = near.map { " Did you mean `shipyard \($0.name)`?" } ?? ""
        return .usage("shipyard: unknown command `\(group)`.\(hint) Run `shipyard --help` for the commands.")
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var row = Array(0...b.count)
        for i in 1...a.count {
            var diagonal = row[0]
            row[0] = i
            for j in 1...b.count {
                let above = row[j]
                row[j] = min(above + 1, row[j - 1] + 1, diagonal + (a[i - 1] == b[j - 1] ? 0 : 1))
                diagonal = above
            }
        }
        return row[b.count]
    }
}
