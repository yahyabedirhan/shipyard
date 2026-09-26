import Foundation

/// One repository a refresh asks GitHub about, and what it asks for.
struct RepositoryRequest: Equatable, Sendable {
    /// `owner/name`, as the configuration spells it.
    var slug: String
    /// Whether any project with this repository shows pull requests.
    var pullRequests: Bool
    /// Whether any project with this repository shows issues. Only then does
    /// the query ask for its issues, so repositories without them cost nothing more.
    var issues: Bool = false
    /// The widest `finished-window-hours` of the projects with this
    /// repository that show workflow runs; `nil` when none does. Runs come
    /// from REST, not this query.
    var runsWindowHours: Int? = nil
    /// Whether a project keeps this repository's runs only on the default
    /// branch and open pull requests' heads: then the query asks for both.
    var runBranches: Bool = false

    var owner: String { String(slug.split(separator: "/", maxSplits: 1)[0]) }
    var name: String { String(slug.split(separator: "/", maxSplits: 1)[1]) }
}

/// The GraphQL request a refresh makes for one batch of repositories: each
/// repository as an alias (its pull requests and, where shown, its issues),
/// plus the viewer and the rate limit. Builds the query and parses the
/// answer into items, so the query text and its parser have one owner.
enum ProjectQuery {
    /// Repositories asked about per request. A refresh with more sends
    /// several requests, one after another, so one query stays well inside
    /// GitHub's node limit however many repositories the projects watch.
    static let repositoriesPerRequest = 25

    /// Open pull requests (and open issues) fetched per repository.
    static let openFirst = 50
    /// Closed or merged pull requests (and closed issues) fetched per
    /// repository, most recently updated first; the menu keeps those inside
    /// the closed window.
    static let closedFirst = 20
    /// Review requests read per pull request, to find the viewer's.
    static let reviewRequestsFirst = 10

    /// The repositories to ask about, each once, in the order the projects
    /// first name them.
    static func plan(_ projects: [ProjectSettings]) -> [RepositoryRequest] {
        var requests: [RepositoryRequest] = []
        var index: [String: Int] = [:]
        for project in projects {
            for slug in project.repositories {
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
                    requests[at].runsWindowHours = max(requests[at].runsWindowHours ?? 0, runs.finishedWindowHours)
                    requests[at].runBranches = requests[at].runBranches || runs.branches == .defaultAndPullRequests
                }
            }
        }
        return requests
    }

    /// The alias of the repository at `index`, e.g. `repo0`.
    static func alias(_ index: Int) -> String { "repo\(index)" }

    // MARK: - Building

    /// The query text for `repositories`, with `$owner<i>`/`$name<i>` variables.
    static func document(_ repositories: [RepositoryRequest]) -> String {
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
        text += fields
        text += "  rateLimit { limit remaining used resetAt cost }\n}\n"
        // GraphQL rejects a fragment no field uses.
        if repositories.contains(where: \.pullRequests) {
            text += """

                fragment PullRequestFields on PullRequest {
                  number title url isDraft state createdAt updatedAt closedAt mergedAt headRefName
                  author { login __typename }
                  comments { totalCount }
                  reviews { totalCount }
                  reviewRequests(first: \(reviewRequestsFirst)) { nodes { requestedReviewer { __typename ... on User { login } } } }
                  commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
                }

                """
        }
        if repositories.contains(where: \.issues) {
            text += """

                fragment IssueFields on Issue {
                  number title url state createdAt updatedAt closedAt
                  author { login __typename }
                  comments { totalCount }
                }

                """
        }
        return text
    }

    /// The JSON body to POST to `/graphql`.
    static func body(_ repositories: [RepositoryRequest]) -> Data {
        var variables: [String: String] = [:]
        for (index, repository) in repositories.enumerated() {
            variables["owner\(index)"] = repository.owner
            variables["name\(index)"] = repository.name
        }
        let request = Request(query: document(repositories), variables: variables)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Encoding strings and a string dictionary can't fail.
        return (try? encoder.encode(request)) ?? Data()
    }

    private struct Request: Encodable {
        var query: String
        var variables: [String: String]
    }

    // MARK: - Parsing

    /// What the answer held.
    struct Parsed: Equatable, Sendable {
        var viewerLogin: String?
        /// Items per repository slug (as requested).
        var items: [String: [Item]] = [:]
        var errors: [String: RepositoryError] = [:]
        /// The body's `rateLimit`, for its `cost`.
        var rateLimit: RateLimit?
        /// GitHub said the GraphQL limit ran out (status 200, `RATE_LIMITED`).
        var rateLimited = false
        /// Per repository slug that asked (`runBranches`): its default branch
        /// and open pull requests' heads, for the runs' branch filter.
        var branches: [String: RunBranches] = [:]

        /// Adds the answer to the next batch: its repositories' items,
        /// errors and branches. The rate limit is the later one's, costing
        /// the sum of both.
        mutating func add(_ next: Parsed) {
            viewerLogin = viewerLogin ?? next.viewerLogin
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

    /// Reads GitHub's answer. A body that isn't GraphQL's shape throws
    /// `.malformed`; errors with no data throw `.graphQL`. A repository whose
    /// alias came back `null` becomes a `RepositoryError`, and the rest still parse.
    static func parse(_ data: Data, repositories: [RepositoryRequest]) throws -> Parsed {
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

        let viewer = payload.viewer?.login
        parsed.viewerLogin = viewer
        parsed.rateLimit = payload.rateLimit.map {
            RateLimit(limit: $0.limit, remaining: $0.remaining, used: $0.used, resetAt: $0.resetAt, cost: $0.cost)
        }
        for (index, repository) in repositories.enumerated() {
            let alias = alias(index)
            if let node = payload.repositories[alias] ?? nil {
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

    // MARK: - Response shape

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
        /// `repo<i>` aliases; `nil` where GitHub answered `null`.
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
    }

    private struct ReviewRequestNode: Decodable {
        struct Reviewer: Decodable {
            var __typename: String?
            var login: String?
        }
        var requestedReviewer: Reviewer?
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
        var author: AuthorNode?
        var comments: Count?
        var reviews: Count?
        var reviewRequests: Nodes<ReviewRequestNode>?
        var commits: Nodes<CommitNode>?

        func item(in repository: String, viewer: String?) -> Item {
            let (author, authorKind) = Self.author(self.author, viewer: viewer)
            let state: ItemState = switch self.state {
            case "MERGED": .merged
            case "CLOSED": .closed
            default: isDraft ? .draft : .open
            }
            let reviewRequested = viewer.map { viewer in
                (reviewRequests?.present ?? []).contains {
                    $0.requestedReviewer?.__typename == "User"
                        && $0.requestedReviewer?.login?.lowercased() == viewer.lowercased()
                }
            } ?? false
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
                reviewRequestedFromViewer: reviewRequested,
                createdAt: createdAt,
                updatedAt: updatedAt,
                closedAt: state.isOpen ? nil : (closedAt ?? mergedAt ?? updatedAt),
                activity: (comments?.totalCount ?? 0) + (reviews?.totalCount ?? 0)
            )
        }

        /// A deleted account is GitHub's `ghost`. GraphQL names a Bot
        /// `dependabot`, where REST and the web say `dependabot[bot]`; the
        /// `[bot]` spelling is kept so `hide-authors` matches either way.
        static func author(_ node: AuthorNode?, viewer: String?) -> (String, AuthorKind) {
            guard let node else { return ("ghost", .other) }
            if node.__typename == "Bot" || node.login.hasSuffix("[bot]") {
                return (node.login.hasSuffix("[bot]") ? node.login : node.login + "[bot]", .bot)
            }
            if let viewer, node.login.lowercased() == viewer.lowercased() { return (node.login, .me) }
            return (node.login, .other)
        }

        /// `StatusCheckRollup.state`: SUCCESS, FAILURE, ERROR, PENDING, EXPECTED.
        static func checks(_ state: String?) -> ChecksState {
            switch state {
            case nil: .none
            case "SUCCESS": .passed
            case "FAILURE", "ERROR": .failed
            default: .pending
            }
        }
    }

    /// An issue: open or closed (GitHub's `stateReason`, completed or not
    /// planned, isn't read). No checks and no review requests; its activity
    /// is its comments.
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
                activity: comments?.totalCount ?? 0
            )
        }
    }
}

extension RepositoryError.Kind {
    /// From a GraphQL error's `type`.
    init(graphQLType type: String?) {
        switch type {
        case nil, "NOT_FOUND": self = .notFound
        case "FORBIDDEN": self = .forbidden
        default: self = .other
        }
    }
}
