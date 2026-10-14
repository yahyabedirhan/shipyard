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

    /// `shipyard ping …`: its help, `send`, `withdraw` or `list`.
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
        let flags = arguments.prefix { $0 != "--" }
        if flags.contains("--help") || flags.contains("-h") { return CommandResult(output: PingCommand.usageText) }
        let rest = Array(arguments.dropFirst())
        switch verb {
        case "withdraw": return PingCommand.withdraw(rest, store: store)
        case "list": return PingCommand.list(rest, store: store, now: now)
        case "send": return PingCommand.run(rest, environment: environment, filing: filing, store: store, now: now)
        default:
            return .usage("shipyard ping: unknown command `\(verb)`; send a ping with `shipyard ping send <title>`. Run `shipyard ping --help` for usage.")
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
