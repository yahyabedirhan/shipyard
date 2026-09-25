import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

/// The projects `graphql-pull-requests.json` answers for.
private let projects = """
    [[projects]]
    name = "e-commerce"
    repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]

    [[projects]]
    name = "job-search"
    repositories = ["yahyabedirhan/job-search"]

    """

/// `graphql-pull-requests.json` (which costs 3 points) with `remaining` left.
private func pullRequests(remaining: Int = 4990, reset: Date = Harness.rateLimitReset) throws -> StubHTTP.Answer {
    try Harness.fixture("graphql-pull-requests.json", remaining: remaining, reset: reset)
}

@Suite("Rate budget through the refresh pipeline")
@MainActor
struct RateLimitTests {
    @Test("agents drain the limit: back off below 20%, pause at 0 until the reset, then resume")
    func drainPauseResume() async throws {
        let nextReset = Harness.rateLimitReset.addingTimeInterval(3600)
        let exhausted = try Harness.fixture("graphql-rate-limited.json", remaining: 0)
        let harness = try await Harness.started(
            config: projects,
            graphQL: pullRequests(remaining: 4990),
            pullRequests(remaining: 900),
            exhausted,
            pullRequests(remaining: 4997, reset: nextReset)
        )
        let shipyard = harness.shipyard

        // Plenty left: the configured interval, and the footer shows GraphQL's limit.
        #expect(harness.timer.armed == 120)
        #expect(shipyard.menu.refreshDelay == .configured(120))
        #expect(shipyard.menu.rateIndicator?.apis == [
            RateUsage(api: .graphql, remaining: 4990, limit: 5000, resetAt: Harness.rateLimitReset, level: .normal),
        ])

        // 900 of 5,000 is 18%: every 10 minutes, amber.
        harness.clock.advance(by: 120)
        await harness.timer.fire()
        #expect(harness.timer.armed == 600)
        #expect(shipyard.menu.refreshDelay == .backedOff(600, api: .graphql))
        #expect(shipyard.menu.rateIndicator?.level == .low)
        #expect(shipyard.menu.canRefreshNow)

        // Exhausted (a 200 with RATE_LIMITED): paused until 12:42, red, rows kept.
        harness.clock.advance(by: 600)
        let rows = shipyard.menu.sections
        await harness.timer.fire()
        let pausedFor = Harness.rateLimitReset.timeIntervalSince(harness.clock.now)
        #expect(shipyard.fetchError == .rateLimited(resetAt: Harness.rateLimitReset, api: .graphql))
        #expect(shipyard.menu.refreshDelay == .paused(until: Harness.rateLimitReset, reason: .exhausted(.graphql)))
        #expect(harness.timer.armed == pausedFor)
        #expect(shipyard.menu.rateIndicator?.level == .exhausted)
        #expect(shipyard.menu.rateIndicator?.apis.first?.remaining == 0)
        // The pause banner says why; the fetch error's banner doesn't repeat it.
        #expect(shipyard.menu.bannerFetchError == nil)
        #expect(shipyard.menu.sections == rows)
        #expect(shipyard.menu.lastUpdated == Harness.now.addingTimeInterval(120))
        #expect(!shipyard.menu.canRefreshNow)
        #expect(!shipyard.canRefreshNow)
        #expect(harness.graphQLRequests.count == 3)

        // ⌘R, opening the panel, waking: nothing is sent while paused.
        await shipyard.refresh()
        await shipyard.refresh()
        #expect(harness.graphQLRequests.count == 3)
        #expect(harness.timer.armed == pausedFor)

        // A timer that fires before the reset sends nothing and waits out the rest.
        harness.clock.advance(by: 1000)
        await harness.timer.fire()
        #expect(harness.graphQLRequests.count == 3)
        #expect(harness.timer.armed == pausedFor - 1000)

        // At the reset time: refreshes resume at the configured interval.
        harness.clock.set(Harness.rateLimitReset)
        await harness.timer.fire()
        #expect(harness.graphQLRequests.count == 4)
        #expect(shipyard.fetchError == nil)
        #expect(shipyard.menu.fetchError == nil)
        #expect(shipyard.menu.refreshDelay == .configured(120))
        #expect(shipyard.menu.canRefreshNow)
        #expect(shipyard.menu.rateIndicator?.apis.first?.remaining == 4997)
        #expect(shipyard.menu.rateIndicator?.level == .normal)
        #expect(harness.timer.armed == 120)
    }

    @Test("a refresh costing more than the share stretches the interval, and the model says why")
    func stretched() async throws {
        // 3 points a refresh at 1% of 5,000 an hour: one every 216 s.
        let harness = try await Harness.started(
            config: "[rate-limit]\nmax-share-percent = 1\n\n" + projects,
            graphQL: pullRequests()
        )

        #expect(harness.timer.armed == 216)
        #expect(harness.shipyard.menu.refreshDelay == .stretched(216, api: .graphql, cost: 3))
        #expect(harness.shipyard.menu.canRefreshNow)
    }

    @Test("the refresh that spends the last point shows its items, then pauses until the reset")
    func lastPoint() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests(remaining: 0))

        #expect(harness.section("job-search")?.rows.map(\.number) == [3])
        #expect(harness.shipyard.fetchError == nil)
        #expect(harness.shipyard.menu.refreshDelay == .paused(until: Harness.rateLimitReset, reason: .exhausted(.graphql)))
        #expect(harness.timer.armed == 2520)
    }

    @Test("a secondary limit waits retry-after, then resumes")
    func secondaryLimit() async throws {
        let harness = try await Harness.started(
            config: projects,
            graphQL: pullRequests(), .status(403, headers: ["retry-after": "30"]), pullRequests()
        )

        await harness.timer.fire()

        #expect(harness.shipyard.fetchError == .secondaryLimit(retryAfter: 30))
        #expect(harness.shipyard.menu.refreshDelay == .paused(until: Harness.now.addingTimeInterval(30), reason: .secondaryLimit))
        #expect(harness.timer.armed == 30)
        #expect(harness.shipyard.menu.bannerFetchError == nil)
        await harness.shipyard.refresh()
        #expect(harness.graphQLRequests.count == 2)

        harness.clock.advance(by: 30)
        await harness.timer.fire()

        #expect(harness.graphQLRequests.count == 3)
        #expect(harness.shipyard.fetchError == nil)
        #expect(harness.timer.armed == 120)
    }

    @Test("a 429 without retry-after waits a minute")
    func bare429() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests(), .status(429), pullRequests())

        await harness.timer.fire()

        #expect(harness.shipyard.fetchError == .secondaryLimit(retryAfter: 60))
        #expect(harness.timer.armed == 60)
    }

    @Test("[rate-limit] show decides whether the footer shows the indicator")
    func show() async throws {
        let never = try await Harness.started(config: "[rate-limit]\nshow = \"never\"\n\n" + projects, graphQL: pullRequests(remaining: 0))
        #expect(never.shipyard.menu.rateIndicator == nil)

        let whenLow = try await Harness.started(
            config: "[rate-limit]\nshow = \"when-low\"\n\n" + projects,
            graphQL: pullRequests(), pullRequests(remaining: 1000)
        )
        #expect(whenLow.shipyard.menu.rateIndicator == nil)
        await whenLow.timer.fire()
        #expect(whenLow.shipyard.menu.rateIndicator?.level == .low)
    }

    @Test("signing out forgets the budget")
    func signOut() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests(remaining: 0))
        #expect(!harness.shipyard.canRefreshNow)

        harness.shipyard.signOut()

        #expect(harness.shipyard.canRefreshNow)
        #expect(harness.shipyard.budget == RateBudget())
    }
}
