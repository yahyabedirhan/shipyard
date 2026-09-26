import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

/// Sixty repositories, `yahyabedirhan/repo-00` to `repo-59`, each with one open
/// pull request; `repo-30` (the second batch's sixth) is gone.
private let repositories = (0..<60).map { String(format: "yahyabedirhan/repo-%02d", $0) }
private let missing = "yahyabedirhan/repo-30"

private let config = """
    [[projects]]
    name = "everything"
    repositories = [\(repositories.map { "\"\($0)\"" }.joined(separator: ", "))]

    """

/// The GraphQL answers for `slice` of the repositories, as one request.
private func answer(_ slice: ArraySlice<String>, cost: Int = 1, remaining: Int = 4990) -> StubHTTP.Answer {
    PullRequestsResponse.answer(
        slice.enumerated().map { offset, repository in
            var pullRequest = PullRequestsResponse.PullRequest(slice.startIndex + offset + 1)
            pullRequest.author = "someone"
            return PullRequestsResponse(repository, [pullRequest], missing: repository == missing)
        },
        cost: cost,
        remaining: remaining
    )
}

/// One answer per batch of 25: the batches a refresh of the sixty sends.
private func batches(costs: [Int] = [1, 1, 1], remaining: [Int] = [4990, 4990, 4990]) -> [StubHTTP.Answer] {
    [
        answer(repositories[0..<25], cost: costs[0], remaining: remaining[0]),
        answer(repositories[25..<50], cost: costs[1], remaining: remaining[1]),
        answer(repositories[50..<60], cost: costs[2], remaining: remaining[2]),
    ]
}

/// How many repositories a GraphQL request asked about.
private func aliases(in request: URLRequest) -> Int {
    request.bodyText.components(separatedBy: ": repository(owner: ").count - 1
}

@Suite("Refreshes fetch repositories in batches")
@MainActor
struct BatchedFetchTests {
    @Test("sixty repositories go out as three requests of at most 25, and the snapshot equals one request's")
    func sixtyRepositoriesInThreeBatches() async throws {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL(batches())
        await harness.shipyard.start()

        let requests = harness.graphQLRequests
        #expect(requests.map(aliases(in:)) == [25, 25, 10])
        #expect(requests[1].bodyText.contains(#""owner0":"yahyabedirhan""#))
        #expect(requests[1].bodyText.contains(#""name0":"repo-25""#))
        #expect(requests[2].bodyText.contains(#""name9":"repo-59""#))

        // The same projects, asked in a single request: the snapshot is the same.
        let stub = StubHTTP()
        stub.on("POST", GitHubClient.graphQLURL, answer(repositories[...], cost: 3))
        let client = GitHubClient(token: "gho_test", transport: stub, repositoriesPerRequest: 60)
        let configuration = try Configuration.decode(config).configuration
        let oneRequest = try await client.fetch(
            projects: configuration.projects.map(configuration.settings(for:)),
            at: Harness.now
        )
        #expect(stub.requests.count == 1)
        let snapshot = try #require(harness.shipyard.snapshot)
        #expect(snapshot == oneRequest)

        // Every repository's pull request is listed, and the one that's gone
        // (in the second batch) is that repository's error only.
        let items = try #require(snapshot.items["everything"])
        #expect(items.count == 59)
        #expect(Set(items.map(\.repository)) == Set(repositories).subtracting([missing]))
        #expect(snapshot.errors.keys.map(\.repository) == [missing])
        #expect(snapshot.errors[ItemSource(repository: missing, kind: .pullRequest)]?.kind == .notFound)
        #expect(snapshot.viewerLogin == "yabepa")
    }

    @Test("a few repositories still go out as one request")
    func fewRepositoriesInOneRequest() async throws {
        let harness = try Harness(stored: "gho_stored", config: """
            [[projects]]
            name = "few"
            repositories = ["yahyabedirhan/repo-00", "yahyabedirhan/repo-01"]

            """)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([answer(repositories[0..<2])])
        await harness.shipyard.start()

        #expect(harness.graphQLRequests.map(aliases(in:)) == [2])
        #expect(harness.shipyard.snapshot?.items["few"]?.count == 2)
    }

    @Test("the rate budget records the batches' total cost and the last batch's limit")
    func budgetRecordsTotalCost() async throws {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL(batches(costs: [2, 3, 1], remaining: [4998, 4995, 4994]))
        await harness.shipyard.start()

        #expect(harness.shipyard.budget.costs[.graphql] == [6])
        let graphql = try #require(harness.shipyard.snapshot?.rateLimits.graphql)
        #expect(graphql.cost == 6)
        #expect(graphql.remaining == 4994)
        #expect(harness.shipyard.menu.rateIndicator?.apis.first?.remaining == 4994)
    }

    @Test("an exhausted limit in a later batch fails the refresh as today: rows kept, paused until the reset")
    func rateLimitedInLaterBatch() async throws {
        let exhausted = try Harness.fixture("graphql-rate-limited.json", remaining: 0)
        let first = batches()
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL(first + [first[0], exhausted])
        await harness.shipyard.start()
        let before = harness.shipyard.menu

        await harness.timer.fire()

        let shipyard = harness.shipyard
        #expect(harness.graphQLRequests.count == 5)
        #expect(shipyard.fetchError == .rateLimited(resetAt: Harness.rateLimitReset, api: .graphql))
        #expect(shipyard.menu.sections == before.sections)
        #expect(shipyard.menu.refreshDelay == .paused(until: Harness.rateLimitReset, reason: .exhausted(.graphql)))
        #expect(shipyard.menu.rateIndicator?.level == .exhausted)
        // Only the successful refresh's cost is on record.
        #expect(shipyard.budget.costs[.graphql] == [3])
    }

    @Test("a network failure in a later batch fails the refresh as today: rows kept, the banner shown")
    func networkFailureInLaterBatch() async throws {
        let first = batches()
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL(first + [first[0], first[1], .failure()])
        await harness.shipyard.start()
        let before = harness.shipyard.menu

        await harness.timer.fire()

        let shipyard = harness.shipyard
        #expect(harness.graphQLRequests.count == 6)
        guard case .network = shipyard.fetchError else {
            Issue.record("expected a network failure, got \(String(describing: shipyard.fetchError))")
            return
        }
        #expect(shipyard.menu.sections == before.sections)
        #expect(shipyard.menu.bannerFetchError == shipyard.menu.fetchError)
        #expect(shipyard.menu.fetchError != nil)
        #expect(shipyard.menu.lastUpdated == before.lastUpdated)
        #expect(shipyard.budget.costs[.graphql] == [3])
    }
}
