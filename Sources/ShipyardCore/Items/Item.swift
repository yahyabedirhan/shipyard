import Foundation

/// What kind of thing an item is.
public enum ItemKind: String, Codable, Equatable, Hashable, Sendable {
    case pullRequest
    case issue
    case workflowRun
}

/// An item's semantic state. The app maps it to GitHub's colours: open
/// green, draft gray, merged purple, closed red.
public enum ItemState: String, Codable, Equatable, Hashable, Sendable {
    case open
    case draft
    case merged
    case closed

    /// Open and draft items are still open on GitHub; merged and closed ones aren't.
    public var isOpen: Bool { self == .open || self == .draft }
}

/// The head commit's combined check status on a pull request.
public enum ChecksState: String, Codable, Equatable, Hashable, Sendable {
    /// No checks ran, or none reported yet.
    case none
    case pending
    case passed
    case failed
}

/// Who wrote an item, as the notification rules' author filter sees it.
public enum AuthorKind: String, Equatable, Hashable, Sendable {
    /// The signed-in account (and so the user's agents, which act as them).
    case me
    /// A Bot account or a `[bot]` login.
    case bot
    /// Anyone else.
    case other
}

/// One pull request, issue or workflow run in a project's repositories.
public struct Item: Equatable, Hashable, Sendable, Identifiable {
    /// The item's URL, unique across pull requests, issues and runs.
    public var id: String { url.absoluteString }
    public var kind: ItemKind
    /// `owner/name`, as the configuration spells it.
    public var repository: String
    public var number: Int
    public var title: String
    public var url: URL
    /// The author's login; `ghost` for a deleted account.
    public var author: String
    public var authorKind: AuthorKind
    public var state: ItemState
    public var checks: ChecksState
    /// Whether the viewer is asked to review it.
    public var reviewRequestedFromViewer: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// When it was closed or merged; `nil` while open.
    public var closedAt: Date?
    /// Comments plus reviews.
    public var activity: Int

    public init(
        kind: ItemKind,
        repository: String,
        number: Int,
        title: String,
        url: URL,
        author: String,
        authorKind: AuthorKind,
        state: ItemState,
        checks: ChecksState = .none,
        reviewRequestedFromViewer: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        closedAt: Date? = nil,
        activity: Int = 0
    ) {
        self.kind = kind
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.author = author
        self.authorKind = authorKind
        self.state = state
        self.checks = checks
        self.reviewRequestedFromViewer = reviewRequestedFromViewer
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.closedAt = closedAt
        self.activity = activity
    }

    /// Everything whose change makes a seen item "changed": state, update
    /// time, checks, review request and activity.
    public var fingerprint: String {
        [
            state.rawValue,
            String(updatedAt.timeIntervalSince1970),
            checks.rawValue,
            String(reviewRequestedFromViewer),
            String(activity),
        ].joined(separator: "|")
    }
}

/// Why one repository couldn't be fetched. The rest of the refresh still counts.
public struct RepositoryError: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// The repository doesn't exist, or the token can't see it (GitHub
        /// answers the same for both).
        case notFound
        /// The token may not read it, for example an organisation enforcing SAML.
        case forbidden
        case other
    }

    public var repository: String
    public var kind: Kind
    /// GitHub's own message.
    public var message: String

    public init(repository: String, kind: Kind, message: String) {
        self.repository = repository
        self.kind = kind
        self.message = message
    }
}

/// One of GitHub's hourly limits, as the latest response reported it.
public struct RateLimit: Equatable, Sendable {
    public var limit: Int
    public var remaining: Int
    public var used: Int?
    public var resetAt: Date
    /// What the refresh that reported it cost on this limit, when known:
    /// GraphQL's `rateLimit.cost`; for REST, the requests that counted (a
    /// `304` doesn't). The rate budget averages it to stretch the interval.
    public var cost: Int?

    public init(limit: Int, remaining: Int, used: Int? = nil, resetAt: Date, cost: Int? = nil) {
        self.limit = limit
        self.remaining = remaining
        self.used = used
        self.resetAt = resetAt
        self.cost = cost
    }
}

/// The two limits shipyard spends: GraphQL points and REST requests.
public struct RateLimits: Equatable, Sendable {
    public var graphql: RateLimit?
    public var rest: RateLimit?

    public init(graphql: RateLimit? = nil, rest: RateLimit? = nil) {
        self.graphql = graphql
        self.rest = rest
    }
}

/// Everything one refresh fetched: each project's items, the repositories
/// that failed, and the rate limits GitHub reported.
public struct Snapshot: Equatable, Sendable {
    public var fetchedAt: Date
    /// Items per project name. A repository in two projects appears in both.
    public var items: [String: [Item]]
    /// Failures per repository (`owner/name` as configured).
    public var errors: [String: RepositoryError]
    public var rateLimits: RateLimits
    /// The login the query ran as, when GitHub said.
    public var viewerLogin: String?

    public init(
        fetchedAt: Date,
        items: [String: [Item]] = [:],
        errors: [String: RepositoryError] = [:],
        rateLimits: RateLimits = RateLimits(),
        viewerLogin: String? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.items = items
        self.errors = errors
        self.rateLimits = rateLimits
        self.viewerLogin = viewerLogin
    }
}
