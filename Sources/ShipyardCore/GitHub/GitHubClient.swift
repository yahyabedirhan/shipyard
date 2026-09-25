import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The signed-in GitHub account.
public struct Viewer: Equatable, Sendable, Decodable {
    public var login: String
    public var id: Int

    public init(login: String, id: Int) {
        self.login = login
        self.id = id
    }
}

/// Why a request to GitHub's API failed.
public enum GitHubError: Error, Equatable, Sendable {
    /// 401: the token is missing, revoked or expired. Shipyard signs out.
    case unauthorized
    /// Any other unexpected HTTP status.
    case http(Int)
    /// The request didn't reach GitHub.
    case network(String)
    /// GitHub's answer couldn't be read.
    case malformed
    /// GraphQL answered with errors and no data.
    case graphQL(String)
    /// `api`'s hourly limit ran out; requests work again at `resetAt`, from
    /// the response. GraphQL says so with a 200, REST with a 403 or 429.
    case rateLimited(resetAt: Date, api: RateAPI = .graphql)
    /// A secondary limit (too many requests too fast); wait `retryAfter` seconds.
    case secondaryLimit(retryAfter: TimeInterval)
}

/// Talks to GitHub's API with one token. Every request goes through `send`,
/// which authorises it and turns a 401 into `GitHubError.unauthorized`.
public struct GitHubClient: Sendable {
    public static let apiURL = URL(string: "https://api.github.com")!
    public static let graphQLURL = apiURL.appendingPathComponent("graphql")

    private let token: String
    private let transport: any HTTPTransport

    public init(token: String, transport: any HTTPTransport) {
        self.token = token
        self.transport = transport
    }

    /// The account the token belongs to.
    public func viewer() async throws -> Viewer {
        let request = URLRequest(url: Self.apiURL.appendingPathComponent("user"))
        let (data, _) = try await send(request)
        guard let viewer = try? JSONDecoder().decode(Viewer.self, from: data) else { throw GitHubError.malformed }
        return viewer
    }

    /// Every project's pull requests in one GraphQL request (each repository
    /// once, as an alias), with the viewer and the rate limit. A repository
    /// GitHub can't resolve becomes an error in the snapshot while the rest
    /// load. The GraphQL limit comes from the response headers, with the
    /// body's `cost`.
    public func fetch(projects: [ProjectSettings], at fetchedAt: Date) async throws -> Snapshot {
        let repositories = ProjectQuery.plan(projects)
        var request = URLRequest(url: Self.graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = ProjectQuery.body(repositories)
        let (data, response) = try await send(request)

        let headers = RateLimit(headers: response)
        // GraphQL's exhausted limit is a 200: an error typed RATE_LIMITED,
        // or at least `x-ratelimit-remaining: 0` with no data.
        let resetAt = headers?.resetAt ?? fetchedAt.addingTimeInterval(60)
        let parsed: ProjectQuery.Parsed
        do {
            parsed = try ProjectQuery.parse(data, repositories: repositories)
        } catch GitHubError.graphQL(let message) {
            if headers?.remaining == 0 { throw GitHubError.rateLimited(resetAt: resetAt, api: .graphql) }
            throw GitHubError.graphQL(message)
        }
        if parsed.rateLimited { throw GitHubError.rateLimited(resetAt: resetAt, api: .graphql) }
        var graphql = headers ?? parsed.rateLimit
        graphql?.cost = parsed.rateLimit?.cost

        var items: [String: [Item]] = [:]
        var errors: [String: RepositoryError] = [:]
        let slugs = Dictionary(repositories.map { ($0.slug.lowercased(), $0.slug) }, uniquingKeysWith: { first, _ in first })
        for project in projects {
            var projectItems: [Item] = []
            for repository in project.repositories {
                guard let slug = slugs[repository.lowercased()] else { continue }
                if let error = parsed.errors[slug] {
                    errors[repository] = RepositoryError(repository: repository, kind: error.kind, message: error.message)
                } else if project.pullRequests.show {
                    projectItems += (parsed.items[slug] ?? []).map { item in
                        var item = item
                        item.repository = repository
                        return item
                    }
                }
            }
            items[project.name] = projectItems
        }
        return Snapshot(
            fetchedAt: fetchedAt,
            items: items,
            errors: errors,
            rateLimits: RateLimits(graphql: graphql),
            viewerLogin: parsed.viewerLogin
        )
    }

    /// Sends `request` with the token and GitHub's headers. A 401 throws
    /// `.unauthorized`; other non-2xx statuses throw `.http`, or `.rateLimited` /
    /// `.secondaryLimit` for a 403 or 429 that says a limit was hit; transport
    /// failures throw `.network`; cancellation throws `CancellationError`.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var request = request
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("shipyard/\(ShipyardVersion.current)", forHTTPHeaderField: "User-Agent")
        if request.timeoutInterval > 30 { request.timeoutInterval = 30 }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch let error as CancellationError {
            throw error
        } catch {
            throw GitHubError.network(error.localizedDescription)
        }
        switch response.statusCode {
        case 200..<300: return (data, response)
        case 401: throw GitHubError.unauthorized
        case 403, 429:
            // GitHub's guidance: obey `retry-after`; else, with nothing
            // remaining, wait for `x-ratelimit-reset`; else wait at least a
            // minute. A 403 that says none of this is a permission error.
            if let retryAfter = response.value(forHTTPHeaderField: "retry-after")
                .flatMap({ TimeInterval($0.trimmingCharacters(in: .whitespaces)) }) {
                throw GitHubError.secondaryLimit(retryAfter: retryAfter)
            }
            if let limit = RateLimit(headers: response), limit.remaining == 0 {
                throw GitHubError.rateLimited(resetAt: limit.resetAt, api: Self.api(of: response, for: request))
            }
            let message = String(decoding: data, as: UTF8.self).lowercased()
            if response.statusCode == 429 || message.contains("secondary rate limit") {
                throw GitHubError.secondaryLimit(retryAfter: RateBudget.defaultRetryAfter)
            }
            throw GitHubError.http(response.statusCode)
        default: throw GitHubError.http(response.statusCode)
        }
    }

    /// Which limit a response counts against: its `x-ratelimit-resource`
    /// (`graphql`, or `core` and the other REST resources), else the URL.
    static func api(of response: HTTPURLResponse, for request: URLRequest) -> RateAPI {
        if let resource = response.value(forHTTPHeaderField: "x-ratelimit-resource")?.lowercased() {
            return resource == "graphql" ? .graphql : .rest
        }
        return request.url?.path == graphQLURL.path ? .graphql : .rest
    }
}

extension RateLimit {
    /// From the `x-ratelimit-*` headers every GitHub API response carries;
    /// `nil` when they're missing.
    init?(headers response: HTTPURLResponse) {
        func header(_ name: String) -> Int? {
            response.value(forHTTPHeaderField: name).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        }
        guard let limit = header("x-ratelimit-limit"),
              let remaining = header("x-ratelimit-remaining"),
              let reset = header("x-ratelimit-reset")
        else { return nil }
        self.init(
            limit: limit,
            remaining: remaining,
            used: header("x-ratelimit-used"),
            resetAt: Date(timeIntervalSince1970: TimeInterval(reset))
        )
    }
}
