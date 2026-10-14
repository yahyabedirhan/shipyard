import Foundation
import ShipyardConfig

struct RepositoryRequest: Equatable, Sendable {
    var slug: String
    var pullRequests: Bool
    var issues: Bool = false
    var runsWindow: TimeInterval? = nil
    var runBranches: Bool = false

    var owner: String { String(slug.split(separator: "/", maxSplits: 1)[0]) }
    var name: String { String(slug.split(separator: "/", maxSplits: 1)[1]) }
}

struct ReviewSearchResult: Equatable, Sendable {
    var pullRequests: [Item] = []
    var total = 0
}

enum ProjectQuery {
    /// Repositories asked about per request. A refresh with more sends
    /// several requests, one after another, so one query stays inside
    /// GitHub's resource limits however many repositories the projects
    /// watch: eleven repositories with issues in one query came back cut
    /// short (`RESOURCE_LIMITS_EXCEEDED`), any five of them whole (see
    /// `docs/references/github-rate-limits.md`). A batch cut short anyway
    /// is asked again in smaller requests (`split`).
    static let repositoriesPerRequest = 5

    /// The GraphQL error `type` GitHub gives when it stopped a query part
    /// way because it used too many resources, answering what it had so far.
    static let resourceLimitsExceeded = "RESOURCE_LIMITS_EXCEEDED"

    static let openFirst = 50
    static let closedFirst = 20

    static let reviewSearchQuery = "is:pr is:open archived:false review-requested:@me"
    static let reviewSearchFirst = 100
    static let reviewSearchAlias = "reviewSearch"

    static func plan(_ projects: [ProjectSettings]) -> [RepositoryRequest] {
        var requests: [RepositoryRequest] = []
        var index: [String: Int] = [:]
        for project in projects {
            for slug in project.repositorySlugs {
                let key = slug.lowercased()
                let at = index[key] ?? requests.count
                if at == requests.count {
                    index[key] = at
                    requests.append(RepositoryRequest(slug: slug, pullRequests: false))
                }
                requests[at].pullRequests = requests[at].pullRequests || project.pullRequests.show
                requests[at].issues = requests[at].issues || project.issues.show
                let runs = project.workflowRuns
                if runs.show {
                    requests[at].runsWindow = max(requests[at].runsWindow ?? 0, runs.finishedWindow)
                    requests[at].runBranches = requests[at].runBranches || runs.branches == .defaultAndPullRequests
                }
            }
        }
        return requests
    }

    static func alias(_ index: Int) -> String { "repo\(index)" }

    struct Part: Equatable, Sendable {
        var repositories: [RepositoryRequest]
        var reviewSearch: Bool
    }

    static func split(_ repositories: [RepositoryRequest], reviewSearch: Bool) -> [Part]? {
        if repositories.count > 1 {
            let middle = repositories.count / 2
            return [
                Part(repositories: Array(repositories[..<middle]), reviewSearch: reviewSearch),
                Part(repositories: Array(repositories[middle...]), reviewSearch: false),
            ]
        }
        if repositories.count == 1, reviewSearch {
            return [Part(repositories: [], reviewSearch: true), Part(repositories: repositories, reviewSearch: false)]
        }
        return nil
    }

    static func document(_ repositories: [RepositoryRequest], reviewSearch: Bool = false) -> String {
        let parameters = repositories.indices
            .map { "$owner\($0): String!, $name\($0): String!" }
            .joined(separator: ", ")
        let fields = repositories.enumerated().map { index, repository in
            var selection = "    nameWithOwner\n"
            if repository.runBranches {
                selection += "    defaultBranchRef { name }\n"
                if !repository.pullRequests {
                    selection += """
                            openPullRequestHeads: pullRequests(states: OPEN, first: \(openFirst), orderBy: {field: UPDATED_AT, direction: DESC}) {
                              nodes { headRefName }
                            }

                        """
                }
            }
            if repository.pullRequests {
                selection += """
                        openPullRequests: pullRequests(states: OPEN, first: \(openFirst), orderBy: {field: UPDATED_AT, direction: DESC}) {
                          nodes { ...PullRequestFields }
                        }
                        closedPullRequests: pullRequests(states: [CLOSED, MERGED], first: \(closedFirst), orderBy: {field: UPDATED_AT, direction: DESC}) {
                          nodes { ...PullRequestFields }
                        }

                    """
            }
            if repository.issues {
                selection += """
                        openIssues: issues(states: OPEN, first: \(openFirst), orderBy: {field: UPDATED_AT, direction: DESC}) {
                          nodes { ...IssueFields }
                        }
                        closedIssues: issues(states: CLOSED, first: \(closedFirst), orderBy: {field: UPDATED_AT, direction: DESC}) {
                          nodes { ...IssueFields }
                        }

                    """
            }
            return "  \(alias(index)): repository(owner: $owner\(index), name: $name\(index)) {\n\(selection)  }\n"
        }.joined()

        var text = "query Shipyard\(parameters.isEmpty ? "" : "(\(parameters))") {\n"
        text += "  viewer { login }\n"
        if reviewSearch {
            text += """
                  \(reviewSearchAlias): search(type: ISSUE, query: "\(reviewSearchQuery)", first: \(reviewSearchFirst)) {
                    issueCount
                    nodes { ... on PullRequest { repository { nameWithOwner } ...PullRequestFields } }
                  }

                """
        }
        text += fields
        text += "  rateLimit { limit remaining used resetAt cost }\n}\n"
        if reviewSearch || repositories.contains(where: \.pullRequests) {
            text += """

                fragment PullRequestFields on PullRequest {
                  number title url isDraft state createdAt updatedAt closedAt mergedAt headRefName
                  baseRefName additions deletions changedFiles reviewDecision
                  author { login __typename avatarUrl }
                  comments { totalCount }
                  reviews { totalCount }
                  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
                }

                """
        }
        if repositories.contains(where: \.issues) {
            text += """

                fragment IssueFields on Issue {
                  number title url state createdAt updatedAt closedAt
                  author { login __typename avatarUrl }
                  comments { totalCount }
                }

                """
        }
        return text
    }

    static func body(_ repositories: [RepositoryRequest], reviewSearch: Bool = false) -> Data {
        var variables: [String: String] = [:]
        for (index, repository) in repositories.enumerated() {
            variables["owner\(index)"] = repository.owner
            variables["name\(index)"] = repository.name
        }
        let request = Request(query: document(repositories, reviewSearch: reviewSearch), variables: variables)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(request)) ?? Data()
    }

    private struct Request: Encodable {
        var query: String
        var variables: [String: String]
    }

    struct Parsed: Equatable, Sendable {
        var viewerLogin: String?
        var items: [String: [Item]] = [:]
        var errors: [String: RepositoryError] = [:]
        var rateLimit: RateLimit?
        var rateLimited = false
        var resourceLimited = false
        var branches: [String: RunBranches] = [:]
        var reviewSearch: ReviewSearchAnswer?

        mutating func add(_ next: Parsed) {
            viewerLogin = viewerLogin ?? next.viewerLogin
            reviewSearch = reviewSearch ?? next.reviewSearch
            items.merge(next.items) { _, later in later }
            errors.merge(next.errors) { _, later in later }
            branches.merge(next.branches) { _, later in later }
            if var limit = next.rateLimit ?? rateLimit {
                let costs = [rateLimit?.cost, next.rateLimit?.cost].compactMap { $0 }
                limit.cost = costs.isEmpty ? nil : costs.reduce(0, +)
                rateLimit = limit
            }
        }
    }

    enum ReviewSearchAnswer: Equatable, Sendable {
        case found(ReviewSearchResult)
        case failed(String)
    }

    static func parse(_ data: Data, repositories: [RepositoryRequest], reviewSearch: Bool = false) throws -> Parsed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response: Response
        do {
            response = try decoder.decode(Response.self, from: data)
        } catch {
            throw GitHubError.malformed
        }

        let errors = response.errors ?? []
        var parsed = Parsed()
        if errors.contains(where: { $0.type == "RATE_LIMITED" }) {
            parsed.rateLimited = true
            return parsed
        }
        guard let payload = response.data else {
            throw GitHubError.graphQL(errors.first?.message ?? "GitHub answered with neither data nor errors")
        }
        let limited = errors.filter { $0.type == resourceLimitsExceeded }
        parsed.resourceLimited = !limited.isEmpty
        func incompleteMessage(_ alias: String) -> String {
            let onPath = limited.first { $0.path?.first == .key(alias) }
            return (onPath ?? limited.first)?.message ?? "GitHub left entries out of its answer."
        }

        let viewer = payload.viewer?.login
        parsed.viewerLogin = viewer
        parsed.rateLimit = payload.rateLimit.map {
            RateLimit(limit: $0.limit, remaining: $0.remaining, used: $0.used, resetAt: $0.resetAt, cost: $0.cost)
        }
        if reviewSearch {
            if let search = payload.reviewSearch, parsed.resourceLimited || search.nodes.hasGaps {
                parsed.reviewSearch = .failed(incompleteMessage(reviewSearchAlias))
            } else if let search = payload.reviewSearch {
                let found = search.nodes.present.compactMap { node -> Item? in
                    guard let repository = node.repository?.nameWithOwner, let pullRequest = node.pullRequest else { return nil }
                    var item = pullRequest.item(in: repository, viewer: viewer)
                    item.reviewRequestedFromViewer = true
                    return item
                }
                parsed.reviewSearch = .found(ReviewSearchResult(pullRequests: found, total: search.issueCount ?? found.count))
            } else {
                let error = errors.first { $0.path?.first == .key(reviewSearchAlias) }
                parsed.reviewSearch = .failed(error?.message ?? "GitHub didn't answer the search")
            }
        }
        for (index, repository) in repositories.enumerated() {
            let alias = alias(index)
            if let node = payload.repositories[alias] ?? nil, parsed.resourceLimited || node.hasGaps {
                parsed.errors[repository.slug] = RepositoryError(
                    repository: repository.slug,
                    kind: .incomplete,
                    message: incompleteMessage(alias)
                )
            } else if let node = payload.repositories[alias] ?? nil {
                parsed.items[repository.slug] = node.items(in: repository.slug, viewer: viewer)
                if repository.runBranches { parsed.branches[repository.slug] = node.branches }
            } else {
                let error = errors.first { $0.path?.first == .key(alias) }
                parsed.errors[repository.slug] = RepositoryError(
                    repository: repository.slug,
                    kind: RepositoryError.Kind(graphQLType: error?.type),
                    message: error?.message ?? "Could not resolve to a Repository with the name '\(repository.slug)'."
                )
            }
        }
        return parsed
    }

    private struct Response: Decodable {
        var data: Payload?
        var errors: [GraphQLError]?
    }

    private struct GraphQLError: Decodable {
        var type: String?
        var message: String
        var path: [PathComponent]?
    }

    private enum PathComponent: Decodable, Equatable {
        case key(String)
        case index(Int)

        init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let index = try? container.decode(Int.self) {
                self = .index(index)
            } else {
                self = .key(try container.decode(String.self))
            }
        }
    }

    private struct Payload: Decodable {
        var viewer: ViewerNode?
        var rateLimit: RateLimitNode?
        var reviewSearch: SearchAnswer?
        var repositories: [String: RepositoryNode?] = [:]

        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            viewer = try container.decodeIfPresent(ViewerNode.self, forKey: Key(stringValue: "viewer"))
            rateLimit = try container.decodeIfPresent(RateLimitNode.self, forKey: Key(stringValue: "rateLimit"))
            reviewSearch = try container.decodeIfPresent(SearchAnswer.self, forKey: Key(stringValue: ProjectQuery.reviewSearchAlias))
            for key in container.allKeys where key.stringValue.hasPrefix("repo") && Int(key.stringValue.dropFirst(4)) != nil {
                repositories[key.stringValue] = .some(try container.decodeIfPresent(RepositoryNode.self, forKey: key))
            }
        }
    }

    private struct ViewerNode: Decodable {
        var login: String
    }

    private struct RateLimitNode: Decodable {
        var limit: Int
        var remaining: Int
        var used: Int?
        var resetAt: Date
        var cost: Int?
    }

    private struct Nodes<Node: Decodable>: Decodable {
        /// GitHub may answer `null` for a node it couldn't resolve.
        var nodes: [Node?]?
        var present: [Node] { (nodes ?? []).compactMap { $0 } }
        var hasGaps: Bool { (nodes ?? []).contains { $0 == nil } }
    }

    private struct SearchAnswer: Decodable {
        var nodes: Nodes<SearchNode>
        var issueCount: Int?

        init(from decoder: any Decoder) throws {
            nodes = try Nodes<SearchNode>(from: decoder)
            issueCount = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Int.self, forKey: .issueCount)
        }

        private enum CodingKeys: String, CodingKey { case issueCount }
    }

    private struct Count: Decodable {
        var totalCount: Int
    }

    private struct RepositoryNode: Decodable {
        var openPullRequests: Nodes<PullRequestNode>?
        var closedPullRequests: Nodes<PullRequestNode>?
        var openIssues: Nodes<IssueNode>?
        var closedIssues: Nodes<IssueNode>?
        var defaultBranchRef: BranchNode?
        var openPullRequestHeads: Nodes<HeadNode>?

        struct BranchNode: Decodable { var name: String }
        struct HeadNode: Decodable { var headRefName: String? }

        var hasGaps: Bool {
            [openPullRequests?.hasGaps, closedPullRequests?.hasGaps, openIssues?.hasGaps,
             closedIssues?.hasGaps, openPullRequestHeads?.hasGaps].contains(true)
        }

        var branches: RunBranches {
            let heads = (openPullRequests?.present ?? []).compactMap(\.headRefName)
                + (openPullRequestHeads?.present ?? []).compactMap(\.headRefName)
            return RunBranches(defaultBranch: defaultBranchRef?.name, pullRequestHeads: Set(heads))
        }

        func items(in repository: String, viewer: String?) -> [Item] {
            let pullRequests = (openPullRequests?.present ?? []) + (closedPullRequests?.present ?? [])
            let issues = (openIssues?.present ?? []) + (closedIssues?.present ?? [])
            return pullRequests.map { $0.item(in: repository, viewer: viewer) }
                + issues.map { $0.item(in: repository, viewer: viewer) }
        }
    }

    private struct AuthorNode: Decodable {
        var login: String
        var __typename: String?
        var avatarUrl: URL?
    }

    private struct SearchNode: Decodable {
        struct Repository: Decodable { var nameWithOwner: String }
        var repository: Repository?
        var pullRequest: PullRequestNode?

        private enum CodingKeys: String, CodingKey { case repository }

        init(from decoder: any Decoder) throws {
            repository = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Repository.self, forKey: .repository)
            pullRequest = try? PullRequestNode(from: decoder)
        }
    }

    private struct CommitNode: Decodable {
        struct Commit: Decodable {
            struct Rollup: Decodable { var state: String }
            var statusCheckRollup: Rollup?
        }
        var commit: Commit
    }

    private struct PullRequestNode: Decodable {
        var number: Int
        var title: String
        var url: URL
        var isDraft: Bool
        var state: String
        var createdAt: Date
        var updatedAt: Date
        var closedAt: Date?
        var mergedAt: Date?
        var headRefName: String?
        var baseRefName: String?
        var additions: Int?
        var deletions: Int?
        var changedFiles: Int?
        var reviewDecision: String?
        var author: AuthorNode?
        var comments: Count?
        var reviews: Count?
        var commits: Nodes<CommitNode>?

        func item(in repository: String, viewer: String?) -> Item {
            let (author, authorKind) = Self.author(self.author, viewer: viewer)
            let state: ItemState = switch self.state {
            case "MERGED": .merged
            case "CLOSED": .closed
            default: isDraft ? .draft : .open
            }
            return Item(
                kind: .pullRequest,
                repository: repository,
                number: number,
                title: title,
                url: url,
                author: author,
                authorKind: authorKind,
                state: state,
                checks: Self.checks(commits?.present.last?.commit.statusCheckRollup?.state),
                createdAt: createdAt,
                updatedAt: updatedAt,
                closedAt: state.isOpen ? nil : (closedAt ?? mergedAt ?? updatedAt),
                activity: (comments?.totalCount ?? 0) + (reviews?.totalCount ?? 0),
                avatarURL: self.author?.avatarUrl,
                details: ItemDetails(
                    headBranch: headRefName,
                    baseBranch: baseRefName,
                    additions: additions,
                    deletions: deletions,
                    changedFiles: changedFiles,
                    review: reviewDecision.flatMap(ReviewDecision.init(rawValue:)),
                    comments: comments?.totalCount ?? 0,
                    reviews: reviews?.totalCount ?? 0
                )
            )
        }

        static func author(_ node: AuthorNode?, viewer: String?) -> (String, AuthorKind) {
            guard let node else { return ("ghost", .other) }
            if node.__typename == "Bot" || node.login.hasSuffix("[bot]") {
                return (node.login.hasSuffix("[bot]") ? node.login : node.login + "[bot]", .bot)
            }
            if let viewer, node.login.lowercased() == viewer.lowercased() { return (node.login, .me) }
            return (node.login, .other)
        }

        static func checks(_ state: String?) -> ChecksState {
            switch state {
            case nil: .none
            case "SUCCESS": .passed
            case "FAILURE", "ERROR": .failed
            default: .pending
            }
        }
    }

    private struct IssueNode: Decodable {
        var number: Int
        var title: String
        var url: URL
        var state: String
        var createdAt: Date
        var updatedAt: Date
        var closedAt: Date?
        var author: AuthorNode?
        var comments: Count?

        func item(in repository: String, viewer: String?) -> Item {
            let (author, authorKind) = PullRequestNode.author(self.author, viewer: viewer)
            let state: ItemState = self.state == "CLOSED" ? .closed : .open
            return Item(
                kind: .issue,
                repository: repository,
                number: number,
                title: title,
                url: url,
                author: author,
                authorKind: authorKind,
                state: state,
                createdAt: createdAt,
                updatedAt: updatedAt,
                closedAt: state.isOpen ? nil : (closedAt ?? updatedAt),
                activity: comments?.totalCount ?? 0,
                avatarURL: self.author?.avatarUrl,
                details: ItemDetails(comments: comments?.totalCount ?? 0)
            )
        }
    }
}

extension RepositoryError.Kind {
    init(graphQLType type: String?) {
        switch type {
        case nil, "NOT_FOUND": self = .notFound
        case "FORBIDDEN": self = .forbidden
        case ProjectQuery.resourceLimitsExceeded: self = .incomplete
        default: self = .other
        }
    }
}
