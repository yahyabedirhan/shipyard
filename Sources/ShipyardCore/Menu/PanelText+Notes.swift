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

    /// The notes banner: why no note can be listed.
    public static func notesNotice(_ notice: NotesNotice) -> String {
        switch notice {
        case .notConnected:
            "Your notes live in Notion. Choose Connect Notion in the settings menu to list them here."
        case .noEntryPage:
            "Notion connected, but its token sees no Shipyard Notes page. Check the token is for your notes workspace, and share Shipyard Notes with the connection."
        }
    }

    /// The settings menu's item that shows the Notion card.
    public static let connectNotion = "Connect Notion…"
    /// The settings menu's item that forgets the token, once connected.
    public static let disconnectNotion = "Disconnect Notion"

    /// The Notion card's title and what it asks for.
    public static let notionCardTitle = "Connect Notion"
    public static let notionCardMessage = "Shipyard reads your notes with a Notion connection of its own, which sees only your Shipyard Notes page."
    /// The card's steps, in order: make the connection, share the page, paste.
    public static let notionCardSteps = [
        "Create an internal connection in your notes workspace.",
        "On its Access tab, add the Shipyard Notes page.",
        "Copy its Internal Integration Secret and paste it here.",
    ]
    /// The link to Notion's page of connections, and where it goes.
    public static let notionConnectionsLink = "Open Notion's connections"
    public static let notionConnectionsURL = URL(string: "https://www.notion.so/profile/integrations")!
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
