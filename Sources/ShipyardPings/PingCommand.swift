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
        usage: shipyard ping "<title>" [--body <text>] [--from <label>] [--id <id>]
                             [--open <url> | --app <bundle id or name> | --herdr [<tab or pane id>]]
                             [--repo <owner/name> | --project <name>]
               shipyard ping withdraw <id>

        Sends the user a ping: it's listed under the projects that watch the
        repository of the working folder (its git remote `origin`), needs
        their attention until they click it, and prints its id, such as
        `k7qm2x`. Clicking it runs its action, if it has one, and marks it
        seen. The Mac's shipyard numbers it in each project it's listed in.

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
          --project <name>     file it under this project (its name in config.toml) only

        One action at most; with none, clicking it only marks it seen. The
        argument after --herdr is its id only when it's shaped like one
        (workspace:tab or workspace:pane, as Herdr prints them). An id is 1 to
        64 lowercase letters, digits, - and _, starting with a letter or digit.
        Everything after -- is the title, even `withdraw`, `list` or a word
        starting with --: shipyard ping -- withdraw

        `shipyard ping withdraw <id>` takes the ping back: it leaves the menu,
        and its notification leaves Notification Center. It prints the id, or
        fails when no ping has it.

        `shipyard ping list --json` prints this computer's pings as one line
        of JSON, newest first, for the Mac's shipyard to read through Herdr.

        On Linux, a computer without the app, a ping isn't filed there: it
        keeps its repository (or --project) as given, and the Mac files it.
        Sent from a Herdr pane without an action, clicking it focuses that
        pane. It leaves a day after its sending or its last replace.

        """

    /// The usage line errors point at.
    static let usageLine = "shipyard ping \"<title>\" [options] (shipyard ping --help lists them)"

    /// The flags that give a ping its action; it takes one at most.
    static let actionFlags = ["--open", "--app", "--herdr"]

    /// The environment variable Herdr sets in each of its panes to that
    /// pane's id, which `--herdr` without an id takes.
    static let herdrPaneVariable = "HERDR_PANE_ID"

    /// The environment variable Herdr sets in the panes of a named session
    /// (`herdr --session <name>`) to its name, inherited from its server.
    static let herdrSessionVariable = "HERDR_SESSION"

    /// The named Herdr session the CLI runs in, which a `--herdr` ping is
    /// focused in on a click: `HERDR_SESSION`, when it names one. `nil` in
    /// Herdr's default session (where it's unset, or `default`) and outside
    /// Herdr.
    static func herdrSession(_ variables: [String: String]) -> String? {
        let name = variables[herdrSessionVariable]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty || name == "default" ? nil : name
    }

    /// The bundle id of the terminal app the CLI runs in, which a `--herdr`
    /// ping brings forward on a click when `[herdr] terminal` is unset.
    /// `TERM_PROGRAM` names it when it's a known terminal's; Herdr sets its
    /// own (`herdr`) in its panes, so then `__CFBundleIdentifier`, the app
    /// macOS launched the process tree from, does, and last the variables a
    /// terminal sets for itself. `nil` when none says.
    static func outerTerminal(_ variables: [String: String]) -> String? {
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
        case .failure(let error): return .usage("shipyard ping: \(error.message)")
        }
        var sending = request
        // An action the agent gives wins over the filing's.
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

    /// Files `request` through `filing` and saves it, with the terminal and
    /// the named Herdr session a `--herdr` ping was sent from
    /// (`outerTerminal`, `herdrSession`), as `run` does once
    /// its arguments read, then prints its id. It's filed by the one
    /// project `--project` names, else by its repository (`--repo`, else
    /// the `origin` of `folder`; none when `folder` is `nil`). A refusal is
    /// returned with nothing written. An id already stored is replaced.
    /// `whenNoProject` says what a ping no project takes comes to:
    /// Herdr's ping for a blocked agent (`HerdrEvent`) is kept unfiled,
    /// since a refusal would reach no one. It expires when `filing` says,
    /// from `now`, so a replace starts its day again.
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
            // A replace is what the agent says now, so its age starts again;
            // it keeps its instance, so it isn't notified again; seen and
            // failure start over, so it needs attention again.
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
            return .failed("shipyard ping: couldn't save the ping in \(store.directory.path) (\(error.localizedDescription))")
        }
        return CommandResult(output: "\(id)\n")
    }

    /// What `request` is filed by: `--project`, else `--repo`, else the
    /// `origin` of `folder`, else nothing, with why.
    private static func target(of request: Request, folder: URL?, git: any GitRemoteLookup) -> FilingTarget {
        if let project = request.project { return .project(project) }
        if let repository = request.repository { return .repository(repository) }
        guard let folder else { return .none(why: "the ping names no repository") }
        switch GitRemote.workingRepository(folder: folder, git: git, filing: "ping") {
        case .success(let slug): return .repository(slug)
        case .failure(let reason): return .none(why: reason.message)
        }
    }

    /// `shipyard ping list --json`, with `arguments` those after `list`:
    /// prints the store's live pings at `now` as the remote ping list
    /// (`PingList`), newest first and capped, on one line. Only `--json`
    /// is accepted, so the contract is always asked for by name.
    public static func list(_ arguments: [String], store: PingStore, now: Date) -> CommandResult {
        guard arguments == ["--json"] else {
            return .usage("shipyard ping list: it prints JSON only; run shipyard ping list --json")
        }
        return CommandResult(output: PingList.encode(store.all().filter { $0.isLive(at: now) }) + "\n")
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
    static func isID(_ id: String) -> Bool {
        // `\A` and `\z`, not `^` and `$`, which also match before a
        // trailing newline: "build-42\n" isn't an id.
        id.range(of: #"\A[a-z0-9][a-z0-9_-]{0,63}\z"#, options: .regularExpression) != nil
    }

    /// What's wrong with an id that isn't one, for the error line.
    static func idRule(_ id: String) -> String {
        "an id is 1 to 64 lowercase letters, digits, - and _, starting with a letter or digit, not `\(id)`"
    }

    /// A ping's arguments, read.
    struct Request: Equatable {
        var title: String
        var project: String?
        /// `--repo`'s `owner/name`.
        var repository: String?
        var body: String?
        /// `--from`'s label.
        var sender: String?
        var action: PingAction?
        /// `--id`'s id; `nil` to make one up.
        var id: String?

        /// Reads `arguments`: one title; `--body` and `--from`; one action
        /// flag at most (`--open`, `--app`, `--herdr`); `--repo <owner/name>`
        /// or `--project <name>`; `--id <id>`; in any order. Everything after
        /// `--` is the title, flags or not. An empty `--body` or `--from`
        /// is none. `--herdr` takes the next argument as its id when it's
        /// shaped like a Herdr id (`isHerdrID`), and `herdrPane` (the
        /// agent's own pane, from `HERDR_PANE_ID`) otherwise.
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
                return .failure(ParseError("one title only; quote it: shipyard ping \"\(titles.joined(separator: " "))\""))
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
    static func isHerdrID(_ argument: String) -> Bool {
        argument.range(of: #"\A[^\s:]+:[tp][0-9]+\z"#, options: .regularExpression) != nil
    }

    /// Why the arguments don't read, as the error line says it.
    struct ParseError: Error, Equatable {
        var message: String
        init(_ message: String) { self.message = message }
    }
}

