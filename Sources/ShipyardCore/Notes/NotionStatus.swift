import Foundation

/// Where Notion stands for the Notion view, found through the same route
/// the notes are read through (`ntn`): whether `ntn` is there and logged
/// in, the name of its default workspace (`GET /v1/users/me`), and
/// whether search finds the "Shipyard Notes" page there.
public enum NotionStatus: Equatable, Sendable {
    /// No `ntn` where the app looks for it.
    case ntnMissing
    /// ntn is there but isn't logged in, has no workspace, or Notion
    /// stopped taking its login.
    case ntnLoggedOut
    /// ntn is logged in to `workspace`, which has no "Shipyard Notes" page.
    case noEntryPage(workspace: String?)
    /// ntn is logged in to `workspace`, which has the "Shipyard Notes" page.
    case ready(workspace: String?)
    /// Notion couldn't be asked (offline, ntn's own failure, an answer that
    /// didn't read), with why.
    case failed(NotionError)
    /// This run reads no notes (a demo run), so it never asks ntn.
    case notRead

    /// Asks Notion through `client`: who ntn is logged in as, then search
    /// for the entry page.
    static func check(_ client: NotionClient) async -> NotionStatus {
        do {
            let workspace = try await client.me()
            let entries = try await client.searchPages(titled: NotesReader.entryPageTitle)
            return entries.isEmpty ? .noEntryPage(workspace: workspace) : .ready(workspace: workspace)
        } catch let error as NotionError {
            switch error {
            case .ntnMissing: return .ntnMissing
            case .unauthorized: return .ntnLoggedOut
            default: return .failed(error)
            }
        } catch {
            return .failed(.network(error.localizedDescription))
        }
    }
}
