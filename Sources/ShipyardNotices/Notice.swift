import Foundation
import ShipyardCommand
import ShipyardPings

/// An agent's notice: a disposable status message ("tests running",
/// "done") it posts with `shipyard notify`, which the app shows as a
/// macOS notification when the user's rules let it (`agent.notice`), and
/// never keeps, counts or lists. Not a ping, which waits for the user.
///
/// It's filed like a ping: by the one project it names, or by its
/// repository, which the app files under the projects that watch it. The
/// `shipyard` command fills one of the two.
///
/// Its JSON is the one shape every route carries a notice in, the control
/// socket's request among them. Every field but `title` is optional and
/// left out when unset, so an app reads a notice from a newer command by
/// the fields it knows:
///
///     {"body":"12 of 40 passed","from":"claude","repository":"owner/shop","title":"Tests running"}
///
/// With every option (the image's `data` is the file's bytes in base64):
///
///     {"action":{"herdr":"w1:p3"},"body":"40 of 40 passed",
///      "buttons":[{"action":{"url":"https://github.com/owner/shop/pull/7"},"label":"Open PR"}],
///      "from":"claude","herdrSession":"work","id":"tests",
///      "image":{"data":"iVBORw0…","name":"chart.png"},"level":"passive",
///      "repository":"owner/shop","sound":"none","subtitle":"checkout",
///      "terminal":"com.mitchellh.ghostty","thread":"orchestration","title":"Tests passed"}
public struct Notice: Codable, Equatable, Sendable {
    /// The one line it shows, after the project's name.
    public var title: String
    /// More than the title fits.
    public var body: String?
    /// Who sent it (`--from`), the agent or its task.
    public var sender: String?
    /// The one project it's filed under (`--project`), by its name.
    public var project: String?
    /// The repository it's filed by (`--repo`, or the checkout's `origin`), as `owner/name`.
    public var repository: String?
    /// A line between the title and the body (`--subtitle`).
    public var subtitle: String?
    /// A picture shown with it (`--image`), carried as the file's bytes.
    public var image: NoticeImage?
    /// What it sounds like (`--sound`; `none` is `.silent`); `nil` is the default sound.
    public var sound: NoticeSound?
    /// The key its notifications stack under (`--thread`); `nil` stacks it
    /// with its project's.
    public var thread: String?
    /// How much it interrupts (`--level`); `nil` is `active`, macOS's default.
    public var level: NoticeLevel?
    /// The id it's shown under (`--id`): a notice with the id of one still
    /// shown replaces it in place, and `shipyard notify withdraw <id>`
    /// takes it away. `nil`: an id of its own, which nothing replaces.
    public var id: String?
    /// What clicking it does (`--open`, `--app`, `--herdr`), as a ping's
    /// click does; `nil`: nothing.
    public var action: PingAction?
    /// Up to three buttons (`--button "<label>=<action>"`), each with its
    /// own action; `nil` for none.
    public var buttons: [NoticeButton]?
    /// The terminal app (a bundle id) it was sent from, when its click or a
    /// button focuses Herdr: brought forward after the focus when
    /// `[herdr] terminal` isn't set, as for a ping (`Ping.terminal`).
    public var terminal: String?
    /// The named Herdr session it was sent from, when its click or a button
    /// focuses Herdr, as for a ping (`Ping.herdrSession`).
    public var herdrSession: String?

    public init(
        title: String,
        body: String? = nil,
        sender: String? = nil,
        project: String? = nil,
        repository: String? = nil,
        subtitle: String? = nil,
        image: NoticeImage? = nil,
        sound: NoticeSound? = nil,
        thread: String? = nil,
        level: NoticeLevel? = nil,
        id: String? = nil,
        action: PingAction? = nil,
        buttons: [NoticeButton]? = nil,
        terminal: String? = nil,
        herdrSession: String? = nil
    ) {
        self.title = title
        self.body = body
        self.sender = sender
        self.project = project
        self.repository = repository
        self.subtitle = subtitle
        self.image = image
        self.sound = sound
        self.thread = thread
        self.level = level
        self.id = id
        self.action = action
        self.buttons = buttons
        self.terminal = terminal
        self.herdrSession = herdrSession
    }

    enum CodingKeys: String, CodingKey {
        case title, body, project, repository, subtitle, image, sound, thread, level, id, action, buttons, terminal, herdrSession
        case sender = "from"
    }

    /// The most buttons a notice has.
    public static let mostButtons = 3

    /// The largest image a notice carries, in bytes: 5 MB, so a notice
    /// stays small enough for every route, and macOS shows it.
    public static let largestImage = 5 * 1024 * 1024

    /// Whether its click or one of its buttons focuses Herdr.
    var focusesHerdr: Bool {
        ([action] + (buttons ?? []).map(\.action)).contains { if case .herdr = $0 { true } else { false } }
    }
}

/// A notice's picture (`--image`): the file's name, whose extension says
/// its type, and its bytes, base64 in JSON. The command reads the file, so
/// the notice carries the picture wherever it goes.
public struct NoticeImage: Codable, Equatable, Hashable, Sendable {
    /// The file's name, such as `chart.png`.
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    /// The extensions of the pictures a notification shows, lowercase.
    public static let extensions = ["png", "jpg", "jpeg", "gif"]
}

/// What a notice sounds like (`--sound`): the default sound, none, or a
/// sound macOS knows by name. In JSON, one string: `default`, `none` or the name.
public enum NoticeSound: Codable, Equatable, Hashable, Sendable {
    case `default`
    /// No sound: `none` on the command line and in JSON.
    case silent
    /// A sound by its name, without its extension (`Glass`).
    case named(String)

    public init(_ text: String) {
        switch text {
        case "default": self = .default
        case "none": self = .silent
        default: self = .named(text)
        }
    }

    public var text: String {
        switch self {
        case .default: "default"
        case .silent: "none"
        case .named(let name): name
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

/// How much a notice interrupts (`--level`). Critical and time-sensitive
/// need entitlements shipyard doesn't have, so they aren't offered.
public enum NoticeLevel: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    /// Shown in Notification Center without a banner or a sound lighting the screen.
    case passive
    /// A banner, as any notification: the default.
    case active
}

/// One of a notice's buttons (`--button "<label>=<action>"`): its label
/// and what pressing it does, as a ping's click would.
public struct NoticeButton: Codable, Equatable, Hashable, Sendable {
    public var label: String
    public var action: PingAction

    public init(label: String, action: PingAction) {
        self.label = label
        self.action = action
    }
}

/// What a command asks of the app about notices: show one, or take one
/// it showed away by its id. Every route carries it as one JSON object: a
/// notice to show is the notice's own JSON, unchanged; a withdrawal is
/// `{"withdraw":"<id>"}`.
public enum NoticeRequest: Codable, Equatable, Sendable {
    /// `shipyard notify "<title>" …`.
    case show(Notice)
    /// `shipyard notify withdraw <id>`: the notice shown under `id` leaves
    /// Notification Center. One that's gone already, or never was, is no error.
    case withdraw(id: String)

    private enum CodingKeys: String, CodingKey {
        case withdraw
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let id = try container.decodeIfPresent(String.self, forKey: .withdraw) {
            self = .withdraw(id: id)
        } else {
            self = .show(try Notice(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .show(let notice):
            try notice.encode(to: encoder)
        case .withdraw(let id):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .withdraw)
        }
    }
}

/// What came of a notice request, as the agent that sent it learns it.
public enum NoticeVerdict: Equatable, Sendable {
    /// The app did it: posted the notice, or withdrew it.
    case shown
    /// It waits on this machine for the Mac's next poll of it, which
    /// shows it by the same rules, or drops it when it's waited too long;
    /// for a withdrawal, the waiting notice was taken away. Only a route
    /// that can't reach the app at once says this.
    case queued
    /// It wasn't done: why, in one line, such as "notices are off for
    /// project `shop`" or "shipyard isn't running, so this notice wasn't shown".
    case refused(String)
}

/// How a notice request reaches the app, and comes back with its verdict.
/// Each build gives `NoticeCommands` the route it has: on the Mac, the
/// running app's control socket; on another machine without a faster
/// way, the herdr-shipyard plugin, which holds it for the Mac's poll
/// (`PluginNoticeRoute`).
public protocol NoticeRoute: Sendable {
    /// Hands `request` to the app, sent by the command run in
    /// `environment`, and waits for its verdict. A route that can't reach
    /// the app refuses, saying so; it never starts the app.
    func deliver(_ request: NoticeRequest, environment: CommandEnvironment) -> NoticeVerdict
}
