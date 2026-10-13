import Foundation
import ShipyardCommand

/// The pings' commands for a `shipyard` build's `CommandTable`: the `ping`
/// group (`send`, `withdraw`, `list`) and `herdr-event`, filing through
/// `filing` and keeping pings in `store`, which each run reads as at its
/// own time.
public enum PingCommands {
    public static func entries(filing: any PingFiling, store: PingStore) -> [CommandTable.Entry] {
        [
            CommandTable.Entry(name: "ping", section: .messages, commands: pingCommands) { arguments, environment, now in
                ping(arguments, environment: environment, filing: filing, store: store.at(now), now: now)
            },
            CommandTable.Entry(name: "herdr-event", section: .plumbing, commands: herdrEventCommands) { arguments, environment, now in
                if arguments == ["--help"] || arguments == ["-h"] { return CommandResult(output: herdrEventUsage) }
                guard arguments.isEmpty else {
                    return .usage("shipyard herdr-event: takes no arguments; it reads HERDR_PLUGIN_EVENT and HERDR_PLUGIN_EVENT_JSON")
                }
                return HerdrEvent.run(environment: environment, filing: filing, store: store.at(now), now: now)
            },
        ]
    }

    /// The words after `ping` that name a command; anything else is the
    /// old form of `send`, a title and its flags.
    static let verbs: Set<String> = ["send", "withdraw", "list"]

    /// `shipyard ping …`: its help, `send`, `withdraw`, `list`, or the old
    /// form of `send`, which warns and sends.
    private static func ping(
        _ arguments: [String],
        environment: CommandEnvironment,
        filing: any PingFiling,
        store: PingStore,
        now: Date
    ) -> CommandResult {
        guard let verb = arguments.first else {
            return CommandResult(error: PingCommand.usageText, status: CommandResult.usageStatus)
        }
        // After `--` it's the title's, not a flag.
        let flags = arguments.prefix { $0 != "--" }
        if flags.contains("--help") || flags.contains("-h") { return CommandResult(output: PingCommand.usageText) }
        let rest = Array(arguments.dropFirst())
        switch verb {
        // Withdrawing and listing never file, so a broken config.toml doesn't stop them.
        case "withdraw": return PingCommand.withdraw(rest, store: store)
        case "list": return PingCommand.list(rest, store: store, now: now)
        case "send": return PingCommand.run(rest, environment: environment, filing: filing, store: store, now: now)
        default:
            var result = PingCommand.run(arguments, environment: environment, filing: filing, store: store, now: now)
            result.error = CommandTable.renamed("ping <title>", "ping send <title>") + result.error
            return result
        }
    }

    static let pingCommands = [
        CommandTable.Command("send <title> [options]", "send the user a ping that waits until they click it"),
        CommandTable.Command("withdraw <id>", "take a ping back"),
        CommandTable.Command("list [--json]", "list this machine's live pings"),
    ]

    static let herdrEventCommands = [
        CommandTable.Command("", "ping when a Herdr agent is blocked, and withdraw it when it goes on"),
    ]

    static let herdrEventUsage = """
        Ping when a Herdr agent is blocked, and withdraw it when it goes on or its pane closes.

        Usage: shipyard herdr-event

        Herdr's plugin hooks run it, with the event in HERDR_PLUGIN_EVENT and
        HERDR_PLUGIN_EVENT_JSON. It takes no arguments; there's nothing to run
        by hand.

        """
}
