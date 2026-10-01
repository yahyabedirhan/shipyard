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

    public init(id: String, title: String, projects: [String], sent: Date, seen: Date? = nil, repository: String? = nil) {
        self.id = id
        self.title = title
        self.projects = projects
        self.sent = sent
        self.seen = seen
        self.repository = repository
    }

    /// The ping as a listed item: kind `ping`, always open, aged from when
    /// it was sent, in the repository it was filed by (if any). Its URL only names it (`shipyard://ping/<id>`), so it
    /// never collides with a GitHub item's; nothing opens it.
    public var item: Item {
        Item(
            kind: .ping,
            repository: repository ?? "",
            number: 0,
            title: title,
            url: Self.url(id: id),
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

    /// The letters a generated id is made of: lowercase letters and digits
    /// without the ones easy to misread (`0`, `o`, `1`, `l`, `i`).
    static let idAlphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")

    /// A new short id: six letters from `idAlphabet`, such as `k7qm2x`.
    public static func newID() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<6).map { _ in idAlphabet.randomElement(using: &generator)! })
    }
}
