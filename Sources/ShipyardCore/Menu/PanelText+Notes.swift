import Foundation

// The words of notes: why a project's notes couldn't be read or a note
// couldn't be started, and the notes banner.
extension PanelText {
    /// Why notes couldn't be read, after "notes: " on the project's error
    /// row: "ntn isn't logged in; run ntn login in Terminal", "can't reach
    /// Notion (…)".
    public static func noteError(_ error: NotionError) -> String {
        switch error {
        case .ntnMissing:
            "ntn, Notion's CLI, isn't installed; install it, then run ntn login"
        case .unauthorized:
            "ntn isn't logged in; run ntn login in Terminal"
        case .rateLimited:
            "Notion asked shipyard to slow down; trying again in a minute"
        case .http(404, _, _):
            "Notion can't find its database; check that ntn's workspace is your notes workspace"
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
        case .notRead: "this run doesn't read notes"
        case .noEntryPage: "ntn's workspace has no page titled Shipyard Notes"
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
        case .ntnMissing:
            "Your notes live in Notion, and shipyard reads them with ntn, Notion's CLI. Install ntn and run ntn login to list them here."
        case .ntnLoggedOut:
            "ntn isn't logged in. Run ntn login in Terminal, choosing your notes workspace, to list your notes here."
        case .noEntryPage:
            "ntn's workspace has no Shipyard Notes page. Run ntn doctor to see its default workspace, and make it your notes workspace."
        }
    }
}
