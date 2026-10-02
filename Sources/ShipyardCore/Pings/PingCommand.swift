import Foundation

/// `shipyard ping`: reads its arguments, files the ping under the projects
/// that watch its repository (or under the one `--project` names), saves it
/// to the ping store and prints its id. Pure apart from the store and the
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
        their attention until they click it, and prints its id. Clicking it
        runs its action, if it has one, and marks it seen.

          --body <text>        say more than the title fits
          --from <label>       who sent it: the agent or the task
          --id <id>            name it, to replace or withdraw it later; sending
                               an id again replaces that ping (new title, body,
                               action and projects, unseen again, no second
                               notification); without --id one is made up
          --open <url>         clicking it opens this URL (a page, an app's deep link)
          --app <id or name>   clicking it brings this app forward, by bundle id or name
          --herdr [<id>]       clicking it focuses this Herdr tab or pane (an id such as
                               w1:t2 or w1:p3); with no id, your own pane ($HERDR_PANE_ID)
          --repo <owner/name>  file it by this repository instead of the working folder's
          --project <name>     file it under this project (its name in config.toml) only

        One action at most; with none, clicking it only marks it seen. The
        argument after --herdr is its id only when it's shaped like one
        (workspace:tab or workspace:pane, as Herdr prints them). An id is 1 to
        64 lowercase letters, digits, - and _, starting with a letter or digit.
        Everything after -- is the title, even `withdraw` or a word starting
        with --: shipyard ping -- withdraw

        `shipyard ping withdraw <id>` takes the ping back: it leaves the menu,
        and its notification leaves Notification Center. It prints the id, or
        fails when no ping has it.

        """

    /// The usage line errors point at.
    static let usageLine = "shipyard ping \"<title>\" [options] (shipyard ping --help lists them)"

    /// The flags that give a ping its action; it takes one at most.
    static let actionFlags = ["--open", "--app", "--herdr"]

    /// The environment variable Herdr sets in each of its panes to that
    /// pane's id, which `--herdr` without an id takes.
    static let herdrPaneVariable = "HERDR_PANE_ID"

    /// Sends a ping with `arguments` (those after `ping`), sent at `now`.
    /// Without `--project` it's filed under every project of `configuration`
    /// that watches its repository: one the configuration names as
    /// `owner/name`, or one in the project's list in `resolved` (each
    /// project's repositories as the app last resolved them, by name).
    /// `newID` makes the id when `--id` gives none; one already stored is
    /// drawn again. A `--id` already stored replaces that ping: its sent
    /// time stays, and it's unseen again with no failure.
    public static func run(
        _ arguments: [String],
        environment: CommandEnvironment,
        configuration: Configuration,
        resolved: [String: [String]] = [:],
        store: PingStore,
        now: Date,
        newID: () -> String = Ping.newID
    ) -> CommandResult {
        let request: Request
        switch Request.parse(arguments, herdrPane: environment.variables[herdrPaneVariable]) {
        case .success(let parsed): request = parsed
        case .failure(let error): return .usage("shipyard ping: \(error.message)")
        }
        return send(
            request,
            folder: environment.workingDirectory,
            git: environment.git,
            configuration: configuration,
            resolved: resolved,
            store: store,
            now: now,
            newID: newID
        )
    }

    /// Files `request` and saves it, as `run` does once its arguments read:
    /// under the one `--project` names, else under every project that
    /// watches its repository (`--repo`, else the `origin` of `folder`;
    /// none when `folder` is `nil`), then prints its id. An id already
    /// stored is replaced. With `unfiled`, a ping no project takes is saved
    /// under none, with the repository it named (if any), instead of being
    /// refused: Herdr's ping for a blocked agent (`HerdrEvent`) has no one
    /// to tell about a refusal.
    static func send(
        _ request: Request,
        folder: URL?,
        git: any GitRemoteLookup,
        configuration: Configuration,
        resolved: [String: [String]],
        store: PingStore,
        now: Date,
        newID: () -> String = Ping.newID,
        unfiled: Bool = false
    ) -> CommandResult {
        let names = configuration.projects.map(\.name)
        let projects: [String]
        var repository: String?
        if let project = request.project {
            guard names.contains(project) else {
                return .failed("shipyard ping: no project is named `\(project)`; \(listing(names))")
            }
            projects = [project]
        } else {
            var slug = request.repository
            var noRepository: NoRepository?
            if slug == nil, let folder {
                switch workingRepository(folder: folder, git: git) {
                case .success(let found): slug = found
                case .failure(let reason): noRepository = reason
                }
            }
            let watching = slug.map { watchers(of: $0, configuration: configuration, resolved: resolved) } ?? []
            if let first = watching.first {
                projects = watching.map(\.project)
                repository = first.spelling
            } else if unfiled {
                projects = []
                repository = slug
            } else if let slug {
                return .failed("shipyard ping: no project watches `\(slug)`; pass --project <name> to file it under one; \(listing(names))")
            } else {
                let reason = noRepository?.message ?? "the ping names no repository"
                return .failed("shipyard ping: \(reason); pass --repo <owner/name> or --project <name>; \(listing(names))")
            }
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
            // A replace keeps when the ping was first sent, and its
            // instance, so it isn't notified again; seen and failure start
            // over, so it needs attention again.
            try store.save(Ping(
                id: id,
                title: request.title,
                projects: projects,
                sent: replaced?.sent ?? now,
                repository: repository,
                body: request.body,
                sender: request.sender,
                action: request.action,
                instance: replaced?.instance ?? UUID().uuidString.lowercased()
            ))
        } catch {
            return .failed("shipyard ping: couldn't save the ping in \(store.directory.path) (\(error.localizedDescription))")
        }
        return CommandResult(output: id + "\n")
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

    /// Why the working folder names no repository, as the error line says it.
    struct NoRepository: Error, Equatable {
        var message: String
    }

    /// The repository of the working folder `url`: its git remote `origin`, as `owner/name`.
    static func workingRepository(folder url: URL, git: any GitRemoteLookup) -> Result<String, NoRepository> {
        let folder = url.path
        guard let origin = git.origin(in: url) else {
            return .failure(NoRepository(message: "the working folder (\(folder)) isn't a git repository with a remote `origin` to file the ping by"))
        }
        guard let slug = GitRemote.repository(fromURL: origin) else {
            return .failure(NoRepository(message: "the working folder's remote `origin` (\(origin)) doesn't name a repository as owner/name"))
        }
        return .success(slug)
    }

    /// The projects that watch `slug`, in the configuration's order, each
    /// with the repository spelled as that project knows it (GitHub's
    /// spelling once resolved). Repositories match ignoring case, as
    /// GitHub's names do.
    static func watchers(
        of slug: String,
        configuration: Configuration,
        resolved: [String: [String]]
    ) -> [(project: String, spelling: String)] {
        configuration.projects.compactMap { project in
            let named = project.repositories.compactMap(\.slug)
            let known = named + (resolved[project.name] ?? [])
            guard let spelling = known.first(where: { $0.caseInsensitiveCompare(slug) == .orderedSame }) else { return nil }
            return (project.name, spelling)
        }
    }

    /// The projects a ping can be filed under, for an error.
    private static func listing(_ names: [String]) -> String {
        names.isEmpty ? "config.toml has no projects yet"
            : "the projects are " + names.map { "`\($0)`" }.joined(separator: ", ")
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
                    guard ConfigurationReader.isRepositorySlug(value) else {
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

