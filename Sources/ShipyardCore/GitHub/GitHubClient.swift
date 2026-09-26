import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The signed-in GitHub account, from `GET /user`: the panel's header shows
/// its avatar and `@login`, and opens its profile.
public struct Viewer: Equatable, Sendable, Decodable {
    public var login: String
    public var id: Int
    /// The account's display name (`name`); `nil` when it has none.
    public var name: String?
    /// The avatar's image (`avatar_url`); `nil` when GitHub gave none.
    public var avatarURL: URL?
    /// The account's page on GitHub (`html_url`), else `https://github.com/<login>`.
    public var profileURL: URL

    public init(login: String, id: Int, name: String? = nil, avatarURL: URL? = nil, profileURL: URL? = nil) {
        self.login = login
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.profileURL = profileURL ?? Self.profileURL(of: login)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            login: container.decode(String.self, forKey: .login),
            id: container.decode(Int.self, forKey: .id),
            name: try? container.decodeIfPresent(String.self, forKey: .name),
            // An odd link is left out rather than failing the sign-in.
            avatarURL: try? container.decodeIfPresent(URL.self, forKey: .avatarURL),
            profileURL: try? container.decodeIfPresent(URL.self, forKey: .profileURL)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case login, id, name
        case avatarURL = "avatar_url"
        case profileURL = "html_url"
    }

    private static func profileURL(of login: String) -> URL {
        URL(string: "https://github.com")!.appendingPathComponent(login)
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
    /// Each repository's last runs answer and its `ETag`, for as long as
    /// this client (one sign-in) lives.
    private let runCache = WorkflowRunCache()

    /// Repositories per GraphQL request; tests change it to compare batches
    /// with a single request.
    private let repositoriesPerRequest: Int

    public init(token: String, transport: any HTTPTransport) {
        self.init(token: token, transport: transport, repositoriesPerRequest: ProjectQuery.repositoriesPerRequest)
    }

    init(token: String, transport: any HTTPTransport, repositoriesPerRequest: Int) {
        self.token = token
        self.transport = transport
        self.repositoriesPerRequest = max(1, repositoriesPerRequest)
    }

    /// The account the token belongs to.
    public func viewer() async throws -> Viewer {
        let request = URLRequest(url: Self.apiURL.appendingPathComponent("user"))
        let (data, _) = try await send(request)
        guard let viewer = try? JSONDecoder().decode(Viewer.self, from: data) else { throw GitHubError.malformed }
        return viewer
    }

    /// Every project's pull requests, and its issues where it shows them,
    /// from GraphQL: each repository once, as an alias, in batches of
    /// `ProjectQuery.repositoriesPerRequest` per request, sent one after
    /// another, each with the viewer and the rate limit. A project gets only
    /// the kinds it shows, even when another project asked for more of a
    /// shared repository. A repository GitHub can't resolve becomes an error
    /// in the snapshot while the rest load; a batch that fails (a spent
    /// limit, a 401, a network failure) fails the fetch. The GraphQL limit
    /// comes from the last batch's response headers, with the batches' total
    /// `cost`.
    ///
    /// Where a project shows workflow runs, each of its repositories' runs
    /// then come from REST, one conditional request per repository, one after
    /// another (a `304` reuses the runs from before and doesn't count against
    /// the limit); the REST limit comes from their headers, with the requests
    /// that counted as its `cost`. A project keeps the runs on the branches
    /// its `branches` allows. A repository whose runs can't be read gets an
    /// error in the snapshot; a spent limit, a 401 or a network failure fails
    /// the fetch.
    public func fetch(projects: [ProjectSettings], at fetchedAt: Date) async throws -> Snapshot {
        let repositories = ProjectQuery.plan(projects)
        var parsed = ProjectQuery.Parsed()
        var headers: RateLimit?
        // With no repositories, one request still asks for the viewer and the limit.
        let starts = repositories.isEmpty ? [0] : Array(stride(from: 0, to: repositories.count, by: repositoriesPerRequest))
        for start in starts {
            let batch = Array(repositories[start..<min(start + repositoriesPerRequest, repositories.count)])
            let answer = try await query(batch, at: fetchedAt)
            parsed.add(answer.parsed)
            headers = answer.headers ?? headers
        }
        var graphql = headers ?? parsed.rateLimit
        graphql?.cost = parsed.rateLimit?.cost

        let runs = try await workflowRuns(
            of: repositories.filter { $0.runsWindowHours != nil && parsed.errors[$0.slug] == nil },
            viewer: parsed.viewerLogin,
            at: fetchedAt
        )

        var items: [String: [Item]] = [:]
        var errors: [ItemSource: RepositoryError] = [:]
        let slugs = Dictionary(repositories.map { ($0.slug.lowercased(), $0.slug) }, uniquingKeysWith: { first, _ in first })
        for project in projects {
            var projectItems: [Item] = []
            for repository in project.repositories {
                guard let slug = slugs[repository.lowercased()] else { continue }
                if let error = parsed.errors[slug] {
                    // Nothing of the repository could be fetched: every kind
                    // the project shows from it failed.
                    for kind in project.fetchedKinds {
                        errors[ItemSource(repository: repository, kind: kind)] =
                            RepositoryError(repository: repository, kind: error.kind, message: error.message)
                    }
                    continue
                }
                var found = (parsed.items[slug] ?? []).filter { project.shows($0.kind) }
                // Runs that couldn't be read leave the pull requests and
                // issues listed, with an error for the runs source only.
                if project.workflowRuns.show, let error = runs.errors[slug] {
                    errors[ItemSource(repository: repository, kind: .workflowRun)] =
                        RepositoryError(repository: repository, kind: error.kind, message: error.message)
                } else if project.workflowRuns.show {
                    found += WorkflowRuns.filter(
                        runs.items[slug] ?? [],
                        branches: project.workflowRuns.branches,
                        known: parsed.branches[slug]
                    )
                }
                projectItems += found.map { item in
                    var item = item
                    item.repository = repository
                    return item
                }
            }
            items[project.name] = projectItems
        }
        return Snapshot(
            fetchedAt: fetchedAt,
            items: items,
            errors: errors,
            rateLimits: RateLimits(graphql: graphql, rest: runs.rateLimit),
            viewerLogin: parsed.viewerLogin
        )
    }

    /// Asks GraphQL about one batch of repositories. Throws `.rateLimited`
    /// when the limit ran out, which GraphQL says with a 200.
    private func query(_ batch: [RepositoryRequest], at fetchedAt: Date) async throws -> (parsed: ProjectQuery.Parsed, headers: RateLimit?) {
        var request = URLRequest(url: Self.graphQLURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = ProjectQuery.body(batch)
        let (data, response) = try await send(request)

        let headers = RateLimit(headers: response)
        // GraphQL's exhausted limit is a 200: an error typed RATE_LIMITED,
        // or at least `x-ratelimit-remaining: 0` with no data.
        let resetAt = headers?.resetAt ?? fetchedAt.addingTimeInterval(60)
        let parsed: ProjectQuery.Parsed
        do {
            parsed = try ProjectQuery.parse(data, repositories: batch)
        } catch GitHubError.graphQL(let message) {
            if headers?.remaining == 0 { throw GitHubError.rateLimited(resetAt: resetAt, api: .graphql) }
            throw GitHubError.graphQL(message)
        }
        if parsed.rateLimited { throw GitHubError.rateLimited(resetAt: resetAt, api: .graphql) }
        return (parsed, headers)
    }

    /// What the runs requests of one refresh found.
    private struct RunsFetch {
        /// Per repository slug, before any project's branch filter.
        var items: [String: [Item]] = [:]
        var errors: [String: RepositoryError] = [:]
        /// The latest REST limit reported, with the requests that counted as its cost.
        var rateLimit: RateLimit?
    }

    /// Asks for each repository's runs in turn, conditionally: a `304`
    /// reuses the runs of the last answer to the same URL.
    private func workflowRuns(of repositories: [RepositoryRequest], viewer: String?, at now: Date) async throws -> RunsFetch {
        var fetch = RunsFetch()
        var counted = 0
        var latest: RateLimit?
        for repository in repositories {
            let url = WorkflowRuns.url(
                for: repository.slug,
                since: WorkflowRuns.since(windowHours: repository.runsWindowHours ?? 0, at: now)
            )
            var request = URLRequest(url: url)
            // The ETag is ours to send; a cache in between would answer for it.
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let cached = runCache.entry(repository.slug, url: url)
            if let cached { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }
            do {
                let (data, response) = try await send(request, acceptingNotModified: cached != nil)
                if let limit = RateLimit(headers: response) { latest = limit }
                if response.statusCode == 304, let cached {
                    fetch.items[repository.slug] = cached.runs
                    continue
                }
                counted += 1
                let runs = try WorkflowRuns.parse(data, repository: repository.slug, viewer: viewer)
                fetch.items[repository.slug] = runs
                let etag = response.value(forHTTPHeaderField: "ETag")
                runCache.store(etag.map { WorkflowRunCache.Entry(url: url, etag: $0, runs: runs) }, for: repository.slug)
            } catch GitHubError.http(let status) {
                counted += 1
                fetch.errors[repository.slug] = RepositoryError(
                    repository: repository.slug,
                    kind: status == 403 ? .forbidden : .other,
                    message: "workflow runs: HTTP \(status)"
                )
            } catch GitHubError.malformed {
                fetch.errors[repository.slug] = RepositoryError(
                    repository: repository.slug,
                    kind: .other,
                    message: "workflow runs: GitHub's answer couldn't be read"
                )
            }
        }
        if var latest {
            latest.cost = counted
            fetch.rateLimit = latest
        }
        return fetch
    }

    /// Sends `request` with the token and GitHub's headers. A 401 throws
    /// `.unauthorized`; other non-2xx statuses throw `.http`, or `.rateLimited` /
    /// `.secondaryLimit` for a 403 or 429 that says a limit was hit; transport
    /// failures throw `.network`; cancellation throws `CancellationError`.
    /// With `acceptingNotModified`, a `304` (the answer to `If-None-Match`)
    /// returns like a success.
    func send(_ request: URLRequest, acceptingNotModified: Bool = false) async throws -> (Data, HTTPURLResponse) {
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
        case 304 where acceptingNotModified: return (data, response)
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
