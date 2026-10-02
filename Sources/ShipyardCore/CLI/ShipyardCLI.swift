import Foundation

/// What a command run prints and how it exits: the `shipyard` executable
/// writes `output` to standard output and `error` to standard error, then
/// exits with `status`.
public struct CommandResult: Equatable, Sendable {
    public var output: String
    public var error: String
    /// 0 when it worked; `CommandResult.failed` (1) when it was refused,
    /// such as a ping for a project that doesn't exist; `usage` (2) when
    /// the arguments don't read.
    public var status: Int32

    public init(output: String = "", error: String = "", status: Int32 = 0) {
        self.output = output
        self.error = error
        self.status = status
    }

    public static let failedStatus: Int32 = 1
    public static let usageStatus: Int32 = 2

    /// Refused: one line on standard error, exit 1.
    static func failed(_ message: String) -> CommandResult {
        CommandResult(error: message + "\n", status: failedStatus)
    }

    /// The arguments don't read: one line on standard error, exit 2.
    static func usage(_ message: String) -> CommandResult {
        CommandResult(error: message + "\n", status: usageStatus)
    }
}

/// What a command reads from where it runs: the working folder, the
/// environment variables (`XDG_CONFIG_HOME`, `HERDR_PANE_ID`, the
/// `HERDR_PLUGIN_EVENT`s), git, which says a folder's remote `origin`, the
/// platform, and how it runs a program (`herdr`) and tells whether one can
/// be run.
public struct CommandEnvironment: Sendable {
    public var workingDirectory: URL
    public var variables: [String: String]
    public var git: any GitRemoteLookup
    public var platform: CommandPlatform
    public var run: GhCLI.Run
    public var isExecutable: @Sendable (String) -> Bool

    public init(
        workingDirectory: URL,
        variables: [String: String],
        git: any GitRemoteLookup = GitCLI(),
        platform: CommandPlatform,
        run: @escaping GhCLI.Run = GhCLI.runProcess,
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) {
        self.workingDirectory = workingDirectory
        self.variables = variables
        self.git = git
        self.platform = platform
        self.run = run
        self.isExecutable = isExecutable
    }
}

/// The platform the `shipyard` command runs on, which decides what a ping
/// is there. On macOS the app is beside it: a ping is filed against
/// `config.toml` and stays until seen. Linux is a machine without the app,
/// whose pings the Mac reads through Herdr: a ping is saved as the agent
/// gave it (the Mac files it), records the Herdr pane it was sent from, and
/// expires a day after its sending or its last replace.
public enum CommandPlatform: Sendable, Equatable {
    case macOS
    case linux

    /// The platform this build runs on; anything but macOS is a machine
    /// without the app.
    public static var current: CommandPlatform {
        #if os(macOS)
        .macOS
        #else
        .linux
        #endif
    }
}

/// The `shipyard` command line (ADR 0004), bundled in `Shipyard.app`. Its
/// commands and flags are a public contract agents depend on, like the
/// configuration's schema. `ping` is its one command so far; the
/// executable is a thin wrapper over `run`.
public enum ShipyardCLI {
    /// What `shipyard --help` prints.
    public static let usageText = """
        usage: shipyard <command> [options]

        commands:
          ping    send the user a ping, filed by the working folder's repository:
                  shipyard ping "<title>" [--body <text>] [--from <label>] [--id <id>]
                                [--open <url> | --app <bundle id or name> | --herdr [<tab or pane id>]]
                                [--repo <owner/name> | --project <name>]
                  shipyard ping withdraw <id>
                  shipyard ping list --json
          herdr-event
                  what Herdr's plugin hooks run: pings when an agent is blocked,
                  and withdraws that ping when it goes on or its pane closes

        options:
          --help     show this help (shipyard ping --help for the command's)
          --version  show shipyard's version

        """

    /// Runs `arguments` (without the program's name): reads the
    /// configuration at `configURL` (a missing file is no projects; one that
    /// doesn't read fails the command) and the repositories the app last
    /// resolved from `repositories` (none, when it hasn't yet), and runs the
    /// command named first. On Linux a ping reads neither: there's no app
    /// to file it for, so it's saved as given. There, the pings that have
    /// expired by `now` are removed before `ping` and `herdr-event` run.
    public static func run(
        _ arguments: [String],
        environment: CommandEnvironment,
        configURL: URL,
        repositories: ResolvedRepositoriesStore,
        pingStore: PingStore,
        now: Date
    ) -> CommandResult {
        guard let command = arguments.first else {
            return CommandResult(error: usageText, status: CommandResult.usageStatus)
        }
        switch command {
        case "--help", "-h", "help":
            return CommandResult(output: usageText)
        case "--version":
            return CommandResult(output: "shipyard \(ShipyardVersion.current)\n")
        case "ping":
            let rest = Array(arguments.dropFirst())
            // After `--` it's the title's, not a flag.
            let flags = rest.prefix { $0 != "--" }
            if flags.contains("--help") || flags.contains("-h") { return CommandResult(output: PingCommand.usageText) }
            // An expired ping is gone: it isn't listed, can't be withdrawn,
            // and its id sent again is a new ping.
            if environment.platform == .linux { pingStore.removeExpired(at: now) }
            // Withdrawing and listing need no projects, so a broken config.toml doesn't stop them.
            if rest.first == "withdraw" { return PingCommand.withdraw(Array(rest.dropFirst()), store: pingStore) }
            if rest.first == "list" { return PingCommand.list(Array(rest.dropFirst()), store: pingStore, now: now) }
            var configuration = Configuration()
            if environment.platform == .macOS {
                switch readConfiguration(at: configURL) {
                case .success(let read): configuration = read
                case .failure(let failure): return failure
                }
            }
            return PingCommand.run(
                rest,
                environment: environment,
                configuration: configuration,
                resolved: repositories.load(),
                store: pingStore,
                now: now
            )
        case "herdr-event":
            guard arguments.count == 1 else {
                return .usage("shipyard herdr-event: takes no arguments; it reads HERDR_PLUGIN_EVENT and HERDR_PLUGIN_EVENT_JSON")
            }
            if environment.platform == .linux { pingStore.removeExpired(at: now) }
            // Withdrawing needs no projects, so only a blocked agent's ping
            // reads config.toml, and only on macOS.
            return HerdrEvent.run(
                environment: environment,
                configuration: { environment.platform == .macOS ? readConfiguration(at: configURL) : .success(Configuration()) },
                resolved: repositories.load(),
                store: pingStore,
                now: now
            )
        default:
            return CommandResult(error: "shipyard: unknown command `\(command)`\n" + usageText, status: CommandResult.usageStatus)
        }
    }

    /// The configuration file as the app reads it, or why it can't be used:
    /// the app falls back on the last file that read, but the CLI has none,
    /// so it says what to fix.
    private static func readConfiguration(at url: URL) -> Result<Configuration, CommandResult> {
        guard let data = try? Data(contentsOf: url) else { return .success(Configuration()) }
        do {
            return .success(try Configuration.decode(data).configuration)
        } catch {
            return .failure(.failed("shipyard: config.toml doesn't read (\(error.issues[0])); fix it, then try again"))
        }
    }
}

/// So a step that can't go on can hand back the result to print.
extension CommandResult: Error {}
