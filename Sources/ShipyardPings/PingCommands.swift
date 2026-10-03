import Foundation
import ShipyardCommand

/// The pings' commands for a `shipyard` build's `CommandTable`: `ping`
/// and `herdr-event`, filing through `filing` and keeping pings in
/// `store`, which each run reads as at its own time.
public enum PingCommands {
    public static func entries(filing: any PingFiling, store: PingStore) -> [CommandTable.Entry] {
        [
            CommandTable.Entry(name: "ping", help: pingHelp) { arguments, environment, now in
                ping(arguments, environment: environment, filing: filing, store: store.at(now), now: now)
            },
            CommandTable.Entry(name: "herdr-event", help: herdrEventHelp) { arguments, environment, now in
                guard arguments.isEmpty else {
                    return .usage("shipyard herdr-event: takes no arguments; it reads HERDR_PLUGIN_EVENT and HERDR_PLUGIN_EVENT_JSON")
                }
                return HerdrEvent.run(environment: environment, filing: filing, store: store.at(now), now: now)
            },
        ]
    }

    /// `shipyard ping …`: its help, `withdraw`, `list`, or a ping to send.
    private static func ping(
        _ arguments: [String],
        environment: CommandEnvironment,
        filing: any PingFiling,
        store: PingStore,
        now: Date
    ) -> CommandResult {
        // After `--` it's the title's, not a flag.
        let flags = arguments.prefix { $0 != "--" }
        if flags.contains("--help") || flags.contains("-h") { return CommandResult(output: PingCommand.usageText) }
        // Withdrawing and listing never file, so a broken config.toml doesn't stop them.
        if arguments.first == "withdraw" { return PingCommand.withdraw(Array(arguments.dropFirst()), store: store) }
        if arguments.first == "list" { return PingCommand.list(Array(arguments.dropFirst()), store: store, now: now) }
        return PingCommand.run(arguments, environment: environment, filing: filing, store: store, now: now)
    }

    static let pingHelp = """
          ping    send the user a ping, filed by the working folder's repository:
                  shipyard ping "<title>" [--body <text>] [--from <label>] [--id <id>]
                                [--open <url> | --app <bundle id or name> | --herdr [<tab or pane id>]]
                                [--repo <owner/name> | --project <name>]
                  shipyard ping withdraw <id>
                  shipyard ping list --json

        """

    static let herdrEventHelp = """
          herdr-event
                  what Herdr's plugin hooks run: pings when an agent is blocked,
                  and withdraws that ping when it goes on or its pane closes

        """
}
