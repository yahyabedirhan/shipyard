import Foundation
import ShipyardCommand

/// The notices' commands for a `shipyard` build's `CommandTable`:
/// `notify`, handing each notice to the app over `route`.
public enum NoticeCommands {
    public static func entries(route: any NoticeRoute) -> [CommandTable.Entry] {
        [
            CommandTable.Entry(name: "notify", help: notifyHelp) { arguments, environment, _ in
                NotifyCommand.run(arguments, environment: environment, route: route)
            },
        ]
    }

    static let notifyHelp = """
          notify  show the user a notice, a status message that isn't kept:
                  shipyard notify "<title>" [--body <text>] [--from <label>]
                                  [--repo <owner/name> | --project <name>]

        """
}

/// `shipyard notify`: reads its arguments into a `Notice`, filed by the
/// one project `--project` names or by its repository (`--repo`, else the
/// working folder's `origin`), hands it to the app over a `NoticeRoute`
/// and says what came of it. Exit 0: shown; 1: refused, with why (notices
/// off for the project, no project takes it, the app not running); 2: the
/// arguments don't read. Nothing is stored.
public enum NotifyCommand {
    /// What `shipyard notify --help` prints.
    public static let usageText = """
        usage: shipyard notify "<title>" [--body <text>] [--from <label>]
                               [--repo <owner/name> | --project <name>]

        Shows the user a notice: a macOS notification titled with the project
        and the title, for a status update such as "tests running" or "done".
        Unlike a ping it isn't listed, counted or kept. It's filed under the
        projects that watch the working folder's repository (its git remote
        `origin`), and shown when the user's notification rules select
        `agent.notice` for one of them. It prints `shown` once the app showed it.

          --body <text>        say more than the title fits
          --from <label>       who sent it: the agent or the task
          --repo <owner/name>  file it by this repository instead of the working folder's
          --project <name>     file it under this project (its name in config.toml) only

        Everything after -- is the title, even a word starting with --.

        Exits 1, with one line saying why, when it isn't shown: notices are off
        for its projects, no project takes it, or shipyard isn't running (it's
        never started for a notice). Exits 2 when the arguments don't read.

        """

    /// The usage line errors point at.
    static let usageLine = "shipyard notify \"<title>\" [options] (shipyard notify --help lists them)"

    /// How a run's errors start.
    static let prefix = "shipyard notify: "

    /// Runs `shipyard notify` with `arguments` (those after `notify`) in
    /// `environment`, delivering over `route`.
    public static func run(_ arguments: [String], environment: CommandEnvironment, route: any NoticeRoute) -> CommandResult {
        let flags = arguments.prefix { $0 != "--" }
        if flags.contains("--help") || flags.contains("-h") { return CommandResult(output: usageText) }
        var notice: Notice
        switch parse(arguments) {
        case .success(let parsed): notice = parsed
        case .failure(let error): return .usage(prefix + error.message)
        }
        if notice.project == nil, notice.repository == nil {
            switch GitRemote.workingRepository(folder: environment.workingDirectory, git: environment.git, filing: "notice") {
            case .success(let slug): notice.repository = slug
            case .failure(let why): return .failed(prefix + why.message + "; pass --repo <owner/name> or --project <name>")
            }
        }
        switch route.deliver(notice, environment: environment) {
        case .shown: return CommandResult(output: "shown\n")
        case .refused(let why): return .failed(prefix + why)
        }
    }

    /// Why the arguments don't read, as the error line says it.
    struct ParseError: Error, Equatable {
        var message: String
        init(_ message: String) { self.message = message }
    }

    /// Reads `arguments`: one title; `--body` and `--from`; `--repo
    /// <owner/name>` or `--project <name>`; in any order. Everything after
    /// `--` is the title. An empty `--body` or `--from` is none. The
    /// notice's repository is left for `run` to find when neither flag
    /// names where it goes.
    static func parse(_ arguments: [String]) -> Result<Notice, ParseError> {
        var titles: [String] = []
        var notice = Notice(title: "")
        var index = 0
        var flagsEnded = false
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if argument == "--", !flagsEnded {
                flagsEnded = true
                continue
            }
            guard argument.hasPrefix("--"), !flagsEnded else {
                titles.append(argument)
                continue
            }
            guard ["--body", "--from", "--project", "--repo"].contains(argument) else {
                return .failure(ParseError("unknown option `\(argument)`"))
            }
            guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
            let value = arguments[index].trimmingCharacters(in: .whitespacesAndNewlines)
            index += 1
            switch argument {
            case "--body": notice.body = value.isEmpty ? nil : value
            case "--from": notice.sender = value.isEmpty ? nil : value
            case "--project":
                guard !value.isEmpty else { return .failure(ParseError("`--project` takes a project's name")) }
                notice.project = value
            default:
                guard GitRemote.isRepositorySlug(value) else {
                    return .failure(ParseError("`--repo` takes a repository as owner/name, not `\(value)`"))
                }
                notice.repository = value
            }
        }
        if titles.count > 1 {
            return .failure(ParseError("one title only; quote it: shipyard notify \"\(titles.joined(separator: " "))\""))
        }
        notice.title = titles.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !notice.title.isEmpty else { return .failure(ParseError("give the notice a title: \(usageLine)")) }
        if notice.project != nil, notice.repository != nil {
            return .failure(ParseError("pass --repo or --project, not both"))
        }
        return .success(notice)
    }
}
