import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The branches a repository's runs are kept on under `branches =
/// "default-and-pull-requests"`: its default branch and the head branches of
/// its open pull requests, from the GraphQL request.
struct RunBranches: Equatable, Sendable {
    /// `nil` for a repository without one (empty).
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
    /// Runs asked for per repository (GitHub's maximum page).
    static let perPage = 100

    /// The request for `slug`'s runs created since `since`.
    /// `exclude_pull_requests` keeps the answer small; the branch filter uses
    /// the GraphQL request's pull request heads instead.
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

    /// The oldest creation time a refresh at `now` asks for, to show runs
    /// finished within `windowHours`: an hour before the window starts (so a
    /// run of up to an hour that finished inside it is still in the answer),
    /// rounded down to the hour, so the URL, and with it the `ETag`, stays
    /// the same for an hour and unchanged runs come back `304`.
    static func since(windowHours: Int, at now: Date) -> Date {
        let start = now.timeIntervalSince1970 - TimeInterval(max(0, windowHours) + 1) * 3600
        return Date(timeIntervalSince1970: (start / 3600).rounded(.down) * 3600)
    }

    /// The runs in GitHub's answer for `repository`. Cancelled, skipped and
    /// stale runs aren't listed (they neither ran nor failed). A body that
    /// isn't the endpoint's shape throws `.malformed`.
    static func parse(_ data: Data, repository: String, viewer: String?) throws -> [Item] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let response = try? decoder.decode(Response.self, from: data) else { throw GitHubError.malformed }
        return response.workflow_runs.compactMap { $0.item(in: repository, viewer: viewer) }
    }

    /// The runs a project keeps under `branches`.
    static func filter(_ runs: [Item], branches: WorkflowRunBranches, known: RunBranches?) -> [Item] {
        switch branches {
        case .all: runs
        case .defaultAndPullRequests: runs.filter { (known ?? RunBranches()).keeps($0.branch) }
        }
    }

    // MARK: - Response shape

    private struct Response: Decodable {
        var workflow_runs: [Run]
    }

    private struct Actor: Decodable {
        var login: String
        var type: String?
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
                branch: head_branch
            )
        }

        /// GitHub's `status` and `conclusion` as a semantic state: anything
        /// not `completed` is running (queued, waiting, in progress…);
        /// `action_required` waits on someone, so it's running too. `nil` for
        /// a run that isn't listed.
        static func state(status: String?, conclusion: String?) -> (ItemState, ChecksState)? {
            guard status == "completed" else { return (.running, .pending) }
            switch conclusion {
            case "success", "neutral": return (.succeeded, .passed)
            case "failure", "timed_out", "startup_failure": return (.failed, .failed)
            case "action_required": return (.running, .pending)
            default: return nil  // cancelled, skipped, stale
            }
        }

        /// REST spells a Bot's login with `[bot]` already.
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

/// The last answer for each repository's runs: the URL asked, its `ETag`
/// and the runs it listed, so the next request can be conditional and a
/// `304` reuses them. Kept in memory by the `GitHubClient` of one sign-in
/// (a relaunch asks afresh, once).
final class WorkflowRunCache: @unchecked Sendable {
    struct Entry: Equatable {
        var url: URL
        var etag: String
        var runs: [Item]
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    /// The entry for `slug`, if its last request was `url`.
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
