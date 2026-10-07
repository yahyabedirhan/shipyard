import Foundation

/// What the menu shows about notes besides their rows (`MenuModel.build`):
/// why a project's notes couldn't be read or a note couldn't be started,
/// and whether the projects' headers carry the new-note icon.
public struct NotesMenuState: Equatable, Sendable {
    /// Whether notes can be started now (`ntn` is there and logged in):
    /// the icon shows only then.
    public var connected: Bool
    /// Why each project's notes couldn't be read, by project name.
    public var readErrors: [String: String]
    /// Why the icon couldn't start a note, by project name.
    public var startErrors: [String: String]
    /// The projects a note is being started in now.
    public var starting: Set<String>
    /// Each project's notes database in Notion, by project name, which its
    /// header's notes count opens.
    public var databases: [String: URL]

    public init(
        connected: Bool = false,
        readErrors: [String: String] = [:],
        startErrors: [String: String] = [:],
        starting: Set<String> = [],
        databases: [String: URL] = [:]
    ) {
        self.connected = connected
        self.readErrors = readErrors
        self.startErrors = startErrors
        self.starting = starting
        self.databases = databases
    }
}

/// A project header's new-note icon.
public enum NewNoteButton: Equatable, Sendable {
    /// A click starts a note (`Shipyard.startNote(in:)`).
    case ready
    /// A note is being started; a click does nothing.
    case starting
}

/// Why notes can't be listed at all, for the panel's notes banner.
public enum NotesNotice: Equatable, Sendable {
    /// No `ntn` where the app looks for it.
    case ntnMissing
    /// ntn isn't logged in, has no workspace, or Notion stopped taking
    /// its login.
    case ntnLoggedOut
    /// ntn's default workspace has no page titled "Shipyard Notes".
    case noEntryPage

    /// Why `reading` could list nothing at all; `nil` when it read, or
    /// failed in a way each project's error row says.
    init?(_ reading: NotesReading) {
        switch reading {
        case .noEntryPage: self = .noEntryPage
        case .failed(.ntnMissing): self = .ntnMissing
        case .failed(.unauthorized): self = .ntnLoggedOut
        case .failed, .read: return nil
        }
    }
}
