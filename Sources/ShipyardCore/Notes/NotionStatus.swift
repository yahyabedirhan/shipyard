import Foundation

/// Where Notion stands for the Notion view, found through the same route
/// the notes are read through (`ntn`): whether `ntn` is there and logged
/// in, the name of its default workspace (`GET /v1/users/me`), and
/// whether search finds the "Shipyard Notes" page there.
public enum NotionStatus: Equatable, Sendable {
    case ntnMissing
    case ntnLoggedOut
    case noEntryPage(workspace: String?)
    case ready(workspace: String?)
    case failed(NotionError)
    case notRead

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
