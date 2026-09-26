import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shopRepository = "yahyabedirhan/shop"
private let blogRepository = "yahyabedirhan/blog"

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

/// Two projects over the same repository: everything, and only what waits on the user.
private let shopAndQueue = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]
    issues = { show = true }

    [[projects]]
    name = "queue"
    repositories = ["yahyabedirhan/shop"]
    pull-requests = { review-requested = true }
    issues = { show = true }

    """

private typealias PR = PullRequestsResponse.PullRequest

private func pr(_ number: Int, author: String = "octocat") -> PR {
    var pullRequest = PR(number)
    pullRequest.author = author
    pullRequest.checks = nil
    return pullRequest
}

private func shopAnswer(
    _ pullRequests: PR...,
    issues: [PullRequestsResponse.Issue]? = nil,
    reviewSearch: PullRequestsResponse.ReviewSearch = .waiting
) -> StubHTTP.Answer {
    PullRequestsResponse.answer([PullRequestsResponse(shopRepository, pullRequests, issues: issues)], reviewSearch: reviewSearch)
}

@MainActor
private extension Harness {
    func refresh(answering answer: StubHTTP.Answer) async {
        graphQL([answer])
        clock.advance(by: 120)
        await shipyard.refresh()
    }

    /// The numbers of the rows `project` lists, in ascending order.
    func numbers(in project: String) -> [Int] {
        (section(project)?.rows.map(\.number) ?? []).sorted()
    }
}

@Suite("Review requests come from one search, teams included")
@MainActor
struct ReviewRequestTests {
    // MARK: - Teams count like the user

    @Test("a pull request asking for a review from the user's team needs attention, like a direct request")
    func teamRequestNeedsAttention() async throws {
        let config = "[attention]\nunseen = false\nchanged = false\n\n" + shop
        var team = pr(1)
        team.teamReviewRequests = ["shop-reviewers"]
        var direct = pr(2)
        direct.reviewRequests = ["yabepa"]
        let quiet = pr(3)
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(team, direct, quiet))

        let rows = try #require(harness.section("shop")?.rows)
        #expect(rows.filter(\.needsAttention).map(\.number).sorted() == [1, 2])
        #expect(rows.first { $0.number == 1 }?.item.reviewRequestedFromViewer == true)
        #expect(harness.shipyard.menu.attention.total == 2)
    }

    @Test("a review request from the user's team notifies pr.review_requested")
    func teamRequestNotifies() async throws {
        let config = shop + "notifications = [{ event = \"pr.review_requested\" }]\n"
        var change = pr(1)
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(change))
        #expect(harness.notifier.posted.isEmpty)

        change.teamReviewRequests = ["shop-reviewers"]
        await harness.refresh(answering: shopAnswer(change))

        #expect(harness.notifier.posted.map(\.title) == ["shop · Review requested on PR #1"])
    }

    // MARK: - review-requested = true

    @Test("review-requested = true lists only the project's pull requests waiting on the user")
    func reviewRequestedListsOnlyWaiting() async throws {
        var team = pr(1)
        team.teamReviewRequests = ["shop-reviewers"]
        var direct = pr(2)
        direct.reviewRequests = ["yabepa"]
        var someoneElse = pr(3)
        someoneElse.reviewRequests = ["someone-else"]
        var merged = pr(4)
        merged.state = "MERGED"
        merged.closedAt = "2026-09-25T11:00:00Z"
        merged.reviewRequests = ["yabepa"]
        // Waiting on the user, but in a repository neither project watches.
        var elsewhere = pr(5)
        elsewhere.reviewRequests = ["yabepa"]
        let search: PullRequestsResponse.ReviewSearch = .pullRequests([
            (shopRepository, team), (shopRepository, direct), ("someone/else", elsewhere),
        ])
        let issues = [PullRequestsResponse.Issue(7)]
        let harness = try await Harness.started(
            config: shopAndQueue,
            graphQL: shopAnswer(team, direct, someoneElse, merged, issues: issues, reviewSearch: search)
        )

        #expect(harness.numbers(in: "shop") == [1, 2, 3, 4, 7])
        // Issues aren't pull requests: the setting leaves them as they are.
        #expect(harness.numbers(in: "queue") == [1, 2, 7])
    }

    @Test("items review-requested leaves out are neither counted nor notified")
    func leftOutNeitherCountsNorNotifies() async throws {
        let config = """
            [[projects]]
            name = "queue"
            repositories = ["yahyabedirhan/shop"]
            pull-requests = { review-requested = true }
            notifications = [{ event = "pr.opened" }]

            """
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))
        var waiting = pr(3)
        waiting.reviewRequests = ["yabepa"]
        await harness.refresh(answering: shopAnswer(pr(1), pr(2), waiting))

        #expect(harness.numbers(in: "queue") == [3])
        #expect(harness.shipyard.menu.attention.total == 1)
        #expect(harness.notifier.posted.map(\.title) == ["queue · New PR #3"])
    }

    @Test("turning review-requested on applies at once, without a restart")
    func appliesLive() async throws {
        var waiting = pr(2)
        waiting.reviewRequests = ["yabepa"]
        let harness = try await Harness.started(config: shop, graphQL: shopAnswer(pr(1), waiting))
        #expect(harness.numbers(in: "shop") == [1, 2])

        try harness.writeConfig(shop + "pull-requests = { review-requested = true }\n")
        await harness.shipyard.reloadConfiguration()

        #expect(harness.numbers(in: "shop") == [2])
    }

    // MARK: - The query

    @Test("the search goes out once, in the first batch, and pull requests aren't asked for their review requests")
    func searchInFirstBatch() async throws {
        let repositories = (0..<30).map { String(format: "yahyabedirhan/repo-%02d", $0) }
        let config = """
            [[projects]]
            name = "everything"
            repositories = [\(repositories.map { "\"\($0)\"" }.joined(separator: ", "))]

            """
        let first = PullRequestsResponse.answer(repositories[0..<25].map { PullRequestsResponse($0, [pr(1)]) }, cost: 4)
        let second = PullRequestsResponse.answer(repositories[25..<30].map { PullRequestsResponse($0, [pr(1)]) }, cost: 1)
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([first, second])
        await harness.shipyard.start()

        let bodies = harness.graphQLRequests.map(\.bodyText)
        #expect(bodies.count == 2)
        #expect(bodies[0].contains("reviewSearch: search(type: ISSUE"))
        #expect(bodies[0].contains("is:pr is:open archived:false review-requested:@me"))
        #expect(bodies[0].contains("first: 100"))
        #expect(!bodies[1].contains("search("))
        #expect(bodies.allSatisfy { !$0.contains("reviewRequests") })
        // The search's cost is part of the first batch's, which the budget records.
        #expect(harness.shipyard.budget.costs[.graphql] == [5])
    }

    @Test("a project that shows no pull requests doesn't pay for the search")
    func noSearchWithoutPullRequests() async throws {
        let config = shop + "pull-requests = { show = false }\nissues = { show = true }\n"
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(issues: [PullRequestsResponse.Issue(1)]))

        #expect(harness.numbers(in: "shop") == [1])
        #expect(harness.graphQLRequests.allSatisfy { !$0.bodyText.contains("search(") })
    }

    // MARK: - A failed search

    @Test("a failed search shows an error row in review-requested projects and leaves the rest as it was")
    func failedSearch() async throws {
        var waiting = pr(2)
        waiting.reviewRequests = ["yabepa"]
        let harness = try await Harness.started(config: shopAndQueue, graphQL: shopAnswer(pr(1), waiting))
        #expect(harness.numbers(in: "queue") == [2])

        await harness.refresh(answering: shopAnswer(pr(1), waiting, reviewSearch: .failed("Something went wrong while executing your query.")))

        #expect(harness.shipyard.menu.fetchError == nil)
        #expect(harness.numbers(in: "shop") == [1, 2])
        #expect(harness.section("shop")?.errors.isEmpty == true)
        let errors = try #require(harness.section("queue")?.errors)
        #expect(errors.map(\.message) == ["review requests: Something went wrong while executing your query."])
        // The last requests found are kept, so the queue still lists them.
        #expect(harness.numbers(in: "queue") == [2])
    }

    @Test("a review request kept through a failed search doesn't notify again when the search is back")
    func failedSearchKeepsRequests() async throws {
        let config = shop + "notifications = [{ event = \"pr.review_requested\" }]\n"
        var waiting = pr(1)
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(waiting))
        waiting.teamReviewRequests = ["shop-reviewers"]
        await harness.refresh(answering: shopAnswer(waiting))
        #expect(harness.notifier.posted.count == 1)

        await harness.refresh(answering: shopAnswer(waiting, reviewSearch: .failed("timeout")))
        let row = try #require(harness.section("shop")?.rows.first)
        #expect(row.item.reviewRequestedFromViewer)
        #expect(harness.section("shop")?.errors.isEmpty == true)

        await harness.refresh(answering: shopAnswer(waiting))
        #expect(harness.notifier.posted.count == 1)
    }
}
