import Foundation
import ShipyardConfig
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct RunBranches: Equatable, Sendable {
    var defaultBranch: String?
    var pullRequestHeads: Set<String>

    init(defaultBranch: String? = nil, pullRequestHeads: Set<String> = []) {
        self.defaultBranch = defaultBranch
        self.pullRequestHeads = pullRequestHeads
    }

    func keeps(_ branch: String?) -> Bool {
        guard let branch else { return false }
        return branch == defaultBranch || pullRequestHeads.contains(branch)
    }
}

/// A repository's workflow runs, from REST (GraphQL doesn't list them):
/// `GET /repos/{owner}/{repo}/actions/runs`, one conditional request per
/// repository per refresh. Builds the request and parses the answer into
/// items; the branch filter and the cache the `304` path reads live here too.
enum WorkflowRuns {
    static let perPage = 100

    static func url(for slug: String, since: Date) -> URL {
        var components = URLComponents(
            url: GitHubClient.apiURL.appendingPathComponent("repos/\(slug)/actions/runs"),
            resolvingAgainstBaseURL: false
        )!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // `>=` spelled out: URLComponents leaves `=` alone inside a value.
        components.percentEncodedQuery = [
            "created=%3E%3D\(formatter.string(from: since))",
            "exclude_pull_requests=true",
            "per_page=\(perPage)",
        ].joined(separator: "&")
        return components.url!
    }

    static func since(window: TimeInterval, at now: Date) -> Date {
        let start = now.timeIntervalSince1970 - max(0, window) - 3600
        return Date(timeIntervalSince1970: (start / 3600).rounded(.down) * 3600)
    }

    static func parse(_ data: Data, repository: String, viewer: String?) throws -> [Item] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let response = try? decoder.decode(Response.self, from: data) else { throw GitHubError.malformed }
        return response.workflow_runs.compactMap { $0.item(in: repository, viewer: viewer) }
    }

    static func filter(_ runs: [Item], branches: WorkflowRunBranches, known: RunBranches?) -> [Item] {
        switch branches {
        case .all: runs
        case .defaultAndPullRequests: runs.filter { (known ?? RunBranches()).keeps($0.branch) }
        }
    }

    private struct Response: Decodable {
        var workflow_runs: [Run]
    }

    private struct Actor: Decodable {
        var login: String
        var type: String?
        var avatar_url: URL?
    }

    private struct Run: Decodable {
        var name: String?
        var display_title: String?
        var run_number: Int
        var head_branch: String?
        var status: String?
        var conclusion: String?
        var html_url: URL
        var created_at: Date
        var updated_at: Date
        var run_started_at: Date?
        var run_attempt: Int?
        var event: String?
        var actor: Actor?

        func item(in repository: String, viewer: String?) -> Item? {
            guard let result = Self.state(status: status, conclusion: conclusion) else { return nil }
            let (state, checks) = result
            let (author, authorKind) = Self.author(actor, viewer: viewer)
            return Item(
                kind: .workflowRun,
                repository: repository,
                number: run_number,
                title: name ?? display_title ?? "Workflow run",
                url: html_url,
                author: author,
                authorKind: authorKind,
                state: state,
                checks: checks,
                createdAt: run_started_at ?? created_at,
                updatedAt: updated_at,
                closedAt: state == .running ? nil : updated_at,
                branch: head_branch,
                avatarURL: actor?.avatar_url,
                details: ItemDetails(runTitle: display_title, runEvent: event, runAttempt: run_attempt)
            )
        }

        static func state(status: String?, conclusion: String?) -> (ItemState, ChecksState)? {
            guard status == "completed" else { return (.running, .pending) }
            switch conclusion {
            case "success", "neutral": return (.succeeded, .passed)
            case "failure", "timed_out", "startup_failure": return (.failed, .failed)
            case "action_required": return (.running, .pending)
            default: return nil
            }
        }

        static func author(_ actor: Actor?, viewer: String?) -> (String, AuthorKind) {
            guard let actor else { return ("ghost", .other) }
            if actor.type == "Bot" || actor.login.hasSuffix("[bot]") {
                return (actor.login.hasSuffix("[bot]") ? actor.login : actor.login + "[bot]", .bot)
            }
            if let viewer, actor.login.lowercased() == viewer.lowercased() { return (actor.login, .me) }
            return (actor.login, .other)
        }
    }
}

final class WorkflowRunCache: @unchecked Sendable {
    struct Entry: Equatable {
        var url: URL
        var etag: String
        var runs: [Item]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    func entry(_ slug: String, url: URL) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[slug.lowercased()], entry.url == url else { return nil }
        return entry
    }

    func store(_ entry: Entry?, for slug: String) {
        lock.lock()
        defer { lock.unlock() }
        entries[slug.lowercased()] = entry
    }
}
