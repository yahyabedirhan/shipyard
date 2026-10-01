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
/// environment variables (`XDG_CONFIG_HOME`, `HERDR_PANE_ID`) and
/// git, which says the working folder's remote `origin`.
public struct CommandEnvironment: Sendable {
    public var workingDirectory: URL
    public var variables: [String: String]
    public var git: any GitRemoteLookup

    public init(workingDirectory: URL, variables: [String: String], git: any GitRemoteLookup = GitCLI()) {
        self.workingDirectory = workingDirectory
        self.variables = variables
        self.git = git
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
                  shipyard ping "<title>" [--body <text>] [--from <label>]
                                [--open <url> | --app <bundle id or name> | --herdr [<tab or pane id>]]
                                [--repo <owner/name> | --project <name>]

        options:
          --help     show this help (shipyard ping --help for the command's)
          --version  show shipyard's version

        """

    /// Runs `arguments` (without the program's name): reads the
    /// configuration at `configURL` (a missing file is no projects; one that
    /// doesn't read fails the command) and the repositories the app last
    /// resolved from `repositories` (none, when it hasn't yet), and runs the
    /// command named first.
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
            if rest.contains("--help") || rest.contains("-h") { return CommandResult(output: PingCommand.usageText) }
            let configuration: Configuration
            switch readConfiguration(at: configURL) {
            case .success(let read): configuration = read
            case .failure(let failure): return failure
            }
            return PingCommand.run(
                rest,
                environment: environment,
                configuration: configuration,
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
