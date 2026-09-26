import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shopRepository = "yahyabedirhan/shop"
private let blogRepository = "yahyabedirhan/blog"

/// Issues on for every project, closed ones kept 3 days (pull requests keep
/// the default 7). `graphql-issues.json` answers for it.
private let issuesEverywhere = """
    [defaults.issues]
    show = true
    closed-window-days = 3

    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private typealias PR = PullRequestsResponse.PullRequest
private typealias Issue = PullRequestsResponse.Issue

/// An open issue, by default updated at 10:<number>, so a higher number
/// is listed first.
private func issue(_ number: Int, author: String = "octocat", comments: Int = 0, updatedAt: String? = nil) -> Issue {
    var issue = Issue(number)
    issue.author = author
    issue.comments = comments
    issue.updatedAt = updatedAt ?? String(format: "2026-09-25T10:%02d:00Z", number)
    return issue
}

private func closed(_ issue: Issue, at closedAt: String = "2026-09-25T11:00:00Z") -> Issue {
    var issue = issue
    issue.state = "CLOSED"
    issue.closedAt = closedAt
    issue.updatedAt = closedAt
    return issue
}

private func shopAnswer(_ pullRequests: [PR] = [PR(1)], issues: [Issue]?) -> StubHTTP.Answer {
    PullRequestsResponse(shopRepository, pullRequests, issues: issues).answer
}

/// What `/graphql` was sent.
private struct QueryBody: Decodable {
    var query: String
    var variables: [String: String]
}

@MainActor
private extension Harness {
    /// Refreshes, two minutes later, with GitHub answering `answer`.
    func refresh(answering answer: StubHTTP.Answer) async {
        graphQL([answer])
        clock.advance(by: 120)
        await shipyard.refresh()
    }

    /// The query text of the latest GraphQL request.
    func lastQuery() throws -> String {
        let body = try #require(graphQLRequests.last?.httpBody)
        return try JSONDecoder().decode(QueryBody.self, from: body).query
    }

    var titles: [String] { notifier.posted.map(\.title) }
}

/// The part of `query` that asks about the repository aliased `repo<index>`.
private func selection(of index: Int, in query: String) -> String {
    let start = query.range(of: "repo\(index): repository(")!.lowerBound
    let rest = query[start...]
    let end = rest.range(of: "\n  }\n")!.upperBound
    return String(rest[..<end])
}

@Suite("Issues through the refresh pipeline")
@MainActor
struct IssuesTests {
    // MARK: - Showing

    @Test("issues follow the pull requests: open first, then closed within their own window; open or closed")
    func showing() async throws {
        let harness = try await Harness.started(config: issuesEverywhere, graphQL: Harness.fixture("graphql-issues.json"))

        let rows = try #require(harness.section("shop")?.rows)
        // PR #18 merged 5 days ago is inside the pull requests' 7 days; issue
        // #24 closed 4 days ago is outside the issues' 3.
        #expect(rows.map(\.number) == [20, 18, 31, 30, 29, 25])
        #expect(rows.map(\.kind) == [.pullRequest, .pullRequest, .issue, .issue, .issue, .issue])
        #expect(rows.suffix(4).map(\.state) == [.open, .open, .open, .closed])
        #expect(rows.suffix(4).allSatisfy { $0.checks == nil })

        let crash = rows[2]
        #expect(crash.title == "Checkout crashes on Safari")
        #expect(crash.author == "octocat")
        #expect(crash.authorKind == .other)
        #expect(crash.repository == shopRepository)
        #expect(crash.url == URL(string: "https://github.com/yahyabedirhan/shop/issues/31"))
        #expect(crash.since == date("2026-09-25T07:00:00Z"))
        #expect(crash.item.activity == 2)
        #expect(rows[3].authorKind == .me)
        #expect(rows[4].author == "renovate[bot]")
        #expect(rows[4].authorKind == .bot)
        #expect(rows[5].since == date("2026-09-24T12:00:00Z"))
    }

    @Test("a closed window of 0 hides closed issues; authors hides issues by their author")
    func closedWindowAndHiddenAuthors() async throws {
        let config = """
            [defaults.issues]
            show = true
            closed-window-days = 0
            authors = { hide = ["@renovate[bot]"] }

            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]

            """
        let harness = try await Harness.started(config: config, graphQL: Harness.fixture("graphql-issues.json"))
        #expect(harness.section("shop")?.rows.map(\.number) == [20, 18, 31, 30])
    }

    @Test("off by default: no issues are asked for or listed")
    func offByDefault() async throws {
        let config = """
            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]

            """
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(issues: nil))

        let query = try harness.lastQuery()
        #expect(!query.contains("issues("))
        #expect(!query.contains("IssueFields"))
        #expect(harness.section("shop")?.rows.map(\.kind) == [.pullRequest])
    }

    // MARK: - Per project

    @Test("issues are asked for only in the repositories of projects that show them")
    func onlyWhereShown() async throws {
        let config = """
            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]
            issues = { show = true, closed-window-days = 3 }

            [[projects]]
            name = "blog"
            repositories = ["yahyabedirhan/blog"]

            """
        let answer = PullRequestsResponse.answer([
            PullRequestsResponse(shopRepository, [PR(1)], issues: [issue(7)]),
            PullRequestsResponse(blogRepository, [PR(2)]),
        ])
        let harness = try await Harness.started(config: config, graphQL: answer)

        let query = try harness.lastQuery()
        let shop = selection(of: 0, in: query)
        #expect(shop.contains("openIssues: issues(states: OPEN, first: 50, orderBy: {field: UPDATED_AT, direction: DESC})"))
        #expect(shop.contains("closedIssues: issues(states: CLOSED, first: 20, orderBy: {field: UPDATED_AT, direction: DESC})"))
        #expect(!selection(of: 1, in: query).contains("issues("))
        #expect(query.contains("fragment IssueFields on Issue {"))

        #expect(harness.section("shop")?.rows.map(\.number) == [1, 7])
        #expect(harness.section("blog")?.rows.map(\.number) == [2])
    }

    @Test("a project can hide issues the defaults show, even for a repository another project shows them for")
    func hiddenPerProject() async throws {
        let config = """
            [defaults.issues]
            show = true

            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]

            [[projects]]
            name = "shop-code"
            repositories = ["yahyabedirhan/shop"]
            issues = { show = false }

            [[projects]]
            name = "blog"
            repositories = ["yahyabedirhan/blog"]
            issues = { show = false }

            """
        let answer = PullRequestsResponse.answer([
            PullRequestsResponse(shopRepository, [PR(1)], issues: [issue(7)]),
            PullRequestsResponse(blogRepository, [PR(2)]),
        ])
        let harness = try await Harness.started(config: config, graphQL: answer)

        let query = try harness.lastQuery()
        #expect(selection(of: 0, in: query).contains("issues("))
        #expect(!selection(of: 1, in: query).contains("issues("))
        #expect(harness.section("shop")?.rows.map(\.number) == [1, 7])
        #expect(harness.section("shop-code")?.rows.map(\.number) == [1])
        #expect(harness.section("blog")?.rows.map(\.number) == [2])
        // The issue counts once, in the one project that lists it.
        #expect(harness.shipyard.menu.attention == AttentionCounts(pullRequests: 2, issues: 1))
    }

    // MARK: - Attention

    @Test("open issues need attention when unseen or changed, closed never; they count per kind")
    func attention() async throws {
        let config = """
            [menu-bar]
            count = "per-kind"

            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]
            issues = { show = true }

            """
        let harness = try await Harness.started(
            config: config,
            graphQL: shopAnswer(issues: [issue(7), issue(8), closed(issue(6))])
        )

        let menu = harness.shipyard.menu
        #expect(menu.attention == AttentionCounts(pullRequests: 1, issues: 2))
        #expect(menu.menuBarLabel.text == "1 PR · 2 issues")
        #expect(harness.section("shop")?.attentionCount == 3)
        let rows = try #require(harness.section("shop")?.rows)
        #expect(rows.filter(\.needsAttention).map(\.number) == [1, 8, 7])

        // Clicking an issue opens it and marks it seen.
        let seven = try #require(rows.first { $0.number == 7 })
        harness.shipyard.open(seven)
        #expect(harness.opener.opened == [seven.url])
        #expect(harness.shipyard.menu.attention == AttentionCounts(pullRequests: 1, issues: 1))
        #expect(harness.shipyard.menu.menuBarLabel.text == "1 PR · 1 issue")

        // A comment changes it: it needs attention again. Issue #8 closing
        // takes it out of the count.
        await harness.refresh(answering: shopAnswer(issues: [
            issue(7, comments: 1, updatedAt: "2026-09-25T11:30:00Z"),
            closed(issue(8)),
            closed(issue(6)),
        ]))
        #expect(harness.shipyard.menu.attention == AttentionCounts(pullRequests: 1, issues: 1))
        #expect(harness.section("shop")?.rows.filter(\.needsAttention).map(\.number) == [1, 7])

        // Mark all seen covers issues too.
        harness.shipyard.markAllSeen()
        #expect(harness.shipyard.menu.attention.total == 0)
        #expect(harness.shipyard.menu.menuBarLabel.text == nil)
    }

    // MARK: - Notifications

    @Test("issue.opened, issue.closed and issue.commented are notified by rule, after a silent first sight")
    func notifications() async throws {
        let config = """
            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]
            issues = { show = true }
            notifications = [
              { event = "issue.opened" },
              { event = "issue.closed" },
              { event = "issue.commented", authors = ["others"] },
            ]

            """
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(issues: [issue(7)]))
        #expect(harness.notifier.posted.isEmpty)

        // A new issue is notified; a new pull request isn't (the project's
        // rules replace the default `pr.opened`).
        var crash = issue(9, comments: 0)
        crash.title = "Checkout crashes on Safari"
        await harness.refresh(answering: shopAnswer([PR(1), PR(2)], issues: [crash, issue(7)]))
        let posted = try #require(harness.notifier.posted.first)
        #expect(harness.titles == ["shop · New issue #9"])
        #expect(posted.event == .issueOpened)
        #expect(posted.body == "Checkout crashes on Safari")
        #expect(posted.itemURL == URL(string: "https://github.com/yahyabedirhan/shop/issues/9"))

        // Someone comments on #9 and #7 is closed.
        crash.comments = 1
        crash.updatedAt = "2026-09-25T11:00:00Z"
        await harness.refresh(answering: shopAnswer([PR(1), PR(2)], issues: [crash, closed(issue(7))]))
        #expect(Set(harness.titles.dropFirst()) == ["shop · New comment on issue #9", "shop · Closed issue #7"])

        // Nothing new: nothing posted again. A comment on an issue of mine
        // doesn't match `others`.
        let count = harness.notifier.posted.count
        await harness.refresh(answering: shopAnswer([PR(1), PR(2)], issues: [crash, closed(issue(7))]))
        await harness.refresh(answering: shopAnswer([PR(1), PR(2)], issues: [crash, closed(issue(7)), issue(10, author: "yabepa")]))
        #expect(harness.titles.last == "shop · New issue #10")
        await harness.refresh(answering: shopAnswer([PR(1), PR(2)], issues: [
            crash, closed(issue(7)), issue(10, author: "yabepa", comments: 1, updatedAt: "2026-09-25T11:30:00Z"),
        ]))
        #expect(harness.notifier.posted.count == count + 1)
    }

    @Test("turning issues on for a project lists them without a burst of notifications")
    func turningOnIsSilent() async throws {
        let off = """
            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]
            notifications = [{ event = "issue.opened" }]

            """
        let harness = try await Harness.started(config: off, graphQL: shopAnswer(issues: nil))
        #expect(harness.section("shop")?.rows.map(\.number) == [1])

        try harness.writeConfig(off.replacingOccurrences(of: "notifications", with: "issues = { show = true }\nnotifications"))
        harness.graphQL([shopAnswer(issues: [issue(7), issue(8)])])
        await harness.shipyard.reloadConfiguration()

        #expect(harness.section("shop")?.rows.map(\.number) == [1, 8, 7])
        #expect(harness.notifier.posted.isEmpty)

        await harness.refresh(answering: shopAnswer(issues: [issue(7), issue(8), issue(9)]))
        #expect(harness.titles == ["shop · New issue #9"])
    }
}
