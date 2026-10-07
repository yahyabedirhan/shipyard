import Foundation
import ShipyardConfig
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

/// Twelve repositories, `yahyabedirhan/repo-00` to `repo-11`, each with one open
/// pull request; `repo-06` (the second batch's second) is gone.
private let repositories = (0..<12).map { String(format: "yahyabedirhan/repo-%02d", $0) }
private let missing = "yahyabedirhan/repo-06"

private let config = """
    [[projects]]
    slug = "everything"
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

/// One answer per batch of five: the batches a refresh of the twelve sends.
private func batches(costs: [Int] = [1, 1, 1], remaining: [Int] = [4990, 4990, 4990]) -> [StubHTTP.Answer] {
    [
        answer(repositories[0..<5], cost: costs[0], remaining: remaining[0]),
        answer(repositories[5..<10], cost: costs[1], remaining: remaining[1]),
        answer(repositories[10..<12], cost: costs[2], remaining: remaining[2]),
    ]
}

/// How many repositories a GraphQL request asked about.
private func aliases(in request: URLRequest) -> Int {
    request.bodyText.components(separatedBy: ": repository(owner: ").count - 1
}

@Suite("Refreshes fetch repositories in batches")
@MainActor
struct BatchedFetchTests {
    @Test("twelve repositories go out as three requests of at most five, and the snapshot equals one request's")
    func twelveRepositoriesInThreeBatches() async throws {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL(batches())
        await harness.shipyard.start()

        let requests = harness.graphQLRequests
        #expect(requests.map(aliases(in:)) == [5, 5, 2])
        #expect(requests[1].bodyText.contains(#""owner0":"yahyabedirhan""#))
        #expect(requests[1].bodyText.contains(#""name0":"repo-05""#))
        #expect(requests[2].bodyText.contains(#""name1":"repo-11""#))

        // The same projects, asked in a single request: the snapshot is the same.
        let stub = StubHTTP()
        stub.on("POST", GitHubClient.graphQLURL, answer(repositories[...], cost: 3))
        let client = GitHubClient(token: "gho_test", transport: stub, repositoriesPerRequest: 12)
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
        #expect(items.count == 11)
        #expect(Set(items.map(\.repository)) == Set(repositories).subtracting([missing]))
        #expect(snapshot.errors.keys.map(\.repository) == [missing])
        #expect(snapshot.errors[ItemSource(repository: missing, kind: .pullRequest)]?.kind == .notFound)
        #expect(snapshot.viewerLogin == "yabepa")
    }

    @Test("a few repositories still go out as one request")
    func fewRepositoriesInOneRequest() async throws {
        let harness = try Harness(stored: "gho_stored", config: """
            [[projects]]
            slug = "few"
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

    // MARK: - Answers cut short

    @Test("a batch GitHub cuts short (resource limits exceeded) is asked again in halves, and every item is listed")
    func cutShortBatchIsSplit() async throws {
        let harness = try await Harness.started(
            config: shop,
            graphQL: Harness.fixture("graphql-resource-limits.json"),
            PullRequestsResponse.answer([frontend]),
            PullRequestsResponse.answer([backend])
        )

        let requests = harness.graphQLRequests
        #expect(requests.map(aliases(in:)) == [2, 1, 1])
        // The review search goes with the first half.
        #expect(requests.map { $0.bodyText.contains("reviewSearch: search(") } == [true, true, false])
        #expect(requests[2].bodyText.contains(#""name0":"e-commerce-backend""#))
        let section = try #require(harness.section("e-commerce"))
        #expect(Set(section.rows.map(\.url)) == shopItems)
        #expect(section.errors.isEmpty)
        #expect(harness.shipyard.menu.fetchError == nil)
        // The cut-short answer cost points too.
        #expect(harness.shipyard.budget.costs[.graphql] == [11])
    }

    @Test(
        "a repository GitHub still answers only in part is its error, and its last items stay listed and known",
        arguments: [CutShort.resourceLimits, .entriesLeftOut]
    )
    func repositoryStillCutShort(_ answer: CutShort) async throws {
        let harness = try await Harness.started(config: shop, graphQL: PullRequestsResponse.answer([frontend, backend]))
        let before = try #require(harness.section("e-commerce"))
        #expect(Set(before.rows.map(\.url)) == shopItems)
        let requestsBefore = harness.graphQLRequests.count

        await harness.refresh(answering: try answer.answer())

        // Resource limits: both halves, then the first half's repository
        // and the review search apart, each cut short again. Entries left
        // out without an error aren't asked again.
        #expect(harness.graphQLRequests.count - requestsBefore == answer.requests)
        let after = try #require(harness.section("e-commerce"))
        #expect(after.rows == before.rows)
        #expect(after.errors.map(\.repository) == [frontendRepository, backendRepository])
        #expect(after.errors.allSatisfy { $0.kind == .incomplete })
        #expect(after.errors.first?.message == "\(frontendRepository): couldn't be read whole (\(answer.message))")
        #expect(harness.shipyard.menu.fetchError == nil)
        #expect(harness.shipyard.menu.lastUpdated == Harness.now.addingTimeInterval(120))
        // Nothing is recorded as gone, so nothing is announced.
        #expect(Set(shopItems.map(\.absoluteString)).isSubset(of: harness.shipyard.appStateStore.state.known.items.keys))
        #expect(harness.notifier.posted.isEmpty)
    }
}

// MARK: - Answers cut short

private let frontendRepository = "yahyabedirhan/e-commerce-frontend"
private let backendRepository = "yahyabedirhan/e-commerce-backend"

/// The project `graphql-resource-limits.json` answers for: repo0 is the
/// frontend, repo1 the backend, pull requests and issues shown.
private let shop = """
    [defaults.issues]
    show = true

    [[projects]]
    slug = "e-commerce"
    repositories = ["\(frontendRepository)", "\(backendRepository)"]

    """

private let frontend = PullRequestsResponse(frontendRepository, [PullRequestsResponse.PullRequest(14)], issues: [PullRequestsResponse.Issue(3)])
private let backend = PullRequestsResponse(backendRepository, [PullRequestsResponse.PullRequest(57)], issues: [PullRequestsResponse.Issue(8)])

/// The URLs of the shop's pull requests and issues, whole.
private let shopItems: Set<URL> = [
    URL(string: "https://github.com/\(frontendRepository)/pull/14")!,
    URL(string: "https://github.com/\(frontendRepository)/issues/3")!,
    URL(string: "https://github.com/\(backendRepository)/pull/57")!,
    URL(string: "https://github.com/\(backendRepository)/issues/8")!,
]

/// How GitHub answers a query it couldn't finish, for every request.
enum CutShort: CaseIterable, Sendable {
    /// `graphql-resource-limits.json`: lists of `null` entries and a
    /// `RESOURCE_LIMITS_EXCEEDED` error for each.
    case resourceLimits
    /// The same lists of `null` entries, without any error.
    case entriesLeftOut

    func answer() throws -> StubHTTP.Answer {
        var answer = try Harness.fixture("graphql-resource-limits.json")
        if self == .entriesLeftOut {
            var body = try #require(try JSONSerialization.jsonObject(with: answer.body) as? [String: Any])
            body["errors"] = nil
            answer.body = try JSONSerialization.data(withJSONObject: body)
        }
        return answer
    }

    /// The GraphQL requests a refresh of the shop sends.
    var requests: Int { self == .resourceLimits ? 5 : 1 }

    /// Why each repository isn't whole, as its error says.
    var message: String {
        self == .resourceLimits ? "Resource limits for this query exceeded." : "GitHub left entries out of its answer."
    }
}
