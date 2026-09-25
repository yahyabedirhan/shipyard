import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A repository the project picker offers or accepted.
public struct RepoSummary: Equatable, Sendable, Identifiable {
    /// `owner/name`, spelt the way GitHub spells it.
    public var slug: String
    public var description: String?
    public var isPrivate: Bool
    public var isArchived: Bool
    /// The last push to any branch; `nil` for a repository nobody pushed to.
    public var pushedAt: Date?

    public var id: String { slug }

    public init(slug: String, description: String? = nil, isPrivate: Bool = false, isArchived: Bool = false, pushedAt: Date? = nil) {
        self.slug = slug
        self.description = description
        self.isPrivate = isPrivate
        self.isArchived = isArchived
        self.pushedAt = pushedAt
    }
}

/// What checking a repository the user typed in the picker found.
public enum RepositoryCheck: Equatable, Sendable {
    /// GitHub has it and the token can see it; add this (GitHub's spelling).
    case accepted(RepoSummary)
    /// It can't be added, and why.
    case rejected(RepositoryRejection)
}

/// Why the picker can't add a typed repository. `message` is what it shows.
public enum RepositoryRejection: Equatable, Sendable {
    /// The text isn't `owner/name` (or a github.com link to one).
    case notASlug(String)
    /// GitHub answered 404: no such repository, or the token can't see it
    /// (GitHub answers the same for both).
    case notFound(String)
    /// GitHub refused access (403), for example an organisation that
    /// requires SSO for this token.
    case forbidden(String)
    /// GitHub couldn't be asked (network, rate limit, sign-in); try again.
    case couldNotCheck(String, GitHubError)

    public var message: String {
        switch self {
        case .notASlug(let text):
            return "`\(text)` isn't a repository: write it as owner/name, e.g. yahyabedirhan/shipyard"
        case .notFound(let slug):
            return "GitHub has no repository `\(slug)`, or your account can't see it"
        case .forbidden(let slug):
            return "GitHub refused access to `\(slug)`: your token may need access to its organisation"
        case .couldNotCheck(let slug, let error):
            let reason: String
            switch error {
            case .rateLimited: reason = "the rate limit ran out"
            case .secondaryLimit: reason = "GitHub asked to slow down"
            case .unauthorized: reason = "GitHub rejected the sign-in"
            case .network: reason = "GitHub can't be reached"
            default: reason = "GitHub answered with an error"
            }
            return "couldn't check `\(slug)` (\(reason)); try again"
        }
    }
}

/// The picker's two questions to GitHub: which repositories to suggest
/// (GraphQL, one request) and whether a typed one exists (REST, one request).
/// The query text and its parser live here, so they have one owner.
enum RepositoriesQuery {
    /// Repositories fetched from each list: the viewer's own (by push), and
    /// those they contributed to (by push).
    static let first = 25

    static let document = """
        query ShipyardRecentRepositories {
          viewer {
            login
            repositories(first: \(first), ownerAffiliations: [OWNER, COLLABORATOR], isArchived: false, orderBy: {field: PUSHED_AT, direction: DESC}) {
              nodes { ...RepositoryFields }
            }
            repositoriesContributedTo(first: \(first), orderBy: {field: PUSHED_AT, direction: DESC}) {
              nodes { ...RepositoryFields }
            }
          }
          rateLimit { limit remaining used resetAt cost }
        }

        fragment RepositoryFields on Repository {
          nameWithOwner description isPrivate isArchived pushedAt
        }

        """

    /// The JSON body to POST to `/graphql`.
    static var body: Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(["query": document])) ?? Data()
    }

    /// What the answer held: the suggestions, or GitHub saying the limit ran out.
    struct Parsed: Equatable, Sendable {
        var repositories: [RepoSummary] = []
        var rateLimited = false
    }

    /// Reads the answer: both lists merged, each repository once, archived
    /// ones left out, most recently pushed first (never pushed last; ties
    /// keep GitHub's order, own repositories first). Errors with no data
    /// throw `.graphQL`; a body that isn't GraphQL's shape throws `.malformed`.
    static func parse(_ data: Data) throws -> Parsed {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response: Response
        do {
            response = try decoder.decode(Response.self, from: data)
        } catch {
            throw GitHubError.malformed
        }
        let errors = response.errors ?? []
        if errors.contains(where: { $0.type == "RATE_LIMITED" }) { return Parsed(rateLimited: true) }
        guard let viewer = response.data?.viewer else {
            throw GitHubError.graphQL(errors.first?.message ?? "GitHub answered with neither data nor errors")
        }

        let nodes = (viewer.repositories?.present ?? []) + (viewer.repositoriesContributedTo?.present ?? [])
        var seen = Set<String>()
        let repositories = nodes
            .filter { !$0.isArchived && seen.insert($0.nameWithOwner.lowercased()).inserted }
            .map(\.summary)
            .enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.pushedAt, rhs.element.pushedAt) {
                case let (left?, right?) where left != right: return left > right
                case (_?, nil): return true
                case (nil, _?): return false
                default: return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
        return Parsed(repositories: repositories)
    }

    private struct Response: Decodable {
        var data: Payload?
        var errors: [GraphQLError]?
    }

    private struct GraphQLError: Decodable {
        var type: String?
        var message: String
    }

    private struct Payload: Decodable {
        var viewer: ViewerNode?
    }

    private struct ViewerNode: Decodable {
        var repositories: Nodes?
        var repositoriesContributedTo: Nodes?
    }

    private struct Nodes: Decodable {
        var nodes: [RepositoryNode?]?
        var present: [RepositoryNode] { (nodes ?? []).compactMap { $0 } }
    }

    private struct RepositoryNode: Decodable {
        var nameWithOwner: String
        var description: String?
        var isPrivate: Bool
        var isArchived: Bool
        var pushedAt: Date?

        var summary: RepoSummary {
            RepoSummary(slug: nameWithOwner, description: description, isPrivate: isPrivate, isArchived: isArchived, pushedAt: pushedAt)
        }
    }

    // MARK: - Checking one

    /// `text` as `owner/name`: trimmed, and taken out of a github.com link
    /// (`https://github.com/owner/name`, with or without `.git` or a
    /// trailing slash). `nil` when it isn't a repository slug.
    static func slug(from text: String) -> String? {
        var slug = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "github.com/"]
        where slug.lowercased().hasPrefix(prefix) {
            slug = String(slug.dropFirst(prefix.count))
            if slug.hasSuffix("/") { slug.removeLast() }
            if slug.hasSuffix(".git") { slug.removeLast(4) }
            break
        }
        return ConfigurationReader.isRepositorySlug(slug) ? slug : nil
    }

    /// REST's `GET /repos/{owner}/{repo}` answer, the fields the picker reads.
    struct RESTRepository: Decodable {
        var full_name: String
        var description: String?
        var `private`: Bool
        var archived: Bool
        var pushed_at: Date?

        var summary: RepoSummary {
            RepoSummary(slug: full_name, description: description, isPrivate: `private`, isArchived: archived, pushedAt: pushed_at)
        }
    }
}

extension GitHubClient {
    /// The picker's suggestions: the viewer's repositories and those they
    /// contributed to, most recently pushed first, without archived ones.
    /// A limit that ran out without a reset time waits from `now`.
    public func recentRepositories(at now: Date) async throws -> [RepoSummary] {
        var request = URLRequest(url: Self.graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = RepositoriesQuery.body
        let (data, response) = try await send(request)

        let headers = RateLimit(headers: response)
        let resetAt = headers?.resetAt ?? now.addingTimeInterval(RateBudget.defaultRetryAfter)
        let parsed: RepositoriesQuery.Parsed
        do {
            parsed = try RepositoriesQuery.parse(data)
        } catch GitHubError.graphQL(let message) {
            if headers?.remaining == 0 { throw GitHubError.rateLimited(resetAt: resetAt, api: .graphql) }
            throw GitHubError.graphQL(message)
        }
        if parsed.rateLimited { throw GitHubError.rateLimited(resetAt: resetAt, api: .graphql) }
        return parsed.repositories
    }

    /// The repository `slug` names (`owner/name`), as GitHub has it. A 404
    /// (missing, or the token can't see it) throws `.http(404)`.
    public func repository(_ slug: String) async throws -> RepoSummary {
        let request = URLRequest(url: Self.apiURL.appendingPathComponent("repos/\(slug)"))
        let (data, _) = try await send(request)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let repository = try? decoder.decode(RepositoriesQuery.RESTRepository.self, from: data) else {
            throw GitHubError.malformed
        }
        return repository.summary
    }
}
