import Foundation
import ShipyardConfig

/// What shipyard reads from GitHub: the account, the picker's
/// repositories, the repository lookups and every project's items.
/// `GitHubClient` reads them from GitHub's API with a token; a demo run
/// with example items (`DemoItems`) answers them from its file, so it
/// sends nothing.
protocol GitHubReading: Sendable {
    func viewer() async throws -> Viewer
    func recentRepositories(at now: Date) async throws -> [RepoSummary]
    func repository(_ slug: String) async throws -> RepoSummary
    func repositories(of lookup: RepositoryLookup, at now: Date) async throws -> [RepoSummary]?
    func fetch(projects: [ProjectSettings], resolved: [String: ResolvedRepositories], at fetchedAt: Date) async throws -> Snapshot
}

extension GitHubClient: GitHubReading {}
