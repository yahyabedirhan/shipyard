import Foundation

/// What kind of thing an item is.
public enum ItemKind: String, Codable, Equatable, Hashable, Sendable {
    case pullRequest
    case issue
    case workflowRun
}

/// An item's semantic state. The app maps it to GitHub's colours: open
/// green, draft gray, merged purple, closed red; a workflow run running
/// amber, succeeded green, failed red.
public enum ItemState: String, Codable, Equatable, Hashable, Sendable {
    case open
    case draft
    case merged
    case closed
    /// A workflow run queued, waiting or in progress.
    case running
    /// A workflow run that finished well (GitHub's `success` or `neutral`).
    case succeeded
    /// A workflow run that finished badly (`failure`, `timed_out` or `startup_failure`).
    case failed

    /// Open and draft items are still open on GitHub; merged and closed ones
    /// aren't. A workflow run is never open: it runs, then it's finished.
    public var isOpen: Bool { self == .open || self == .draft }

    /// Not finished yet: an open (or draft) pull request or issue, or a
    /// running workflow run. The menu lists these first and ages them from
    /// when they started; finished ones count back from `closedAt`.
    public var isActive: Bool { isOpen || self == .running }
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
    /// A pull request's head commit checks. A workflow run's own result in
    /// the same terms (running pending, succeeded passed, failed failed), so
    /// `[attention] checks-failed` covers failed runs too.
    public var checks: ChecksState
    /// Whether an open pull request waits on the viewer's review, asked of
    /// them or of one of their teams: the review search found it.
    public var reviewRequestedFromViewer: Bool
    public var createdAt: Date
    public var updatedAt: Date
    /// When it was closed or merged, or a workflow run finished; `nil` while
    /// open or running.
    public var closedAt: Date?
    /// Comments plus reviews.
    public var activity: Int
    /// A workflow run's head branch; `nil` for pull requests and issues.
    public var branch: String?

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
        activity: Int = 0,
        branch: String? = nil
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
        self.branch = branch
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

    /// The review search failed: shown where review requests were needed,
    /// in place of a repository, as "review requests: <GitHub's message>".
    public static func reviewSearch(_ message: String) -> RepositoryError {
        RepositoryError(repository: "review requests", kind: .other, message: message)
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

/// Everything one refresh fetched: each project's items, the sources that
/// failed, and the rate limits GitHub reported.
public struct Snapshot: Equatable, Sendable {
    public var fetchedAt: Date
    /// Items per project name. A repository in two projects appears in both.
    public var items: [String: [Item]]
    /// Failures per source: a repository (`owner/name` as configured) and
    /// the kind of item that couldn't be fetched from it. A repository GitHub
    /// can't resolve fails every kind a project fetches from it; one whose
    /// workflow runs can't be read fails only its runs.
    public var errors: [ItemSource: RepositoryError]
    public var rateLimits: RateLimits
    /// The login the query ran as, when GitHub said.
    public var viewerLogin: String?
    /// The open pull requests waiting on the user's review, directly or
    /// through one of their teams (their IDs), from the review search. Every
    /// pull request's `reviewRequestedFromViewer` says the same.
    public var reviewRequested: Set<String>
    /// The pull requests the review search found, in any repository.
    public var searchPullRequests: [Item]
    /// Why the review search failed, when it did; `reviewRequested` is then
    /// the last set it found.
    public var reviewSearchError: RepositoryError?

    public init(
        fetchedAt: Date,
        items: [String: [Item]] = [:],
        errors: [ItemSource: RepositoryError] = [:],
        rateLimits: RateLimits = RateLimits(),
        viewerLogin: String? = nil,
        reviewRequested: Set<String> = [],
        searchPullRequests: [Item] = [],
        reviewSearchError: RepositoryError? = nil
    ) {
        self.fetchedAt = fetchedAt
        self.items = items
        self.errors = errors
        self.rateLimits = rateLimits
        self.viewerLogin = viewerLogin
        self.reviewRequested = reviewRequested
        self.searchPullRequests = searchPullRequests
        self.reviewSearchError = reviewSearchError
    }
}
