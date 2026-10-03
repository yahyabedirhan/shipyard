import Foundation

// The words of notes: why a project's notes couldn't be read, and the
// card that takes the Notion token.
extension PanelText {
    /// Why notes couldn't be read, after "notes: " on the project's error
    /// row: "Notion rejected the token; connect Notion again from the
    /// settings menu", "can't reach Notion (…)".
    public static func noteError(_ error: NotionError) -> String {
        switch error {
        case .unauthorized:
            "Notion rejected the token; connect Notion again from the settings menu"
        case .rateLimited:
            "Notion asked shipyard to slow down; trying again in a minute"
        case .http(404, _, _):
            "Notion can't find its database; share the Shipyard Notes page with the connection"
        case .http(let status, _, let message):
            "Notion answered \(status)\(message.map { ": \($0)" } ?? "")"
        case .network(let reason):
            "can't reach Notion (\(reason))"
        case .unreadable(let what):
            "Notion's answer didn't read (\(what))"
        }
    }

    /// Why the new-note icon couldn't start a note, after "new note: " on
    /// the project's error row.
    public static func newNoteError(_ error: NewNoteError) -> String {
        switch error {
        case .notConnected: "connect Notion first, from the settings menu"
        case .noEntryPage: "no page titled Shipyard Notes is shared with shipyard's Notion connection"
        case .notion(let error): noteError(error)
        }
    }

    /// The new-note icon's hover help: "New note in shop".
    public static func newNoteHelp(_ project: String) -> String {
        "New note in \(project)"
    }

    /// The settings menu's item that shows the Notion card.
    public static let connectNotion = "Connect Notion…"
    /// The settings menu's item that forgets the token, once connected.
    public static let disconnectNotion = "Disconnect Notion"

    /// The Notion card's title and what it asks for.
    public static let notionCardTitle = "Connect Notion"
    public static let notionCardMessage = "Paste the token of your notes' Notion connection (an internal connection shared with the Shipyard Notes page). Shipyard keeps it in your Keychain and lists each project's open notes."
    /// The token field's placeholder, and the button that checks and keeps it.
    public static let notionTokenPlaceholder = "Notion token"
    public static let notionConnect = "Connect"

    /// What connecting came to, under the token field.
    public static func notionConnection(_ result: NotionConnection) -> String {
        switch result {
        case .connected: "Connected: notes list within a minute"
        case .empty: "Paste the token first"
        case .rejected: "Notion didn't take that token; copy it again from the connection's page"
        case .couldNotCheck(let error): "Couldn't check the token: \(noteError(error))"
        case .couldNotSave(let reason): "Couldn't keep the token in the Keychain (\(reason))"
        }
    }
}
