/// What the menu shows about notes besides their rows (`MenuModel.build`):
/// why a project's notes couldn't be read or a note couldn't be started,
/// and whether the projects' headers carry the new-note icon.
public struct NotesMenuState: Equatable, Sendable {
    /// Whether a Notion token is kept: the icon shows only then.
    public var connected: Bool
    /// Why each project's notes couldn't be read, by project name.
    public var readErrors: [String: String]
    /// Why the icon couldn't start a note, by project name.
    public var startErrors: [String: String]
    /// The projects a note is being started in now.
    public var starting: Set<String>

    public init(
        connected: Bool = false,
        readErrors: [String: String] = [:],
        startErrors: [String: String] = [:],
        starting: Set<String> = []
    ) {
        self.connected = connected
        self.readErrors = readErrors
        self.startErrors = startErrors
        self.starting = starting
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
    /// No Notion token is kept: the settings menu's Connect Notion takes one.
    case notConnected
    /// The token sees no page titled "Shipyard Notes".
    case noEntryPage
}
