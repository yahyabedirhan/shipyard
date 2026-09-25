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

private let blog = """
    [[projects]]
    name = "blog"
    repositories = ["yahyabedirhan/blog"]

    """

private typealias PR = PullRequestsResponse.PullRequest

private func shopAnswer(_ pullRequests: PR...) -> StubHTTP.Answer {
    PullRequestsResponse(shopRepository, pullRequests).answer
}

/// One answer for shop (repo0) and blog (repo1).
private func bothAnswer(shop: [PR], blog: [PR], blogMissing: Bool = false) -> StubHTTP.Answer {
    PullRequestsResponse.answer([
        PullRequestsResponse(shopRepository, shop),
        PullRequestsResponse(blogRepository, blog, missing: blogMissing),
    ])
}

private func pr(_ number: Int, author: String = "yabepa", type: String = "User", title: String? = nil) -> PR {
    var pullRequest = PR(number)
    pullRequest.author = author
    pullRequest.authorType = type
    if let title { pullRequest.title = title }
    return pullRequest
}

@MainActor
private extension Harness {
    /// Refreshes, two minutes later, with GitHub answering `answer`.
    func refresh(answering answer: StubHTTP.Answer) async {
        graphQL([answer])
        clock.advance(by: 120)
        await shipyard.refresh()
    }

    /// What was posted: "project · headline" per notification.
    var titles: [String] { notifier.posted.map(\.title) }
}

@Suite("Notifications through the refresh pipeline")
@MainActor
struct NotificationTests {
    // MARK: - The default rule

    @Test("the first refresh is silent; a pull request opened after it is notified, by default from anyone")
    func defaultRule() async throws {
        let harness = try await Harness.started(config: shop, graphQL: shopAnswer(pr(1), pr(2, author: "octocat")))
        #expect(harness.notifier.posted.isEmpty)
        #expect(harness.shipyard.menu.attention.total == 2)

        await harness.refresh(answering: shopAnswer(pr(1), pr(2, author: "octocat"), pr(57, title: "Add order export")))

        let posted = try #require(harness.notifier.posted.first)
        #expect(harness.notifier.posted.count == 1)
        #expect(posted.event == .prOpened)
        #expect(posted.project == "shop")
        #expect(posted.headline == "New PR #57")
        #expect(posted.itemTitle == "Add order export")
        #expect(posted.itemURL == pr(57).url(in: shopRepository))
        #expect(posted.title == "shop · New PR #57")
        #expect(posted.body == "Add order export")

        // Anyone: another author's pull request is notified too.
        await harness.refresh(answering: shopAnswer(pr(1), pr(2, author: "octocat"), pr(57), pr(58, author: "octocat")))
        #expect(harness.titles == ["shop · New PR #57", "shop · New PR #58"])
    }

    @Test("an event is notified once: not again on the next refresh, nor after a relaunch")
    func noDuplicates() async throws {
        let harness = try await Harness.started(config: shop, graphQL: shopAnswer(pr(1)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2)))
        #expect(harness.titles == ["shop · New PR #2"])

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([shopAnswer(pr(1), pr(2))])
        await relaunched.shipyard.start()
        #expect(relaunched.notifier.posted.isEmpty)

        // Notified is apart from seen: marking it seen doesn't make it new again.
        let row = try #require(relaunched.section("shop")?.rows.first { $0.number == 2 })
        relaunched.shipyard.markSeen(row)
        await relaunched.refresh(answering: shopAnswer(pr(1), pr(2)))
        #expect(relaunched.notifier.posted.isEmpty)
    }

    @Test("a pull request opened while shipyard was quit is notified at the next launch")
    func openedWhileQuit() async throws {
        let harness = try await Harness.started(config: shop, graphQL: shopAnswer(pr(1)))

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([shopAnswer(pr(1), pr(2))])
        await relaunched.shipyard.start()

        #expect(relaunched.titles == ["shop · New PR #2"])
    }

    @Test("a pull request listed in two projects is notified once")
    func twoProjectsOnce() async throws {
        let config = shop + """
            [[projects]]
            name = "everything"
            repositories = ["yahyabedirhan/shop"]

            """
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2)))
        #expect(harness.titles == ["shop · New PR #2"])
    }

    // MARK: - Project overrides

    @Test("a project's own rules replace the defaults for it")
    func projectOverride() async throws {
        let config = shop + """
            [[projects]]
            name = "blog"
            repositories = ["yahyabedirhan/blog"]
            notifications = [{ event = "pr.merged" }]

            """
        var post = pr(10)
        let harness = try await Harness.started(config: config, graphQL: bothAnswer(shop: [pr(1)], blog: [post]))

        post.state = "MERGED"
        post.closedAt = "2026-09-25T11:50:00Z"
        await harness.refresh(answering: bothAnswer(shop: [pr(1), pr(2)], blog: [post, pr(11)]))

        // shop keeps the default (pr.opened); blog only hears about merges.
        #expect(harness.titles == ["shop · New PR #2", "blog · Merged PR #10"])
    }

    @Test("a project whose rules don't select the event lets a later project in the list notify it")
    func overrideAcrossProjects() async throws {
        let config = """
            [[projects]]
            name = "quiet"
            repositories = ["yahyabedirhan/shop"]
            notifications = []

            """ + shop
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2)))
        #expect(harness.titles == ["shop · New PR #2"])
    }

    // MARK: - Author filters

    struct AuthorCase: Sendable, CustomTestStringConvertible {
        var filter: String
        var expected: [Int]
        var testDescription: String { filter }
    }

    @Test("each author filter selects its authors", arguments: [
        AuthorCase(filter: "any", expected: [2, 3, 4, 5]),
        AuthorCase(filter: "me", expected: [2]),
        AuthorCase(filter: "others", expected: [3]),
        AuthorCase(filter: "bots", expected: [4, 5]),
    ])
    func authorFilter(_ author: AuthorCase) async throws {
        let config = """
            [[defaults.notifications]]
            event = "pr.opened"
            authors = "\(author.filter)"

            """ + shop
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))

        await harness.refresh(answering: shopAnswer(
            pr(1),
            pr(2, author: "yabepa"),
            pr(3, author: "octocat"),
            pr(4, author: "dependabot", type: "Bot"),
            pr(5, author: "renovate[bot]")
        ))

        #expect(harness.notifier.posted.map(\.headline) == author.expected.map { "New PR #\($0)" })
    }

    @Test("a hidden author is never notified")
    func hiddenAuthor() async throws {
        let config = "hide-authors = [\"dependabot[bot]\"]\n\n" + shop
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2, author: "dependabot", type: "Bot"), pr(3)))
        #expect(harness.titles == ["shop · New PR #3"])
    }

    // MARK: - First sight

    @Test("adding a project is silent for its existing pull requests, not for new ones")
    func addingAProject() async throws {
        let harness = try await Harness.started(config: shop, graphQL: shopAnswer(pr(1)))

        try harness.writeConfig(shop + blog)
        harness.graphQL([bothAnswer(shop: [pr(1), pr(2)], blog: [pr(10), pr(11)])])
        await harness.shipyard.reloadConfiguration()
        #expect(harness.titles == ["shop · New PR #2"])

        await harness.refresh(answering: bothAnswer(shop: [pr(1), pr(2)], blog: [pr(10), pr(11), pr(12)]))
        #expect(harness.titles == ["shop · New PR #2", "blog · New PR #12"])
    }

    @Test("a repository that can't be reached for a while doesn't announce its pull requests when it's back")
    func repositoryBack() async throws {
        let harness = try await Harness.started(config: shop + blog, graphQL: bothAnswer(shop: [pr(1)], blog: [pr(10)]))

        await harness.refresh(answering: bothAnswer(shop: [pr(1)], blog: [], blogMissing: true))
        #expect(harness.section("blog")?.errors.count == 1)
        await harness.refresh(answering: bothAnswer(shop: [pr(1)], blog: [pr(10), pr(11)]))

        #expect(harness.titles == ["blog · New PR #11"])
    }

    @Test("a state file from before notifications makes the next refresh silent")
    func stateFromBefore() async throws {
        let harness = try await Harness.started(config: shop, graphQL: shopAnswer(pr(1)))
        try Data(#"{"version": 1, "seen": {}, "collapsed": []}"#.utf8).write(to: harness.stateURL)

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([shopAnswer(pr(1), pr(2))])
        await relaunched.shipyard.start()
        #expect(relaunched.notifier.posted.isEmpty)

        await relaunched.refresh(answering: shopAnswer(pr(1), pr(2), pr(3)))
        #expect(relaunched.titles == ["shop · New PR #3"])
    }

    // MARK: - Every pull request event

    @Test("every pull request event is found and notified when a rule selects it")
    func everyEvent() async throws {
        let rules = EventKind.allCases.filter { $0.rawValue.hasPrefix("pr.") }
            .map { "{ event = \"\($0.rawValue)\" }" }
            .joined(separator: ", ")
        let config = shop + "notifications = [\(rules)]\n"
        var change = pr(1)
        change.author = "octocat"
        change.checks = "PENDING"
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(9)))

        let steps: [(String, (inout PR) -> Void)] = [
            ("New PR #1", { _ in }),
            ("New comment on PR #1", { $0.comments += 1 }),
            ("Review requested on PR #1", { $0.reviewRequests = ["yabepa"] }),
            ("Checks failed on PR #1", { $0.checks = "FAILURE" }),
            ("Closed PR #1", { $0.state = "CLOSED"; $0.closedAt = "2026-09-25T12:00:00Z" }),
            ("Reopened PR #1", { $0.state = "OPEN"; $0.closedAt = nil; $0.updatedAt = "2026-09-25T12:10:00Z" }),
            ("Merged PR #1", { $0.state = "MERGED"; $0.closedAt = "2026-09-25T12:20:00Z" }),
        ]
        for (headline, step) in steps {
            step(&change)
            await harness.refresh(answering: shopAnswer(pr(9), change))
            #expect(harness.notifier.posted.last?.headline == headline)
        }
        #expect(harness.notifier.posted.map(\.headline) == steps.map(\.0))
    }

    // MARK: - Clicking a notification

    @Test("clicking a notification opens the item and marks it seen")
    func click() async throws {
        let harness = try await Harness.started(config: shop, graphQL: shopAnswer(pr(1)))
        harness.shipyard.markSeen(try #require(harness.section("shop")?.rows.first))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2)))
        #expect(harness.shipyard.menu.attention.total == 1)

        let posted = try #require(harness.notifier.posted.first)
        harness.shipyard.openNotification(posted.itemURL)

        #expect(harness.opener.opened == [pr(2).url(in: shopRepository)])
        #expect(harness.shipyard.menu.attention.total == 0)
        #expect(harness.section("shop")?.rows.contains { $0.needsAttention } == false)
    }

    @Test("a notification clicked before the first refresh after a relaunch still marks its item seen")
    func clickBeforeRefresh() async throws {
        let harness = try await Harness.started(config: shop, graphQL: shopAnswer(pr(1)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2)))
        let posted = try #require(harness.notifier.posted.first)

        let relaunched = harness.relaunched()
        relaunched.shipyard.appStateStore.load()
        relaunched.shipyard.openNotification(posted.itemURL)

        #expect(relaunched.opener.opened == [posted.itemURL])
        #expect(relaunched.shipyard.appStateStore.state.attention.seen[posted.itemURL.absoluteString] != nil)
    }
}
