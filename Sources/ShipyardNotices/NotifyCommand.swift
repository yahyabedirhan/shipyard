import Foundation
import ShipyardCommand
import ShipyardPings

/// The notices' commands for a `shipyard` build's `CommandTable`:
/// `notify`, handing each notice request to the app over `route`.
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
                  shipyard notify "<title>" [--subtitle <text>] [--body <text>] [--from <label>]
                                  [--repo <owner/name> | --project <name>] [--id <id>] …
                  shipyard notify withdraw <id>

        """
}

/// `shipyard notify`: reads its arguments into a `Notice`, filed by the
/// one project `--project` names or by its repository (`--repo`, else the
/// working folder's `origin`), hands it to the app over a `NoticeRoute`
/// and says what came of it; `shipyard notify withdraw <id>` asks the app
/// to take the notice shown under `id` away, over the same route. Exit 0:
/// done, or queued for the Mac's poll (`PluginNoticeRoute`, which says
/// so); 1: refused, with why (notices off for the project, no project
/// takes it, the app not running, the plugin missing or refusing it, the
/// Mac unreachable over the tailnet); 2: the arguments don't read, or the
/// route can't carry the notice (`NoticeRoute.unfit(_:)`).
public enum NotifyCommand {
    /// What `shipyard notify --help` prints.
    public static let usageText = """
        usage: shipyard notify "<title>" [--subtitle <text>] [--body <text>] [--from <label>]
                               [--repo <owner/name> | --project <name>]
                               [--image <path>] [--sound default|none|<name>]
                               [--thread <key>] [--level passive|active] [--id <id>]
                               [--open <url> | --app <bundle id or name> | --herdr [<tab or pane id>]]
                               [--button "<label>=<action>"]…
               shipyard notify withdraw <id>

        Shows the user a notice: a macOS notification titled with the project
        and the title, for a status update such as "tests running" or "done".
        Unlike a ping it isn't listed, counted or kept. It's filed under the
        projects that watch the working folder's repository (its git remote
        `origin`), and shown when the user's notification rules select
        `agent.notice` for one of them.

        Where it runs decides its route. On the Mac, it goes to the running app,
        and prints `shown` once the app showed it. On another machine whose
        cli.toml sets [notify] app-machine (with app-scheme and app-port when
        tailscale serve needs others), it goes over the tailnet to the app on
        that Mac, and prints `shown` the same way; a --herdr click or a herdr
        button can't go that way (the Mac would focus its own Herdr). Otherwise
        it's left with the herdr-shipyard plugin for the Mac's next poll, and
        prints `queued`: the Mac shows it by the same rules when it arrives, or
        drops it when it arrives more than ten minutes late. That route carries
        no image.

          --subtitle <text>    a line between the title and the body
          --body <text>        say more than the title fits
          --from <label>       who sent it: the agent or the task
          --repo <owner/name>  file it by this repository instead of the working folder's
          --project <name>     file it under this project (its name in config.toml) only
          --image <path>       show this PNG, JPEG or GIF with it (5 MB at most)
          --sound <sound>      default, none, or a sound's name such as Glass
          --thread <key>       stack it with the other notices of this thread
          --level <level>      passive: into Notification Center without a banner;
                               active (the default): a banner, as any notification
          --id <id>            show it under this id: a notice with the id of one still
                               shown replaces it in place (1 to 64 lowercase letters,
                               digits, - and _)
          --open <url>         clicking it opens this URL
          --app <app>          clicking it brings this app forward (a bundle id or a name)
          --herdr [<id>]       clicking it focuses this Herdr tab or pane (w1:t2, w1:p3);
                               with no id, your own pane ($HERDR_PANE_ID)
          --button "<label>=<action>"
                               a button, up to 3; its action is open:<url>,
                               app:<bundle id or name>, herdr:<tab or pane id>, or
                               herdr alone for your own pane

        One of --open, --app and --herdr at most. Everything after -- is the
        title, even a word starting with --.

        withdraw <id> takes the notice shown under that id away and prints
        `withdrawn`; one already gone is no error. Through the plugin it takes
        away only a notice still waiting for the Mac's poll.

        Exits 1, with one line saying why, when it isn't shown or queued: notices
        are off for its projects, no project takes it, shipyard isn't running
        (it's never started for a notice), or the herdr-shipyard plugin is
        missing or refuses it. Over the tailnet, also when the Mac can't be
        reached, doesn't answer in time, or refuses the sender's Tailscale
        login, or when cli.toml doesn't read. Exits 2 when the arguments don't
        read, or carry a Herdr action over the tailnet.

        """

    /// The usage line errors point at.
    static let usageLine = "shipyard notify \"<title>\" [options] (shipyard notify --help lists them)"

    /// How a run's errors start.
    static let prefix = "shipyard notify: "

    /// The flags that give a notice its click; it takes one at most.
    static let actionFlags = ["--open", "--app", "--herdr"]

    /// The flags that take a value of text: an empty one is none.
    static let textFlags = ["--subtitle", "--body", "--from"]

    /// Every flag that takes a value (`--herdr` takes one only when it's an id).
    static let valueFlags = textFlags + ["--project", "--repo", "--image", "--sound", "--thread", "--level", "--id", "--open", "--app", "--button"]

    /// Runs `shipyard notify` with `arguments` (those after `notify`) in
    /// `environment`, delivering over `route`.
    public static func run(_ arguments: [String], environment: CommandEnvironment, route: any NoticeRoute) -> CommandResult {
        let flags = arguments.prefix { $0 != "--" }
        if flags.contains("--help") || flags.contains("-h") { return CommandResult(output: usageText) }
        if arguments.first == "withdraw" { return withdraw(Array(arguments.dropFirst()), environment: environment, route: route) }
        let request: Request
        switch parse(arguments, herdrPane: environment.variables[PingCommand.herdrPaneVariable]) {
        case .success(let parsed): request = parsed
        case .failure(let error): return .usage(prefix + error.message)
        }
        var notice = request.notice
        if let path = request.imagePath {
            switch readImage(path, in: environment.workingDirectory) {
            case .success(let image): notice.image = image
            case .failure(let error): return .usage(prefix + error.message)
            }
        }
        if notice.focusesHerdr {
            notice.terminal = PingCommand.outerTerminal(environment.variables)
            notice.herdrSession = PingCommand.herdrSession(environment.variables)
        }
        if let why = route.unfit(notice) { return .usage(prefix + why) }
        if notice.project == nil, notice.repository == nil {
            switch GitRemote.workingRepository(folder: environment.workingDirectory, git: environment.git, filing: "notice") {
            case .success(let slug): notice.repository = slug
            case .failure(let why): return .failed(prefix + why.message + "; pass --repo <owner/name> or --project <name>")
            }
        }
        switch route.deliver(.show(notice), environment: environment) {
        case .shown: return CommandResult(output: "shown\n")
        case .queued: return CommandResult(output: PluginNoticeRoute.queuedLine + "\n")
        case .refused(let why): return .failed(prefix + why)
        }
    }

    /// `shipyard notify withdraw <id>`, with `arguments` those after
    /// `withdraw`: asks the app over `route` to take the notice shown under
    /// the id away, and prints `withdrawn`.
    static func withdraw(_ arguments: [String], environment: CommandEnvironment, route: any NoticeRoute) -> CommandResult {
        let prefix = "shipyard notify withdraw: "
        guard arguments.count == 1, let id = arguments.first else {
            return .usage(prefix + "give the id of one notice: shipyard notify withdraw <id>")
        }
        guard PingCommand.isID(id) else { return .usage(prefix + PingCommand.idRule(id)) }
        switch route.deliver(.withdraw(id: id), environment: environment) {
        case .shown: return CommandResult(output: "withdrawn\n")
        case .queued: return CommandResult(output: PluginNoticeRoute.withdrawnLine + "\n")
        case .refused(let why): return .failed(prefix + why)
        }
    }

    /// A notice's arguments, read: the notice, and the image file
    /// `--image` names, which `run` reads.
    struct Request: Equatable {
        var notice: Notice
        var imagePath: String?
    }

    /// Why the arguments don't read, as the error line says it.
    struct ParseError: Error, Equatable {
        var message: String
        init(_ message: String) { self.message = message }
    }

    /// Reads `arguments`: one title and the flags `usageText` lists, in any
    /// order. Everything after `--` is the title. An empty `--subtitle`,
    /// `--body` or `--from` is none. `--herdr`, and a button's `herdr`
    /// action, without an id take `herdrPane` (the agent's own pane, from
    /// `HERDR_PANE_ID`). The notice's repository is left for `run` to find
    /// when neither `--repo` nor `--project` names where it goes.
    static func parse(_ arguments: [String], herdrPane: String? = nil) -> Result<Request, ParseError> {
        var titles: [String] = []
        var notice = Notice(title: "")
        var imagePath: String?
        var actions: [PingAction] = []
        var buttons: [NoticeButton] = []
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
            if argument == "--herdr" {
                if index < arguments.count, PingCommand.isHerdrID(arguments[index]) {
                    actions.append(.herdr(arguments[index]))
                    index += 1
                } else {
                    switch ownPane(herdrPane, for: "`--herdr`") {
                    case .success(let pane): actions.append(.herdr(pane))
                    case .failure(let error): return .failure(error)
                    }
                }
                continue
            }
            guard valueFlags.contains(argument) else { return .failure(ParseError("unknown option `\(argument)`")) }
            guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
            let value = arguments[index].trimmingCharacters(in: .whitespacesAndNewlines)
            index += 1
            switch argument {
            case "--subtitle": notice.subtitle = value.isEmpty ? nil : value
            case "--body": notice.body = value.isEmpty ? nil : value
            case "--from": notice.sender = value.isEmpty ? nil : value
            case "--project":
                guard !value.isEmpty else { return .failure(ParseError("`--project` takes a project's name")) }
                notice.project = value
            case "--repo":
                guard GitRemote.isRepositorySlug(value) else {
                    return .failure(ParseError("`--repo` takes a repository as owner/name, not `\(value)`"))
                }
                notice.repository = value
            case "--image":
                guard !value.isEmpty else { return .failure(ParseError("`--image` takes an image file's path")) }
                imagePath = value
            case "--sound":
                guard !value.isEmpty else { return .failure(ParseError("`--sound` takes default, none or a sound's name")) }
                notice.sound = NoticeSound(value)
            case "--thread":
                guard !value.isEmpty else { return .failure(ParseError("`--thread` takes a key the notices of one thread share")) }
                notice.thread = value
            case "--level":
                guard let level = NoticeLevel(rawValue: value) else {
                    return .failure(ParseError("`--level` takes passive or active, not `\(value)`"))
                }
                notice.level = level
            case "--id":
                guard PingCommand.isID(value) else { return .failure(ParseError("`--id`: \(PingCommand.idRule(value))")) }
                notice.id = value
            case "--open", "--app":
                switch action(argument == "--open" ? "open:" + value : "app:" + value, herdrPane: herdrPane, for: "`\(argument)`") {
                case .success(let action): actions.append(action)
                case .failure(let error): return .failure(error)
                }
            default:
                switch button(value, herdrPane: herdrPane) {
                case .success(let button): buttons.append(button)
                case .failure(let error): return .failure(error)
                }
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
        if actions.count > 1 {
            return .failure(ParseError("a notice's click has one action at most; pass one of \(actionFlags.joined(separator: ", "))"))
        }
        if buttons.count > Notice.mostButtons {
            return .failure(ParseError("a notice has \(Notice.mostButtons) buttons at most, not \(buttons.count)"))
        }
        notice.action = actions.first
        notice.buttons = buttons.isEmpty ? nil : buttons
        return .success(Request(notice: notice, imagePath: imagePath))
    }

    /// A button's value, `<label>=<action>`: split at the first `=`, so
    /// the action's URL may hold more.
    static func button(_ value: String, herdrPane: String?) -> Result<NoticeButton, ParseError> {
        let shape = "`--button` takes \"<label>=<action>\", its action open:<url>, app:<bundle id or name> or herdr[:<tab or pane id>]"
        guard let equals = value.firstIndex(of: "=") else { return .failure(ParseError("\(shape), not `\(value)`")) }
        let label = value[..<equals].trimmingCharacters(in: .whitespaces)
        let text = value[value.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard !label.isEmpty else { return .failure(ParseError("\(shape); `\(value)` has no label")) }
        guard text.hasPrefix("open:") || text.hasPrefix("app:") || text == "herdr" || text.hasPrefix("herdr:") else {
            return .failure(ParseError("\(shape), not `\(text)` for `\(label)`"))
        }
        return action(text, herdrPane: herdrPane, for: "`--button` `\(label)`").map { NoticeButton(label: label, action: $0) }
    }

    /// An action written `open:<url>`, `app:<bundle id or name>`, `herdr`
    /// or `herdr:<tab or pane id>`, as a button's is and as `--open` and
    /// `--app` read; `flag` names it in an error.
    static func action(_ text: String, herdrPane: String?, for flag: String) -> Result<PingAction, ParseError> {
        if text.hasPrefix("open:") {
            let value = String(text.dropFirst("open:".count)).trimmingCharacters(in: .whitespaces)
            guard let url = URL(string: value), url.scheme?.isEmpty == false else {
                return .failure(ParseError("\(flag) takes a URL with its scheme, such as https://example.com, not `\(value)`"))
            }
            return .success(.url(url))
        }
        if text.hasPrefix("app:") {
            let value = String(text.dropFirst("app:".count)).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { return .failure(ParseError("\(flag) takes an app's bundle id or name")) }
            return .success(.app(value))
        }
        guard text != "herdr" else { return ownPane(herdrPane, for: flag).map { .herdr($0) } }
        let id = String(text.dropFirst("herdr:".count))
        guard PingCommand.isHerdrID(id) else {
            return .failure(ParseError("\(flag) takes a Herdr tab or pane id such as w1:t2 or w1:p3, not `\(id)`"))
        }
        return .success(.herdr(id))
    }

    /// The agent's own Herdr pane, which a Herdr action without an id
    /// focuses, or why there's none.
    static func ownPane(_ herdrPane: String?, for flag: String) -> Result<String, ParseError> {
        let pane = herdrPane?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !pane.isEmpty else {
            return .failure(ParseError(
                "\(flag) without an id focuses your own pane, but \(PingCommand.herdrPaneVariable) isn't set (you're not in Herdr); pass a tab or pane id such as w1:t2"
            ))
        }
        return .success(pane)
    }

    /// The image at `path` (relative to `folder` unless absolute), read
    /// for `--image`: a PNG, JPEG or GIF of `Notice.largestImage` at most.
    static func readImage(_ path: String, in folder: URL) -> Result<NoticeImage, ParseError> {
        let file = path.hasPrefix("/") ? URL(fileURLWithPath: path) : folder.appendingPathComponent(path)
        guard NoticeImage.extensions.contains(file.pathExtension.lowercased()) else {
            return .failure(ParseError("`--image` takes a PNG, JPEG or GIF file, not `\(path)`"))
        }
        guard let data = try? Data(contentsOf: file) else {
            return .failure(ParseError("`--image` can't read `\(path)`"))
        }
        guard data.count <= Notice.largestImage else {
            return .failure(ParseError("`--image` `\(path)` is larger than a notice's 5 MB"))
        }
        return .success(NoticeImage(name: file.lastPathComponent, data: data))
    }
}
