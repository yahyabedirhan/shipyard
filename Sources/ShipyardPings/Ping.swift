import Foundation

/// A short message an agent sent the user through shipyard (`shipyard ping`),
/// filed under projects. Kept by shipyard itself in the `PingStore`, never
/// fetched from GitHub. The app lists it as an item of kind `ping`
/// (`Ping.item`, in ShipyardCore), and it needs attention until it's seen.
///
/// Later fields (a body, a sender, an action, a repository) join as
/// optional ones, so a record written by an older CLI still reads.
public struct Ping: Codable, Equatable, Hashable, Sendable, Identifiable {
    /// Short and readable, global: one id names one ping wherever it's filed.
    public var id: String
    public var title: String
    /// The names of the projects it's filed under.
    public var projects: [String]
    /// When it was sent, or last replaced: a replace starts its age again.
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
    /// The named Herdr session a `--herdr` ping was sent from (Herdr's
    /// `HERDR_SESSION` in the pane), whose server a click focuses its tab or
    /// pane on (`herdr --session <name>`); `nil` for Herdr's default
    /// session, for any other ping, and before it was kept. Kept on the
    /// machine, never listed (`PingList`): a remote ping is focused in the
    /// session its saved machine names.
    public var herdrSession: String?
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
        case id, title, projects, sent, seen, repository, body, sender, action, terminal, herdrSession, failure, failureDetail, instance, expires
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
        herdrSession: String? = nil,
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
        self.herdrSession = herdrSession
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
