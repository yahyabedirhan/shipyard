import Foundation

/// A short message an agent sent the user through shipyard (`shipyard ping`),
/// filed under projects. Kept by shipyard itself in the `PingStore`, never
/// fetched from GitHub. It's listed as an `Item` of kind `ping`, and needs
/// attention until it's seen.
///
/// Later fields (a body, a sender, an action, a repository) join as
/// optional ones, so a record written by an older CLI still reads.
public struct Ping: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Short and readable, global: one id names one ping wherever it's filed.
    public var id: String
    public var title: String
    /// The names of the projects it's filed under.
    public var projects: [String]
    /// When it was sent.
    public var sent: Date
    /// When the user saw it (clicked its row); `nil` while it needs attention.
    public var seen: Date?
    /// The repository (`owner/name`) it was filed by, from the agent's
    /// working folder or `--repo`; `nil` when it was filed with `--project`.
    public var repository: String?
    /// More than the title fits (`--body`); `nil` when the agent gave none.
    public var body: String?
    /// Which agent or task sent it (`--from`); `nil` when the agent gave none.
    public var sender: String?
    /// What clicking it does (`--open`, `--app`, `--herdr`); `nil` when it only marks
    /// it seen.
    public var action: PingAction?
    /// The terminal app (a bundle id) a `--herdr` ping was sent from, brought
    /// forward on a click when `[herdr] terminal` isn't set; `nil` for any
    /// other ping, when the CLI couldn't tell, or before it was kept.
    public var terminal: String?
    /// Why its action last failed, in a few words for its row, shown until
    /// the next click, ⌥-click or dismiss; `nil` when it hasn't failed.
    public var failure: String?
    /// The same, whole, for its hover card; `nil` when `failure` says it
    /// all, or was written before the row's reason was kept short.
    public var failureDetail: String?
    /// Made new each time the id is sent as a new ping, and kept by a
    /// replace: its `ping.sent` occurrence, so a ping withdrawn and sent
    /// again under its id is new (and notifies) however soon it comes back,
    /// even while the app wasn't running, and a replace never is. `nil` for
    /// a ping written before it was kept.
    public var instance: String?
    /// When it leaves the machine it was sent on, a day after its sending or
    /// its last replace: set on Linux, where no app sees it seen, so an
    /// unanswered ping doesn't stay forever. `nil` on the Mac, where it stays
    /// until seen. Kept on the machine, never listed (`PingList`).
    public var expires: Date?
    /// The Herdr label of the machine it was sent on, for a remote ping
    /// the Mac read from that machine (`RemoteMachines`); `nil` for a ping
    /// sent on this computer. Set by the reader, never stored or listed:
    /// it isn't encoded.
    public var machine: String?

    private enum CodingKeys: String, CodingKey {
        case id, title, projects, sent, seen, repository, body, sender, action, terminal, failure, failureDetail, instance, expires
    }

    public init(
        id: String,
        title: String,
        projects: [String],
        sent: Date,
        seen: Date? = nil,
        repository: String? = nil,
        body: String? = nil,
        sender: String? = nil,
        action: PingAction? = nil,
        terminal: String? = nil,
        failure: String? = nil,
        failureDetail: String? = nil,
        instance: String? = nil,
        expires: Date? = nil,
        machine: String? = nil
    ) {
        self.id = id
        self.title = title
        self.projects = projects
        self.sent = sent
        self.seen = seen
        self.repository = repository
        self.body = body
        self.sender = sender
        self.action = action
        self.terminal = terminal
        self.failure = failure
        self.failureDetail = failureDetail
        self.instance = instance
        self.expires = expires
        self.machine = machine
    }

    /// What its notification says under the title: the body, then
    /// "from <sender>", each on its own line when given; empty when neither is.
    public var notificationBody: String {
        [body, sender.map { "from \($0)" }].compactMap { $0 }.joined(separator: "\n")
    }

    /// Whether `other` is this same sending of the ping: the same id and
    /// instance with the same content, whatever the app recorded on it since
    /// (seen, a failure). A ping withdrawn and sent anew under its id is a
    /// different instance; a replace keeps the instance but changes what
    /// it says, so it's a different sending too.
    public func isSameSending(as other: Ping) -> Bool {
        var mine = self, theirs = other
        mine.seen = nil
        mine.failure = nil
        mine.failureDetail = nil
        theirs.seen = nil
        theirs.failure = nil
        theirs.failureDetail = nil
        return mine == theirs
    }

    /// Whether it's still on its machine at `now`: one without an expiry
    /// always is; one with an expiry until then.
    public func isLive(at now: Date) -> Bool {
        expires.map { now < $0 } ?? true
    }

    /// Whether it's still listed under a `seen-window` of `seenWindow`
    /// seconds at `now`: an unseen ping always is; a seen one until
    /// `seenWindow` has passed since it was seen (a window of 0: not at all).
    public func isListed(seenWindow: TimeInterval, at now: Date) -> Bool {
        guard let seen else { return true }
        return now < seen.addingTimeInterval(seenWindow)
    }

    /// The ping as a listed item: kind `ping`, with no number (0) until
    /// `Listing` gives it its section's (`PingNumbers`), always open, aged from when
    /// it was sent, in the repository it was filed by (if any). Its URL only
    /// names it (`shipyard://ping/<id>`, or `shipyard://ping/<machine>/<id>`
    /// for a remote ping), so it never collides with a GitHub item's, nor
    /// the same id on another machine; a click runs its `action` instead. It has no GitHub author:
    /// its sender is on the ping, apart from author filters and rules.
    public var item: Item {
        Item(
            kind: .ping,
            repository: repository ?? "",
            number: 0,
            title: title,
            url: machine.map { Self.url(machine: $0, id: id) } ?? Self.url(id: id),
            author: "",
            authorKind: .other,
            state: .open,
            createdAt: sent,
            updatedAt: sent,
            ping: self
        )
    }

    /// The URL a ping's item is known by.
    public static func url(id: String) -> URL {
        URL(string: "shipyard://ping/\(id)")!
    }

    /// The URL a remote ping's item is known by: its machine's label and
    /// its id, each percent-encoded (a label may hold a space).
    public static func url(machine: String, id: String) -> URL {
        URL(string: "shipyard://ping/\(pathSegment(machine))/\(pathSegment(id))")!
    }

    /// The id a local ping's URL names; `nil` for a remote ping's URL, or
    /// any other.
    public static func id(from url: URL) -> String? {
        let path = segments(of: url)
        return path?.count == 1 ? path?.first : nil
    }

    /// The machine and id a remote ping's URL names; `nil` for a local
    /// ping's URL, or any other.
    public static func remote(from url: URL) -> (machine: String, id: String)? {
        guard let path = segments(of: url), path.count == 2 else { return nil }
        return (path[0], path[1])
    }

    /// A ping URL's path, decoded: `[id]` or `[machine, id]`.
    private static func segments(of url: URL) -> [String]? {
        guard url.scheme == "shipyard", url.host == "ping" else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        return path.isEmpty || path.contains(where: \.isEmpty) ? nil : path
    }

    /// `text` as one path segment: everything but unreserved characters percent-encoded.
    private static func pathSegment(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))) ?? text
    }

    /// The letters a generated id is made of: lowercase letters and digits
    /// without the ones easy to misread (`0`, `o`, `1`, `l`, `i`).
    static let idAlphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    /// A new short id: six letters from `idAlphabet`, such as `k7qm2x`.
    public static func newID() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<6).map { _ in idAlphabet.randomElement(using: &generator)! })
    }
}

/// What clicking a ping does: one action at most, given by the flag the
/// agent passed. Stored as `{"url": "…"}`, `{"app": "…"}` or `{"herdr": "…"}`.
public enum PingAction: Codable, Equatable, Hashable, Sendable {
    /// Opens a URL (`--open`): a web page, an artifact, an app's deep link.
    case url(URL)
    /// Brings an app forward (`--app`), named by its bundle id
    /// (`com.anthropic.claudefordesktop`) or its name (`Claude`).
    case app(String)
    /// Focuses a Herdr tab or pane (`--herdr`), by the id Herdr gives it:
    /// a tab's (`w1:t2`) or a pane's (`w1:p3`). Then `[herdr] terminal`, when
    /// set, is brought forward (`HerdrFocus`).
    case herdr(String)

    /// The icon a ping's row shows for it.
    public var icon: PingIcon {
        switch self {
        case .url: .link
        case .app: .app
        case .herdr: .terminal
        }
    }

    private enum CodingKeys: String, CodingKey {
        case url, app, herdr
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let url = try container.decodeIfPresent(URL.self, forKey: .url) {
            self = .url(url)
        } else if let app = try container.decodeIfPresent(String.self, forKey: .app) {
            self = .app(app)
        } else if let herdr = try container.decodeIfPresent(String.self, forKey: .herdr) {
            self = .herdr(herdr)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "an action this build doesn't know"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .url(let url): try container.encode(url, forKey: .url)
        case .app(let app): try container.encode(app, forKey: .app)
        case .herdr(let id): try container.encode(id, forKey: .herdr)
        }
    }
}

/// The icon a ping's row shows: what clicking it does.
public enum PingIcon: Equatable, Sendable {
    /// Opens a link.
    case link
    /// Brings an app forward.
    case app
    /// Focuses a Herdr tab or pane, then the terminal.
    case terminal
    /// Only marks it seen.
    case noAction
}
