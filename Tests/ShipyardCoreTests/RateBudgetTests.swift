import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let now = Harness.now
private let reset = now.addingTimeInterval(2520)
private let past = now.addingTimeInterval(-60)

/// A GraphQL limit of 5,000 with `remaining` left, costing `cost` this refresh.
private func graphql(_ remaining: Int = 4990, cost: Int? = 7, resetAt: Date = reset) -> RateLimits {
    RateLimits(graphql: RateLimit(limit: 5000, remaining: remaining, resetAt: resetAt, cost: cost))
}

/// A GraphQL limit with plenty left and a REST limit of 5,000 with `remaining` left.
private func withREST(_ remaining: Int = 4990, cost: Int? = 10, resetAt: Date = reset) -> RateLimits {
    var limits = graphql()
    limits.rest = RateLimit(limit: 5000, remaining: remaining, resetAt: resetAt, cost: cost)
    return limits
}

/// One row of the budget table: what was recorded, what's asked, what comes back.
struct BudgetCase: Sendable, CustomTestStringConvertible {
    var name: String
    var records: [RateLimits] = []
    var errors: [GitHubError] = []
    var configured: TimeInterval = 120
    var share = 10
    var at = now
    var expected: RefreshDelay

    var testDescription: String { name }

    func budget() -> RateBudget {
        var budget = RateBudget()
        for limits in records { budget.record(limits, at: now) }
        for error in errors { budget.record(error, at: now) }
        return budget
    }
}

private let delayCases: [BudgetCase] = [
    BudgetCase(name: "nothing known: the configured interval", expected: .configured(120)),
    BudgetCase(name: "5 repositories (7 points) fit 120 s at 10%", records: [graphql(cost: 7)], expected: .configured(120)),
    BudgetCase(name: "10 repositories (14 points) still fit", records: [graphql(cost: 14)], expected: .configured(120)),
    BudgetCase(
        name: "20 repositories (28 points) stretch to 201.6 s",
        records: [graphql(cost: 28)],
        expected: .stretched(201.6, api: .graphql, cost: 28)
    ),
    BudgetCase(
        name: "the cost is the average of recent refreshes",
        records: [graphql(cost: 10), graphql(cost: 30)],
        expected: .stretched(144, api: .graphql, cost: 20)
    ),
    BudgetCase(
        name: "only the last 5 refreshes count",
        records: [graphql(cost: 100)] + Array(repeating: graphql(cost: 7), count: 5),
        expected: .configured(120)
    ),
    BudgetCase(
        name: "a limit without a cost leaves the average alone",
        records: [graphql(cost: 28), graphql(cost: nil)],
        expected: .stretched(201.6, api: .graphql, cost: 28)
    ),
    BudgetCase(
        name: "a smaller share stretches sooner",
        records: [graphql(cost: 3)],
        share: 1,
        expected: .stretched(216, api: .graphql, cost: 3)
    ),
    BudgetCase(
        name: "a longer configured interval is kept",
        records: [graphql(cost: 28)],
        configured: 300,
        expected: .configured(300)
    ),
    BudgetCase(
        name: "each API is held to the share: REST stretches past GraphQL",
        records: [withREST(cost: 40)],
        expected: .stretched(288, api: .rest, cost: 40)
    ),
    BudgetCase(
        name: "refreshes without REST cost nothing on REST",
        records: [withREST(cost: 40), graphql(), graphql(), graphql(), graphql()],
        expected: .configured(120)
    ),
    BudgetCase(
        name: "under 20% on GraphQL: every 10 minutes",
        records: [graphql(900)],
        expected: .backedOff(600, api: .graphql)
    ),
    BudgetCase(name: "exactly 20% left isn't under 20%", records: [graphql(1000)], expected: .configured(120)),
    BudgetCase(
        name: "under 20% on REST backs off too",
        records: [withREST(500)],
        expected: .backedOff(600, api: .rest)
    ),
    BudgetCase(
        name: "backed off, but stretched further still",
        records: [graphql(900, cost: 200)],
        expected: .backedOff(1440, api: .graphql)
    ),
    BudgetCase(
        name: "a low limit whose window has reset doesn't back off",
        records: [graphql(900, resetAt: past)],
        expected: .configured(120)
    ),
    BudgetCase(
        name: "the refresh that spent the last point pauses until the reset",
        records: [graphql(0)],
        expected: .paused(until: reset, reason: .exhausted(.graphql))
    ),
    BudgetCase(
        name: "an exhausted limit whose reset has passed doesn't pause",
        records: [graphql(0, resetAt: past)],
        expected: .configured(120)
    ),
    BudgetCase(
        name: "GraphQL rate-limited: paused until the reset from the response",
        records: [graphql()],
        errors: [.rateLimited(resetAt: reset, api: .graphql)],
        expected: .paused(until: reset, reason: .exhausted(.graphql))
    ),
    BudgetCase(
        name: "REST rate-limited: paused until its reset",
        errors: [.rateLimited(resetAt: reset, api: .rest)],
        expected: .paused(until: reset, reason: .exhausted(.rest))
    ),
    BudgetCase(
        name: "a secondary limit waits retry-after",
        errors: [.secondaryLimit(retryAfter: 30)],
        expected: .paused(until: now.addingTimeInterval(30), reason: .secondaryLimit)
    ),
    BudgetCase(
        name: "a secondary limit without a usable retry-after waits a minute",
        errors: [.secondaryLimit(retryAfter: 0)],
        expected: .paused(until: now.addingTimeInterval(60), reason: .secondaryLimit)
    ),
    BudgetCase(
        name: "the later of two pauses wins",
        errors: [.rateLimited(resetAt: reset), .secondaryLimit(retryAfter: 30)],
        expected: .paused(until: reset, reason: .exhausted(.graphql))
    ),
    BudgetCase(
        name: "other errors change nothing",
        records: [graphql()],
        errors: [.http(502), .network("offline"), .malformed],
        expected: .configured(120)
    ),
    BudgetCase(
        name: "at the reset time the pause is over",
        errors: [.rateLimited(resetAt: reset)],
        at: reset,
        expected: .configured(120)
    ),
]

@Suite("Rate budget")
struct RateBudgetTests {
    @Test("the next delay", arguments: delayCases)
    func nextDelay(_ row: BudgetCase) {
        let delay = row.budget().nextDelay(configured: row.configured, sharePercent: row.share, at: row.at)
        #expect(delay == row.expected)
    }

    @Test("⌘R works unless paused", arguments: delayCases)
    func canRefresh(_ row: BudgetCase) {
        #expect(row.budget().canRefresh(at: row.at) == !row.expected.isPaused)
    }

    @Test("the timer waits the delay, or until the pause ends and never less than 0")
    func seconds() {
        #expect(RefreshDelay.configured(120).seconds(from: now) == 120)
        #expect(RefreshDelay.stretched(201.6, api: .graphql, cost: 28).seconds(from: now) == 201.6)
        #expect(RefreshDelay.backedOff(600, api: .rest).seconds(from: now) == 600)
        #expect(RefreshDelay.paused(until: reset, reason: .secondaryLimit).seconds(from: now) == 2520)
        #expect(RefreshDelay.paused(until: past, reason: .secondaryLimit).seconds(from: now) == 0)
    }

    // MARK: - Indicator

    struct IndicatorCase: Sendable, CustomTestStringConvertible {
        var name: String
        var records: [RateLimits] = []
        var errors: [GitHubError] = []
        var show: RateLimitDisplay = .always
        /// Remaining per API and the overall level; `nil` for no indicator.
        var expected: ([RateAPI: Int], RateLevel)?

        var testDescription: String { name }
    }

    static let indicatorCases: [IndicatorCase] = [
        IndicatorCase(name: "plenty left", records: [graphql(4850)], expected: ([.graphql: 4850], .normal)),
        IndicatorCase(name: "exactly 25% is normal", records: [graphql(1250)], expected: ([.graphql: 1250], .normal)),
        IndicatorCase(name: "under 25% is low", records: [graphql(1249)], expected: ([.graphql: 1249], .low)),
        IndicatorCase(name: "0 is exhausted", records: [graphql(0)], expected: ([.graphql: 0], .exhausted)),
        IndicatorCase(
            name: "a rate-limit error exhausts the API it names",
            records: [graphql(900)],
            errors: [.rateLimited(resetAt: reset, api: .graphql)],
            expected: ([.graphql: 0], .exhausted)
        ),
        IndicatorCase(
            name: "the worst API sets the level",
            records: [withREST(1000)],
            expected: ([.graphql: 4990, .rest: 1000], .low)
        ),
        IndicatorCase(
            name: "an exhausted limit whose window reset isn't red",
            records: [graphql(0, resetAt: past)],
            expected: ([.graphql: 0], .normal)
        ),
        IndicatorCase(name: "nothing known: no indicator", expected: nil),
        IndicatorCase(name: "never: no indicator", records: [graphql(0)], show: .never, expected: nil),
        IndicatorCase(name: "when-low hides a normal limit", records: [graphql(4850)], show: .whenLow, expected: nil),
        IndicatorCase(
            name: "when-low shows a low one",
            records: [graphql(900)],
            show: .whenLow,
            expected: ([.graphql: 900], .low)
        ),
    ]

    @Test("the indicator", arguments: indicatorCases)
    func indicator(_ row: IndicatorCase) {
        var budget = RateBudget()
        for limits in row.records { budget.record(limits, at: now) }
        for error in row.errors { budget.record(error, at: now) }

        let indicator = budget.indicator(show: row.show, at: now)

        guard let expected = row.expected else {
            #expect(indicator == nil)
            return
        }
        let (remaining, level) = expected
        let shown = indicator
        #expect(shown != nil)
        #expect(shown?.level == level)
        #expect(shown?.apis.map(\.api) == RateAPI.allCases.filter { remaining[$0] != nil })
        #expect(shown.map { Dictionary(uniqueKeysWithValues: $0.apis.map { ($0.api, $0.remaining) }) } == remaining)
        #expect(shown?.apis.allSatisfy { $0.limit == 5000 } == true)
    }

    @Test("each API's line has its reset time and its own level")
    func perAPI() {
        var budget = RateBudget()
        budget.record(withREST(1000, resetAt: reset.addingTimeInterval(600)), at: now)

        let indicator = budget.indicator(show: .always, at: now)

        #expect(indicator?.apis == [
            RateUsage(api: .graphql, remaining: 4990, limit: 5000, resetAt: reset, level: .normal),
            RateUsage(api: .rest, remaining: 1000, limit: 5000, resetAt: reset.addingTimeInterval(600), level: .low),
        ])
    }
}

// MARK: - Recognising a limit in a response

/// One response and the error `GitHubClient.send` reads from it.
struct ResponseCase: Sendable, CustomTestStringConvertible {
    var name: String
    var url: URL = GitHubClient.apiURL.appendingPathComponent("repos/yahyabedirhan/job-search/actions/runs")
    var status: Int
    var headers: [String: String] = [:]
    var body = ""
    var expected: GitHubError

    var testDescription: String { name }
}

private let exhaustedREST = Harness.rateLimitHeaders(remaining: 0, reset: reset, resource: "core")

private let responseCases: [ResponseCase] = [
    ResponseCase(
        name: "REST 403 with nothing remaining: rate-limited until x-ratelimit-reset",
        status: 403, headers: exhaustedREST, expected: .rateLimited(resetAt: reset, api: .rest)
    ),
    ResponseCase(
        name: "REST 429 with nothing remaining: rate-limited too",
        status: 429, headers: exhaustedREST, expected: .rateLimited(resetAt: reset, api: .rest)
    ),
    ResponseCase(
        name: "a 403 on /graphql with nothing remaining is GraphQL's limit",
        url: GitHubClient.graphQLURL,
        status: 403, headers: Harness.rateLimitHeaders(remaining: 0, reset: reset),
        expected: .rateLimited(resetAt: reset, api: .graphql)
    ),
    ResponseCase(
        name: "without x-ratelimit-resource, the URL says which API",
        status: 403,
        headers: ["x-ratelimit-limit": "5000", "x-ratelimit-remaining": "0", "x-ratelimit-reset": "1790340120"],
        expected: .rateLimited(resetAt: reset, api: .rest)
    ),
    ResponseCase(
        name: "retry-after is a secondary limit",
        status: 403, headers: ["retry-after": "30", "x-ratelimit-remaining": "4000"],
        expected: .secondaryLimit(retryAfter: 30)
    ),
    ResponseCase(
        name: "retry-after wins over the reset time",
        status: 429, headers: exhaustedREST.merging(["retry-after": "45"]) { $1 },
        expected: .secondaryLimit(retryAfter: 45)
    ),
    ResponseCase(name: "a bare 429 waits a minute", status: 429, expected: .secondaryLimit(retryAfter: 60)),
    ResponseCase(
        name: "a 403 saying 'secondary rate limit' waits a minute",
        status: 403,
        body: #"{"message":"You have exceeded a secondary rate limit. Please wait a few minutes before you try again."}"#,
        expected: .secondaryLimit(retryAfter: 60)
    ),
    ResponseCase(
        name: "any other 403 is a permission error",
        status: 403, headers: Harness.rateLimitHeaders(remaining: 4000, resource: "core"),
        body: #"{"message":"Resource not accessible by integration"}"#,
        expected: .http(403)
    ),
]

@Suite("Rate limits in responses")
struct RateLimitResponseTests {
    @Test("REST 403/429 and secondary limits are recognised, with the reset time from the response", arguments: responseCases)
    func recognised(_ row: ResponseCase) async {
        let stub = StubHTTP()
        stub.on("GET", row.url, .json(row.body, status: row.status, headers: row.headers))
        let client = GitHubClient(token: "gho_test", transport: stub)

        await #expect(throws: row.expected) {
            _ = try await client.send(URLRequest(url: row.url))
        }
    }

    @Test("GraphQL's 200 with x-ratelimit-remaining: 0 is exhaustion, whatever the error says")
    func graphQLExhausted() async throws {
        let stub = StubHTTP()
        stub.on(
            "POST", GitHubClient.graphQLURL,
            .json(#"{"errors":[{"message":"API rate limit exceeded"}]}"#, headers: Harness.rateLimitHeaders(remaining: 0))
        )
        let client = GitHubClient(token: "gho_test", transport: stub)
        let project = ProjectSettings(
            name: "job-search",
            repositories: ["yahyabedirhan/job-search"],
            pullRequests: .init(),
            issues: .init(),
            workflowRuns: .init(),
            notifications: []
        )

        await #expect(throws: GitHubError.rateLimited(resetAt: Harness.rateLimitReset, api: .graphql)) {
            _ = try await client.fetch(projects: [project], at: now)
        }
    }
}
