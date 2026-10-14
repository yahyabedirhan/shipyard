import Foundation
import ShipyardCommand

/// `shipyard ping`: reads its arguments, files the ping under the projects
/// that watch its repository (or under the one `--project` names), saves it
/// to the ping store and prints its id (`k7qm2x`). Pure apart from the store and the
/// git remote it reads through `CommandEnvironment`, so tests call it as a
/// function; the `shipyard` executable only prints what it returns.
///
/// Its arguments are read as a subcommand first (`withdraw`), then as a
/// title and flags, in any order; `--` ends the flags.
public enum PingCommand {
    /// What `shipyard ping --help` prints.
    public static let usageText = """
        Send the user pings: messages that wait until they click them.

        Usage: shipyard ping send <title> [options]
               shipyard ping withdraw <id>
               shipyard ping list [--json]

        Examples:
          shipyard ping send "PR ready for review" --open https://github.com/o/r/pull/7
          shipyard ping send "Which option?" --from claude --id ask-1 --herdr
          shipyard ping withdraw ask-1

        send <title> [options]
          Sends the user a ping and prints its id, such as `k7qm2x`. It's
          listed under the projects that watch the repository of the working
          folder (its git remote `origin`), and needs their attention until
          they click it. Clicking it runs its action, if it has one, and marks
          it seen. The Mac's shipyard numbers it in each project it's listed in.

          --body <text>        say more than the title fits
          --from <label>       who sent it: the agent or the task
          --id <id>            name it, to replace or withdraw it later; sending
                               an id again replaces that ping (new title, body,
                               action and projects, unseen again, no second
                               notification); without --id one is made up
          --open <url>         clicking it opens this URL (a page, an app's deep link)
          --app <id or name>   clicking it brings this app forward, by bundle id or name
          --herdr [<id>]       clicking it focuses this Herdr tab or pane (an id such as
                               w1:t2 or w1:p3); with no id, your own pane ($HERDR_PANE_ID).
                               It notes the terminal app you ran it in, and clicking brings
                               that app forward unless [herdr] terminal names one
          --repo <owner/name>  file it by this repository instead of the working folder's
          --project <name>     file it under this project only: its slug in config.toml,
                               or else its title

          One action at most; with none, clicking it only marks it seen. The
          argument after --herdr is its id only when it's shaped like one
          (workspace:tab or workspace:pane, as Herdr prints them). An id is 1 to
          64 lowercase letters, digits, - and _, starting with a letter or digit.
          Everything after -- is the title, even a word starting with --.

        withdraw <id>
          Takes the ping back: it leaves the menu, and its notification leaves
          Notification Center. Prints the id; exits 1 when no ping has it.

        list [--json]
          Lists this machine's live pings, newest first: id, age, title and
          where it's filed. --json prints them as one line of JSON, the shape
          the Mac's shipyard reads through Herdr.

        On Linux, a computer without the app, a ping isn't filed there: it
        keeps its repository (or --project) as given, and the Mac files it.
        Sent from a Herdr pane without an action, clicking it focuses that
        pane. It leaves a day after its sending or its last replace.

        Exit codes: 1 when no project takes the ping, or no ping has the id.

        """

    static let usageLine = "shipyard ping send <title> [options] (shipyard ping --help lists them)"

    static let actionFlags = ["--open", "--app", "--herdr"]

    /// The environment variable Herdr sets in each of its panes to that
    /// pane's id, which `--herdr` without an id takes.
    public static let herdrPaneVariable = "HERDR_PANE_ID"

    static let herdrSessionVariable = "HERDR_SESSION"

    /// The named Herdr session the CLI runs in, which a `--herdr` ping is
    /// focused in on a click: `HERDR_SESSION`, when it names one. `nil` in
    /// Herdr's default session (where it's unset, or `default`) and outside
    /// Herdr.
    public static func herdrSession(_ variables: [String: String]) -> String? {
        let name = variables[herdrSessionVariable]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty || name == "default" ? nil : name
    }

    /// The bundle id of the terminal app the CLI runs in, which a `--herdr`
    /// ping brings forward on a click when `[herdr] terminal` is unset.
    /// `TERM_PROGRAM` names it when it's a known terminal's; Herdr sets its
    /// own (`herdr`) in its panes, so then `__CFBundleIdentifier`, the app
    /// macOS launched the process tree from, does, and last the variables a
    /// terminal sets for itself. `nil` when none says.
    public static func outerTerminal(_ variables: [String: String]) -> String? {
        let known = [
            "ghostty": "com.mitchellh.ghostty",
            "iTerm.app": "com.googlecode.iterm2",
            "Apple_Terminal": "com.apple.Terminal",
            "WezTerm": "com.github.wez.wezterm",
            "vscode": "com.microsoft.VSCode",
            "WarpTerminal": "dev.warp.Warp-Stable",
        ]
        func value(_ name: String) -> String? {
            let text = variables[name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return text.isEmpty ? nil : text
        }
        if let program = value("TERM_PROGRAM"), let bundle = known[program] { return bundle }
        if let bundle = value("__CFBundleIdentifier") { return bundle }
        if value("KITTY_WINDOW_ID") != nil || value("TERM") == "xterm-kitty" { return "net.kovidgoyal.kitty" }
        if value("ALACRITTY_WINDOW_ID") != nil { return "org.alacritty" }
        return nil
    }

    /// How long a ping lives on a machine without the app (`Unfiled`), from
    /// its sending or its last replace: no one marks it seen there, so an
    /// unanswered one would otherwise stay forever.
    public static let lifetimeWithoutTheApp: TimeInterval = 24 * 60 * 60

    /// Sends a ping with `arguments` (those after `ping`), sent at `now`,
    /// filed through `filing`: on the Mac under every project that watches
    /// its repository (or the one `--project` names), refused when none
    /// does; on a machine without the app as the agent sent it. A ping
    /// without an action takes the filing's default one (`Unfiled`: the
    /// agent's Herdr pane). `newID` makes the id when `--id` gives none;
    /// one already stored is drawn again. A `--id` already stored replaces
    /// that ping: its sent time starts again at `now`, its instance stays,
    /// and it's unseen again with no failure.
    public static func run(
        _ arguments: [String],
        environment: CommandEnvironment,
        filing: any PingFiling,
        store: PingStore,
        now: Date,
        newID: () -> String = Ping.newID
    ) -> CommandResult {
        let request: Request
        switch Request.parse(arguments, herdrPane: environment.variables[herdrPaneVariable]) {
        case .success(let parsed): request = parsed
        case .failure(let error): return .usage("shipyard ping send: \(error.message)")
        }
        var sending = request
        if sending.action == nil { sending.action = filing.defaultAction(environment) }
        var terminal: String?, session: String?
        if case .herdr = sending.action {
            terminal = outerTerminal(environment.variables)
            session = herdrSession(environment.variables)
        }
        return send(
            sending,
            terminal: terminal,
            herdrSession: session,
            folder: environment.workingDirectory,
            git: environment.git,
            filing: filing,
            store: store,
            now: now,
            newID: newID
        )
    }

    static func send(
        _ request: Request,
        terminal: String? = nil,
        herdrSession: String? = nil,
        folder: URL?,
        git: any GitRemoteLookup,
        filing: any PingFiling,
        store: PingStore,
        now: Date,
        newID: () -> String = Ping.newID,
        whenNoProject: NoProject = .refuse
    ) -> CommandResult {
        let filed: Filing
        switch filing.file(target(of: request, folder: folder, git: git), whenNoProject: whenNoProject) {
        case .success(let result): filed = result
        case .failure(let refused): return refused
        }
        let id: String
        if let named = request.id {
            id = named
        } else {
            var drawn = newID()
            while store.ping(id: drawn) != nil { drawn = newID() }
            id = drawn
        }
        let replaced = store.ping(id: id)
        do {
            try store.save(Ping(
                id: id,
                title: request.title,
                projects: filed.projects,
                sent: now,
                repository: filed.repository,
                body: request.body,
                sender: request.sender,
                action: request.action,
                terminal: terminal,
                herdrSession: herdrSession,
                instance: replaced?.instance ?? UUID().uuidString.lowercased(),
                expires: filing.expiry(sentAt: now)
            ))
        } catch {
            return .failed("shipyard ping send: couldn't save the ping in \(store.directory.path) (\(error.localizedDescription))")
        }
        return CommandResult(output: "\(id)\n")
    }

    private static func target(of request: Request, folder: URL?, git: any GitRemoteLookup) -> FilingTarget {
        if let project = request.project { return .project(project) }
        if let repository = request.repository { return .repository(repository) }
        guard let folder else { return .none(why: "the ping names no repository") }
        switch GitRemote.workingRepository(folder: folder, git: git, filing: "ping") {
        case .success(let slug): return .repository(slug)
        case .failure(let reason): return .none(why: reason.message)
        }
    }

    /// `shipyard ping list [--json]`, with `arguments` those after `list`:
    /// the store's live pings at `now`, newest first. Plain, one line each
    /// for a person; with `--json`, the remote ping list (`PingList`),
    /// capped, on one line: the contract the Mac reads through Herdr.
    public static func list(_ arguments: [String], store: PingStore, now: Date) -> CommandResult {
        let live = store.all().filter { $0.isLive(at: now) }
        switch arguments {
        case ["--json"]:
            return CommandResult(output: PingList.encode(live) + "\n")
        case []:
            let rows = live.sorted { ($0.sent, $0.id) > ($1.sent, $1.id) }.map { ping in
                let place = ping.projects.isEmpty ? ping.repository ?? "unfiled" : ping.projects.joined(separator: ", ")
                return [ping.id, age(of: ping.sent, at: now), ping.title, "(\(place))"].joined(separator: "  ")
            }
            return CommandResult(output: rows.isEmpty ? "no pings\n" : rows.joined(separator: "\n") + "\n")
        default:
            return .usage("shipyard ping list: unexpected `\(arguments[0])`. Usage: shipyard ping list [--json]")
        }
    }

    static func age(of date: Date, at now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        switch seconds {
        case ..<60: return "\(seconds)s"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86400)d"
        }
    }

    /// `shipyard ping withdraw <id>`, with `arguments` those after
    /// `withdraw`: removes the ping `id` names from the store and prints
    /// the id. The app, watching the store, takes it out of the menu and
    /// its notification out of Notification Center. An id no ping has is
    /// refused (exit 1), so a typo shows.
    public static func withdraw(_ arguments: [String], store: PingStore) -> CommandResult {
        guard arguments.count == 1, let id = arguments.first else {
            return .usage("shipyard ping withdraw: give the id of one ping: shipyard ping withdraw <id>")
        }
        guard isID(id) else { return .usage("shipyard ping withdraw: \(idRule(id))") }
        guard store.ping(id: id) != nil else {
            return .failed("shipyard ping withdraw: no ping has the id `\(id)`; it may have been withdrawn, dismissed or have left already")
        }
        do {
            try store.remove(id: id)
        } catch {
            return .failed("shipyard ping withdraw: couldn't remove the ping from \(store.directory.path) (\(error.localizedDescription))")
        }
        return CommandResult(output: id + "\n")
    }

    /// Whether `id` can name a ping: 1 to 64 lowercase letters, digits,
    /// `-` and `_`, starting with a letter or digit. Generated ids are such
    /// ids too. One rule for every id keeps it a safe file name and a URL
    /// path, the same on case-insensitive disks.
    public static func isID(_ id: String) -> Bool {
        id.range(of: #"\A[a-z0-9][a-z0-9_-]{0,63}\z"#, options: .regularExpression) != nil
    }

    /// What's wrong with an id that isn't one, for the error line.
    public static func idRule(_ id: String) -> String {
        "an id is 1 to 64 lowercase letters, digits, - and _, starting with a letter or digit, not `\(id)`"
    }

    struct Request: Equatable {
        var title: String
        var project: String?
        var repository: String?
        var body: String?
        var sender: String?
        var action: PingAction?
        var id: String?

        static func parse(_ arguments: [String], herdrPane: String? = nil) -> Result<Request, ParseError> {
            var titles: [String] = []
            var project: String?
            var repository: String?
            var body: String?
            var sender: String?
            var actions: [PingAction] = []
            var id: String?
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
                switch argument {
                case "--project":
                    guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
                    project = arguments[index]
                    index += 1
                case "--repo":
                    guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
                    let value = arguments[index]
                    index += 1
                    guard GitRemote.isRepositorySlug(value) else {
                        return .failure(ParseError("`--repo` takes a repository as owner/name, not `\(value)`"))
                    }
                    repository = value
                case "--id":
                    guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
                    let value = arguments[index]
                    index += 1
                    guard isID(value) else { return .failure(ParseError("`--id`: \(idRule(value))")) }
                    id = value
                case "--body", "--from":
                    guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
                    let value = arguments[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    index += 1
                    if argument == "--body" { body = value.isEmpty ? nil : value } else { sender = value.isEmpty ? nil : value }
                case "--open":
                    guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
                    let value = arguments[index].trimmingCharacters(in: .whitespaces)
                    index += 1
                    guard let url = URL(string: value), url.scheme?.isEmpty == false else {
                        return .failure(ParseError("`--open` takes a URL with its scheme, such as https://example.com, not `\(value)`"))
                    }
                    actions.append(.url(url))
                case "--app":
                    guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
                    let value = arguments[index].trimmingCharacters(in: .whitespaces)
                    index += 1
                    guard !value.isEmpty else { return .failure(ParseError("`--app` takes an app's bundle id or name")) }
                    actions.append(.app(value))
                case "--herdr":
                    if index < arguments.count, isHerdrID(arguments[index]) {
                        actions.append(.herdr(arguments[index]))
                        index += 1
                    } else {
                        let pane = herdrPane?.trimmingCharacters(in: .whitespaces) ?? ""
                        guard !pane.isEmpty else {
                            return .failure(ParseError("`--herdr` without an id focuses your own pane, but \(herdrPaneVariable) isn't set (you're not in Herdr); pass a tab or pane id such as w1:t2"))
                        }
                        actions.append(.herdr(pane))
                    }
                default:
                    return .failure(ParseError("unknown option `\(argument)`"))
                }
            }
            if titles.count > 1 {
                return .failure(ParseError("one title only; quote it: shipyard ping send \"\(titles.joined(separator: " "))\""))
            }
            let title = titles.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return .failure(ParseError("give the ping a title: \(usageLine)")) }
            if project != nil, repository != nil {
                return .failure(ParseError("pass --repo or --project, not both"))
            }
            if actions.count > 1 {
                return .failure(ParseError("a ping has one action at most; pass one of \(actionFlags.joined(separator: ", "))"))
            }
            return .success(Request(
                title: title,
                project: project,
                repository: repository,
                body: body,
                sender: sender,
                action: actions.first,
                id: id
            ))
        }
    }

    /// Whether `argument` is shaped like a Herdr tab or pane id, as Herdr
    /// prints them: a workspace, a colon, then `t` or `p` and a number
    /// (`w1:t2`, `w1:p3`). Only such an argument after `--herdr` is its id,
    /// so `--herdr "Ready"` still reads "Ready" as the title.
    public static func isHerdrID(_ argument: String) -> Bool {
        argument.range(of: #"\A[^\s:]+:[tp][0-9]+\z"#, options: .regularExpression) != nil
    }

    struct ParseError: Error, Equatable {
        var message: String
        init(_ message: String) { self.message = message }
    }
}

