import Foundation

/// One of GitHub's two hourly limits shipyard spends.
public enum RateAPI: String, CaseIterable, Equatable, Hashable, Sendable {
    /// GraphQL points: pull requests and issues.
    case graphql
    /// REST requests (the `core` resource): workflow runs.
    case rest

    /// For the footer: "GraphQL", "REST".
    public var name: String {
        switch self {
        case .graphql: "GraphQL"
        case .rest: "REST"
        }
    }
}

/// How full one limit is, for the indicator's colour.
public enum RateLevel: Int, Comparable, Equatable, Sendable {
    case normal
    /// Under 25% remaining (amber).
    case low
    /// Nothing remaining until the reset time (red).
    case exhausted

    public static func < (lhs: RateLevel, rhs: RateLevel) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Why refreshing is paused.
public enum PauseReason: Equatable, Sendable {
    /// An hourly limit ran out; it comes back at the reset time.
    case exhausted(RateAPI)
    /// GitHub's secondary limit (too much too fast) asked shipyard to wait.
    case secondaryLimit
}

/// Refreshing stops until `until`, for `reason`.
public struct RatePause: Equatable, Sendable {
    public var until: Date
    public var reason: PauseReason

    public init(until: Date, reason: PauseReason) {
        self.until = until
        self.reason = reason
    }
}

/// When the next refresh runs, and why then. The panel says it when it
/// isn't simply the configured interval.
public enum RefreshDelay: Equatable, Sendable {
    /// The configured interval fits the budget.
    case configured(TimeInterval)
    /// The configured interval would spend more than the share of `api`'s
    /// hourly limit at the measured cost (average points or requests per
    /// refresh), so it's stretched to `seconds`.
    case stretched(TimeInterval, api: RateAPI, cost: Double)
    /// `api` has under 20% left (other tools are using it): every 10 minutes
    /// (or the stretched interval, when that's longer).
    case backedOff(TimeInterval, api: RateAPI)
    /// Nothing runs until `until`.
    case paused(until: Date, reason: PauseReason)

    /// How long to wait from `now`.
    public func seconds(from now: Date) -> TimeInterval {
        switch self {
        case .configured(let seconds), .stretched(let seconds, _, _), .backedOff(let seconds, _):
            seconds
        case .paused(let until, _):
            max(0, until.timeIntervalSince(now))
        }
    }

    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
}

/// One API's line in the footer indicator: `GraphQL 4,850 / 5,000 · resets 16:42`.
public struct RateUsage: Equatable, Sendable {
    public var api: RateAPI
    public var remaining: Int
    public var limit: Int
    public var resetAt: Date
    public var level: RateLevel

    public init(api: RateAPI, remaining: Int, limit: Int, resetAt: Date, level: RateLevel) {
        self.api = api
        self.remaining = remaining
        self.limit = limit
        self.resetAt = resetAt
        self.level = level
    }
}

/// What the footer draws for the rate limit.
public struct RateIndicator: Equatable, Sendable {
    /// One per API shipyard has heard from, GraphQL first.
    public var apis: [RateUsage]
    /// The worst of them: the indicator's colour.
    public var level: RateLevel

    public init(apis: [RateUsage]) {
        self.apis = apis
        level = apis.map(\.level).max() ?? .normal
    }
}

/// Keeps shipyard to its share of the user's GitHub limits, which their
/// agents share. Pure: it's told what each refresh reported and what time it
/// is, and answers when the next refresh may run.
///
/// It remembers the latest limit per API, the cost of the last few
/// refreshes per API, and a pause (an exhausted limit until its reset, or a
/// secondary limit's `retry-after`).
public struct RateBudget: Equatable, Sendable {
    /// How many recent refreshes the cost average covers.
    public static let costWindow = 5
    /// Below this share remaining, refreshing backs off.
    public static let backOffBelow = 0.20
    /// The back-off interval.
    public static let backOffInterval: TimeInterval = 600
    /// Below this share remaining, the indicator turns amber.
    public static let lowBelow = 0.25
    /// A secondary limit's wait when GitHub didn't say (or said 0 or less).
    public static let defaultRetryAfter: TimeInterval = 60

    /// The latest limit GitHub reported per API.
    public private(set) var limits: [RateAPI: RateLimit] = [:]
    /// The cost of the most recent refreshes per API, oldest first.
    public private(set) var costs: [RateAPI: [Int]] = [:]
    /// Until when refreshing is paused, and why; may lie in the past.
    public private(set) var pause: RatePause?

    public init() {}

    // MARK: - Recording

    /// What a successful refresh reported. An API the refresh didn't use
    /// (no limit reported, such as REST while runs are off) cost nothing;
    /// one that reported a limit without a cost keeps its average as it was.
    /// A limit reported at 0 pauses until its reset.
    public mutating func record(_ reported: RateLimits, at now: Date) {
        for api in RateAPI.allCases {
            guard let limit = reported[api] else {
                if costs[api] != nil { addCost(0, for: api) }
                continue
            }
            limits[api] = limit
            if let cost = limit.cost { addCost(cost, for: api) }
            if limit.remaining <= 0, limit.resetAt > now {
                pauseUntil(limit.resetAt, reason: .exhausted(api))
            }
        }
    }

    /// What a failed refresh reported: an exhausted limit pauses until its
    /// reset time, a secondary limit for its `retry-after`. Other errors
    /// change nothing.
    public mutating func record(_ error: GitHubError, at now: Date) {
        switch error {
        case .rateLimited(let resetAt, let api):
            if var limit = limits[api] {
                limit.remaining = 0
                limit.resetAt = resetAt
                limit.cost = nil
                limits[api] = limit
            }
            pauseUntil(resetAt, reason: .exhausted(api))
        case .secondaryLimit(let retryAfter):
            let wait = retryAfter > 0 ? retryAfter : Self.defaultRetryAfter
            pauseUntil(now.addingTimeInterval(wait), reason: .secondaryLimit)
        default:
            break
        }
    }

    private mutating func addCost(_ cost: Int, for api: RateAPI) {
        var recent = costs[api, default: []]
        recent.append(max(0, cost))
        if recent.count > Self.costWindow { recent.removeFirst(recent.count - Self.costWindow) }
        costs[api] = recent
    }

    /// Keeps the later of two pauses.
    private mutating func pauseUntil(_ until: Date, reason: PauseReason) {
        if let pause, pause.until >= until { return }
        pause = RatePause(until: until, reason: reason)
    }

    // MARK: - Answering

    /// Whether a refresh may run now; false only while paused. ⌘R asks this.
    public func canRefresh(at now: Date) -> Bool {
        activePause(at: now) == nil
    }

    /// The average cost of one refresh on `api` over the recent ones; `nil`
    /// before one was measured.
    public func averageCost(_ api: RateAPI) -> Double? {
        guard let recent = costs[api], !recent.isEmpty else { return nil }
        return Double(recent.reduce(0, +)) / Double(recent.count)
    }

    /// When the next refresh runs: paused until the pause ends; every 10
    /// minutes when an API has under 20% left; otherwise the configured
    /// interval, stretched so each API's measured cost stays within
    /// `sharePercent` of its hourly limit.
    public func nextDelay(configured: TimeInterval, sharePercent: Int, at now: Date) -> RefreshDelay {
        if let pause = activePause(at: now) {
            return .paused(until: pause.until, reason: pause.reason)
        }

        var delay = RefreshDelay.configured(configured)
        var longest = configured
        for api in RateAPI.allCases {
            guard let cost = averageCost(api), cost > 0, let limit = limits[api], limit.limit > 0 else { continue }
            let allowedPerHour = Double(limit.limit) * Double(max(1, sharePercent)) / 100
            let interval = 3600 * cost / allowedPerHour
            if interval > longest {
                longest = interval
                delay = .stretched(interval, api: api, cost: cost)
            }
        }

        if let low = RateAPI.allCases.first(where: { share(of: $0, at: now).map { $0 < Self.backOffBelow } ?? false }) {
            return .backedOff(max(Self.backOffInterval, longest), api: low)
        }
        return delay
    }

    /// What the footer draws, or `nil` when it shows nothing: `show = never`,
    /// `when-low` while every API is above 25%, or no limit heard of yet.
    public func indicator(show: RateLimitDisplay, at now: Date) -> RateIndicator? {
        guard show != .never else { return nil }
        let apis = RateAPI.allCases.compactMap { api -> RateUsage? in
            guard let limit = limits[api] else { return nil }
            return RateUsage(
                api: api,
                remaining: limit.remaining,
                limit: limit.limit,
                resetAt: limit.resetAt,
                level: level(of: api, at: now)
            )
        }
        guard !apis.isEmpty else { return nil }
        let indicator = RateIndicator(apis: apis)
        if show == .whenLow, indicator.level == .normal { return nil }
        return indicator
    }

    // MARK: - Helpers

    private func activePause(at now: Date) -> RatePause? {
        guard let pause, pause.until > now else { return nil }
        return pause
    }

    /// The share of `api`'s limit left, while its window lasts; `nil` when
    /// unknown or when the window has reset since.
    private func share(of api: RateAPI, at now: Date) -> Double? {
        guard let limit = limits[api], limit.limit > 0, limit.resetAt > now else { return nil }
        return Double(max(0, limit.remaining)) / Double(limit.limit)
    }

    private func level(of api: RateAPI, at now: Date) -> RateLevel {
        guard let share = share(of: api, at: now) else { return .normal }
        if share <= 0 { return .exhausted }
        return share < Self.lowBelow ? .low : .normal
    }
}

extension RateLimits {
    /// The limit reported for `api`.
    public subscript(api: RateAPI) -> RateLimit? {
        get {
            switch api {
            case .graphql: graphql
            case .rest: rest
            }
        }
        set {
            switch api {
            case .graphql: graphql = newValue
            case .rest: rest = newValue
            }
        }
    }
}
