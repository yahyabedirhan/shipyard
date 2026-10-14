import Foundation

/// What the menu shows about notes besides their rows (`MenuModel.build`):
/// why a project's notes couldn't be read or a note couldn't be started,
/// and whether the projects' headers carry the new-note icon.
public struct NotesMenuState: Equatable, Sendable {
    /// Whether notes can be started now (`ntn` is there and logged in):
    /// the icon shows only then.
    public var canStartNotes: Bool
    /// Why each project's notes couldn't be read, by project slug.
    public var readErrors: [String: String]
    /// Why the icon couldn't start a note, by project slug.
    public var startErrors: [String: String]
    /// The projects a note is being started in now.
    public var starting: Set<String>
    /// Each project's notes database in Notion, by project slug, which its
    /// header's notes count opens.
    public var databases: [String: URL]

    public init(
        canStartNotes: Bool = false,
        readErrors: [String: String] = [:],
        startErrors: [String: String] = [:],
        starting: Set<String> = [],
        databases: [String: URL] = [:]
    ) {
        self.canStartNotes = canStartNotes
        self.readErrors = readErrors
        self.startErrors = startErrors
        self.starting = starting
        self.databases = databases
    }
}

/// A project header's new-note icon.
public enum NewNoteButton: Equatable, Sendable {
    case ready
    case starting
}

/// Why notes can't be listed at all, for the panel's notes banner.
public enum NotesNotice: Equatable, Sendable {
    case ntnMissing
    case ntnLoggedOut
    case noEntryPage

    init?(_ reading: NotesReading) {
        switch reading {
        case .noEntryPage: self = .noEntryPage
        case .failed(.ntnMissing): self = .ntnMissing
        case .failed(.unauthorized): self = .ntnLoggedOut
        case .failed, .read: return nil
        }
    }

    var isNtn: Bool { self != .noEntryPage }
}
