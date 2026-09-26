import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private typealias PR = PullRequestsResponse.PullRequest

private func pr(_ number: Int, author: String = "octocat") -> PR {
    var pullRequest = PR(number)
    pullRequest.author = author
    pullRequest.checks = nil
    pullRequest.reviewRequests = ["yabepa"]
    return pullRequest
}

/// A project of pull requests waiting on the user's review anywhere.
private let reviews = """
    [[projects]]
    name = "reviews"
    repositories = ["anywhere"]
    pull-requests = { review-requested = true }
    notifications = [{ event = "pr.opened" }, { event = "pr.review_requested" }]

    """

/// The answer when the projects watch no repository: the viewer, the limit
/// and the review search's `found`, each in its repository.
private func searchAnswer(
    _ found: [(repository: String, pullRequest: PR)],
    total: Int? = nil,
    repositories: [PullRequestsResponse] = []
) -> StubHTTP.Answer {
    PullRequestsResponse.answer(repositories, reviewSearch: .pullRequests(found, total: total))
}

@MainActor
private extension Harness {
    func refresh(answering answer: StubHTTP.Answer) async {
        graphQL([answer])
        clock.advance(by: 120)
        await shipyard.refresh()
    }

    /// The rows `project` lists, as `owner/name#number`, in ascending order.
    func listed(in project: String) -> [String] {
        (section(project)?.rows.map { "\($0.repository)#\($0.number)" } ?? []).sorted()
    }
}

@Suite("The anywhere group lists pull requests waiting on the user's review in any repository")
@MainActor
struct AnywhereTests {
    @Test("anywhere lists the search's pull requests from any repository, named, and counts them")
    func listsFromAnyRepository() async throws {
        let harness = try await Harness.started(
            config: "[attention]\nchanged = false\n\n" + reviews,
            graphQL: searchAnswer([("someone/else", pr(5)), ("another/place", pr(9))])
        )

        let section = try #require(harness.section("reviews"))
        #expect(harness.listed(in: "reviews") == ["another/place#9", "someone/else#5"])
        // Rows come from many repositories, so each names its own.
        #expect(section.showsRepository)
        #expect(section.errors.isEmpty)
        #expect(section.notes.isEmpty)
        #expect(section.attentionCount == 2)
        #expect(harness.shipyard.menu.attention.total == 2)
        // It resolves to no repositories: one request, carrying the search.
        let body = try #require(harness.graphQLRequests.last?.httpBody).utf8
        #expect(body.contains("review-requested:@me"))
        #expect(!body.contains("repo0"))
    }

    @Test("a pull request the search newly finds notifies, as new and as a review request")
    func newRequestsNotify() async throws {
        let harness = try await Harness.started(config: reviews, graphQL: searchAnswer([("someone/else", pr(5))]))
        // The first refresh is a first sight: nothing notifies.
        #expect(harness.notifier.posted.isEmpty)

        await harness.refresh(answering: searchAnswer([("someone/else", pr(5)), ("another/place", pr(9))]))

        #expect(harness.notifier.posted.map(\.title) == ["reviews · New PR #9", "reviews · Review requested on PR #9"])
        #expect(harness.notifier.posted.map(\.itemURL) == Array(repeating: URL(string: "https://github.com/another/place/pull/9")!, count: 2))
    }

    @Test("what happens to a listed pull request afterwards notifies as anywhere else")
    func laterChangesNotify() async throws {
        let config = """
            [[projects]]
            name = "reviews"
            repositories = ["anywhere"]
            pull-requests = { review-requested = true }
            notifications = [{ event = "pr.commented" }]

            """
        var change = pr(5)
        let harness = try await Harness.started(config: config, graphQL: searchAnswer([("someone/else", change)]))
        change.comments = 1
        await harness.refresh(answering: searchAnswer([("someone/else", change)]))

        #expect(harness.notifier.posted.map(\.title) == ["reviews · New comment on PR #5"])
    }

    @Test("a pull request that leaves the search and comes back within the retention isn't new again")
    func comingBackIsNotNew() async throws {
        let harness = try await Harness.started(config: reviews, graphQL: searchAnswer([("someone/else", pr(5))]))
        await harness.refresh(answering: searchAnswer([]))
        #expect(harness.listed(in: "reviews").isEmpty)

        await harness.refresh(answering: searchAnswer([("someone/else", pr(5))]))

        #expect(harness.listed(in: "reviews") == ["someone/else#5"])
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("the project's other filters apply to what the search found")
    func otherFiltersApply() async throws {
        let config = """
            [[projects]]
            name = "reviews"
            repositories = ["anywhere"]
            pull-requests = { review-requested = true, drafts = false, authors = { hide = ["bots"] } }

            """
        var draft = pr(2)
        draft.isDraft = true
        let harness = try await Harness.started(config: config, graphQL: searchAnswer([
            ("o/a", pr(1)), ("o/a", draft), ("o/b", pr(3, author: "dependabot[bot]")),
        ]))

        #expect(harness.listed(in: "reviews") == ["o/a#1"])
        #expect(harness.shipyard.menu.attention.total == 1)
    }

    @Test("anywhere beside a repository lists both, each pull request once")
    func besideRepositories() async throws {
        let config = """
            [[projects]]
            name = "reviews"
            repositories = ["o/watched", "anywhere"]
            pull-requests = { review-requested = true }

            """
        let quiet = PR(2)
        let harness = try await Harness.started(config: config, graphQL: searchAnswer(
            [("o/watched", pr(1)), ("someone/else", pr(5))],
            repositories: [PullRequestsResponse("o/watched", [pr(1), quiet])]
        ))

        #expect(harness.listed(in: "reviews") == ["o/watched#1", "someone/else#5"])
    }

    @Test("more than one page of results shows a note in the section")
    func moreThanAPage() async throws {
        let found = (1...100).map { ("o/r", pr($0)) }
        let harness = try await Harness.started(config: reviews, graphQL: searchAnswer(found, total: 134))

        let section = try #require(harness.section("reviews"))
        #expect(section.rows.count == 100)
        #expect(section.notes == ["Only the first 100 of 134 review requests are listed"])
        #expect(harness.shipyard.menu.tabContent(for: .project("reviews")).notes == section.notes)
        #expect(harness.shipyard.menu.tabContent(for: .all).notes == section.notes)

        await harness.refresh(answering: searchAnswer(found, total: 100))
        #expect(harness.section("reviews")?.notes == [])
    }

    @Test("a failed search shows its error row, keeps the last pull requests, and notifies nothing")
    func failedSearch() async throws {
        let harness = try await Harness.started(config: reviews, graphQL: searchAnswer([("someone/else", pr(5))]))
        await harness.refresh(answering: PullRequestsResponse.answer([], reviewSearch: .failed("Something went wrong")))

        let section = try #require(harness.section("reviews"))
        #expect(harness.listed(in: "reviews") == ["someone/else#5"])
        #expect(section.errors.map(\.message) == ["review requests: Something went wrong"])

        await harness.refresh(answering: searchAnswer([("someone/else", pr(5))]))
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("a search failing on the first refresh keeps its first answer a first sight")
    func failedFirstSearch() async throws {
        let harness = try await Harness.started(
            config: reviews,
            graphQL: PullRequestsResponse.answer([], reviewSearch: .failed("Something went wrong"))
        )
        #expect(harness.listed(in: "reviews").isEmpty)

        await harness.refresh(answering: searchAnswer([("someone/else", pr(5))]))

        #expect(harness.listed(in: "reviews") == ["someone/else#5"])
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("an edit that misuses anywhere is refused and the last configuration keeps running")
    func misuseIsRefused() async throws {
        let harness = try await Harness.started(config: reviews, graphQL: searchAnswer([("someone/else", pr(5))]))
        try harness.writeConfig("""
            [[projects]]
            name = "reviews"
            repositories = ["anywhere"]
            issues = { show = true }
            """)
        await harness.shipyard.reloadConfiguration()

        #expect(harness.shipyard.configError?.issues == [ConfigIssue(
            line: 3,
            message: "`anywhere` needs `pull-requests = { review-requested = true }`, and lists no issues or runs"
        )])
        #expect(harness.listed(in: "reviews") == ["someone/else#5"])
    }
}

private extension Data {
    var utf8: String { String(decoding: self, as: UTF8.self) }
}
