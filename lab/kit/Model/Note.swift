import Foundation

/// One of the user's own notes: a page in its project's notes database in
/// Notion, read from a data-source query (`NotionNotes`). Notion is the
/// editor; shipyard only lists open notes and opens them.
public struct Note: Equatable, Hashable, Sendable {
    /// The page's id.
    public var id: String
    /// The page in Notion, which clicking the row opens.
    public var url: URL
    /// Its `No.`: the number Notion gave it, unique in its project and never
    /// reused; `nil` when the database has no such property.
    public var number: Int?
    /// The number's prefix, the same for every note of a project ("SHIP");
    /// `nil` without one.
    public var prefix: String?
    /// Its `Name`, as written; empty for a note nobody titled yet.
    public var title: String
    /// The first line of its body, read only for a note without a title.
    public var firstLine: String?
    /// Its `Labels`, in Notion's order.
    public var labels: [String]
    /// Its `Status`: `Open`, `Archived`, or `nil` (no status), which is open.
    public var status: String?
    /// When the page was created, which orders notes newest first.
    public var created: Date
    /// When the page was last edited.
    public var edited: Date

    public init(
        id: String,
        url: URL,
        number: Int?,
        prefix: String? = nil,
        title: String,
        firstLine: String? = nil,
        labels: [String] = [],
        status: String? = nil,
        created: Date,
        edited: Date
    ) {
        self.id = id
        self.url = url
        self.number = number
        self.prefix = prefix
        self.title = title
        self.firstLine = firstLine
        self.labels = labels
        self.status = status
        self.created = created
        self.edited = edited
    }

    /// The status a note starts with, as the new-note icon writes it.
    public static let open = "Open"
    /// The status that takes a note out of the menu.
    public static let archived = "Archived"

    /// Whether the note is archived: its status says so, in any case.
    public var isArchived: Bool {
        status?.caseInsensitiveCompare(Self.archived) == .orderedSame
    }

    /// What the row shows as its title: the title, else the body's first
    /// line, else "Untitled", as Notion itself says.
    public var displayTitle: String {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { return title }
        if let line = firstLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty { return line }
        return "Untitled"
    }

    /// How the user names the note: its number with its prefix, "SHIP-7",
    /// or the number alone without a prefix; `nil` without a number.
    public var reference: String? {
        guard let number else { return nil }
        guard let prefix, !prefix.isEmpty else { return String(number) }
        return "\(prefix)-\(number)"
    }

    /// The note as a listed item: kind `note`, always open, aged (and
    /// sorted, newest first) from when it was created, under no repository
    /// and with no GitHub author. Its URL is the page's in Notion.
    public var item: Item {
        Item(
            kind: .note,
            repository: "",
            number: number ?? 0,
            title: displayTitle,
            url: url,
            author: "",
            authorKind: .other,
            state: .open,
            createdAt: created,
            // Created, not edited: an edit doesn't move a note up the list.
            updatedAt: created,
            note: self
        )
    }
}
