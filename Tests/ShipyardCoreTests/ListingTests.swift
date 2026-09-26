import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shopRepository = "yahyabedirhan/shop"
private let blogRepository = "yahyabedirhan/blog"

private typealias PR = PullRequestsResponse.PullRequest

private func pr(_ number: Int, author: String = "yabepa", type: String = "User", draft: Bool = false) -> PR {
    var pullRequest = PR(number)
    pullRequest.author = author
    pullRequest.authorType = type
    pullRequest.isDraft = draft
    return pullRequest
}

private func shopAnswer(_ pullRequests: PR...) -> StubHTTP.Answer {
    PullRequestsResponse(shopRepository, pullRequests).answer
}

/// One answer for shop (repo0) and blog (repo1).
private func bothAnswer(shop: [PR], blog: [PR]) -> StubHTTP.Answer {
    PullRequestsResponse.answer([PullRequestsResponse(shopRepository, shop), PullRequestsResponse(blogRepository, blog)])
}

/// A pull request each from the viewer (yabepa), someone else, a Bot
/// account and a `[bot]` login.
private let everyAuthor = [
    pr(1, author: "yabepa"),
    pr(2, author: "octocat"),
    pr(3, author: "dependabot", type: "Bot"),
    pr(4, author: "renovate[bot]"),
]

/// A shop project whose pull requests take `authors`.
private func shop(authors: String? = nil) -> String {
    """
    [[projects]]
    name = "shop"
    repositories = ["\(shopRepository)"]
    \(authors.map { "pull-requests = { authors = \($0) }" } ?? "")

    """
}

@MainActor
private extension Harness {
    /// Refreshes, two minutes later, with GitHub answering `answer`.
    func refresh(answering answer: StubHTTP.Answer) async {
        graphQL([answer])
        clock.advance(by: 120)
        await shipyard.refresh()
    }

    /// Replaces the configuration and follows it, GitHub answering `answer`.
    func reconfigure(_ config: String, answering answer: StubHTTP.Answer) async throws {
        try writeConfig(config)
        graphQL([answer])
        clock.advance(by: 120)
        await shipyard.reloadConfiguration()
    }

    func numbers(_ project: String) -> [Int]? { section(project)?.rows.map(\.number) }
    var headlines: [String] { notifier.posted.map(\.title) }
}

@Suite("Listing: what a project has")
@MainActor
struct ListingTests {
    // MARK: - Whose items

    @Test("by default a project lists everyone's items, as before authors existed")
    func everyoneByDefault() async throws {
        let harness = try await Harness.started(config: shop(), graphQL: shopAnswer(everyAuthor[0], everyAuthor[1], everyAuthor[2], everyAuthor[3]))
        #expect(harness.numbers("shop")?.sorted() == [1, 2, 3, 4])
        #expect(harness.shipyard.menu.attention.total == 4)
        #expect(harness.shipyard.configWarnings.isEmpty)
    }

    @Test("hide me and bots: only others' items are listed, counted and notified")
    func hideMeAndBots() async throws {
        let config = shop(authors: #"{ hide = ["me", "bots"] }"#)
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(everyAuthor[0], everyAuthor[1], everyAuthor[2], everyAuthor[3]))

        #expect(harness.numbers("shop") == [2])
        #expect(harness.section("shop")?.attentionCount == 1)
        #expect(harness.shipyard.menu.attention.total == 1)
        #expect(harness.shipyard.menu.menuBarLabel == .total(1))

        await harness.refresh(answering: shopAnswer(
            everyAuthor[0], everyAuthor[1], everyAuthor[2], everyAuthor[3],
            pr(5, author: "yabepa"), pr(6, author: "someone"), pr(7, author: "github-actions", type: "Bot")
        ))
        #expect(harness.headlines == ["shop · New PR #6"])
        #expect(harness.numbers("shop")?.sorted() == [2, 6])
        #expect(harness.shipyard.menu.attention.total == 2)
    }

    @Test("show one login: only that login's items are listed")
    func showOneLogin() async throws {
        let config = shop(authors: #"{ show = ["@dependabot[bot]"] }"#)
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(everyAuthor[0], everyAuthor[1], everyAuthor[2], everyAuthor[3]))
        #expect(harness.numbers("shop") == [3])
        #expect(harness.shipyard.menu.attention.total == 1)
    }

    @Test("show minus hide: hide wins where both match")
    func showMinusHide() async throws {
        let config = shop(authors: #"{ show = ["bots"], hide = ["@renovate[bot]"] }"#)
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(everyAuthor[0], everyAuthor[1], everyAuthor[2], everyAuthor[3]))
        #expect(harness.numbers("shop") == [3])
    }

    @Test("a project's authors merge onto the defaults key by key")
    func defaultsAndOverrides() async throws {
        let config = """
            [defaults.pull-requests]
            authors = { hide = ["bots"] }

            """ + shop(authors: #"{ show = ["others", "bots"] }"#)
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(everyAuthor[0], everyAuthor[1], everyAuthor[2], everyAuthor[3]))
        // The project's show, the defaults' hide.
        #expect(harness.numbers("shop") == [2])
    }

    @Test("the tabs layout's All tab and a project's tab list what the filters leave")
    func tabsToo() async throws {
        let config = "[menu]\nlayout = \"tabs\"\n\n" + shop(authors: #"{ hide = ["me", "bots"] }"#)
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(everyAuthor[0], everyAuthor[1], everyAuthor[2], everyAuthor[3]))
        let menu = harness.shipyard.menu
        #expect(menu.tabContent(for: .all).groups.flatMap(\.rows).map(\.number) == [2])
        #expect(menu.tabContent(for: .project("shop")).groups.flatMap(\.rows).map(\.number) == [2])
        #expect(menu.attentionCount(for: .all) == 1)
    }

    // MARK: - Notifications read the listing

    @Test("an item hidden by a filter, then shown by a filter change, doesn't notify")
    func looseningDoesNotNotify() async throws {
        let harness = try await Harness.started(config: shop(authors: #"{ hide = ["bots"] }"#), graphQL: shopAnswer(pr(1)))

        // Opened while hidden: known, not listed, not notified.
        await harness.refresh(answering: shopAnswer(pr(1), pr(2, author: "dependabot", type: "Bot")))
        #expect(harness.numbers("shop") == [1])
        #expect(harness.headlines.isEmpty)

        // Shown now: listed, and still not notified as new.
        try await harness.reconfigure(shop(), answering: shopAnswer(pr(1), pr(2, author: "dependabot", type: "Bot")))
        #expect(harness.numbers("shop")?.sorted() == [1, 2])
        #expect(harness.headlines.isEmpty)

        // A pull request opened after the change notifies as usual.
        await harness.refresh(answering: shopAnswer(pr(1), pr(2, author: "dependabot", type: "Bot"), pr(3, author: "dependabot", type: "Bot")))
        #expect(harness.headlines == ["shop · New PR #3"])
    }

    @Test("a rule's authors narrow what's listed; they can't reach an item the listing leaves out")
    func ruleOnlyNarrows() async throws {
        let config = """
            [[projects]]
            name = "shop"
            repositories = ["\(shopRepository)"]
            pull-requests = { authors = { hide = ["bots"] } }
            notifications = [{ event = "pr.opened", authors = ["bots", "others"] }]

            """
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2, author: "dependabot", type: "Bot"), pr(3, author: "octocat"), pr(4)))
        #expect(harness.headlines == ["shop · New PR #3"])
    }

    @Test("an item one project hides is notified for another project that lists it")
    func anotherProjectLists() async throws {
        let config = """
            [[projects]]
            name = "quiet"
            repositories = ["\(shopRepository)"]
            pull-requests = { authors = { hide = ["bots"] } }

            [[projects]]
            name = "everything"
            repositories = ["\(shopRepository)"]

            """
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2, author: "dependabot", type: "Bot")))
        #expect(harness.headlines == ["everything · New PR #2"])
    }

    @Test("a draft isn't notified where the project hides drafts")
    func hiddenDrafts() async throws {
        let config = """
            [[projects]]
            name = "shop"
            repositories = ["\(shopRepository)"]
            pull-requests = { drafts = false }

            """
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2, draft: true), pr(3)))
        #expect(harness.headlines == ["shop · New PR #3"])
    }

    @Test("a closed window of 0 leaves merged pull requests out, so pr.merged isn't notified there")
    func windowDecidesToo() async throws {
        let config = """
            [[defaults.notifications]]
            event = "pr.merged"

            [[projects]]
            name = "open only"
            repositories = ["\(shopRepository)"]
            pull-requests = { closed-window-days = 0 }

            [[projects]]
            name = "with history"
            repositories = ["\(shopRepository)"]

            """
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))
        var merged = pr(1)
        merged.state = "MERGED"
        merged.closedAt = "2026-09-25T11:59:00Z"
        await harness.refresh(answering: shopAnswer(merged))
        #expect(harness.headlines == ["with history · Merged PR #1"])
    }

    // MARK: - Which states

    @Test("states = [\"open\"] lists no merged or closed pull requests, and doesn't notify pr.merged there; the default lists all three")
    func onlyOpenPullRequests() async throws {
        let config = """
            [[defaults.notifications]]
            event = "pr.merged"

            [[defaults.notifications]]
            event = "pr.closed"

            [[projects]]
            name = "open only"
            repositories = ["\(shopRepository)"]
            pull-requests = { states = ["open"] }

            [[projects]]
            name = "everything"
            repositories = ["\(shopRepository)"]

            """
        var merged = pr(2)
        merged.state = "MERGED"
        merged.closedAt = "2026-09-25T11:00:00Z"
        var closed = pr(3)
        closed.state = "CLOSED"
        closed.closedAt = "2026-09-25T11:00:00Z"
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1), merged, closed, pr(4), pr(5)))
        #expect(harness.numbers("open only")?.sorted() == [1, 4, 5])
        #expect(harness.numbers("everything")?.sorted() == [1, 2, 3, 4, 5])
        #expect(harness.section("open only")?.attentionCount == 3)

        // #4 is merged and #5 closed: notified only where merged and closed pull requests are listed.
        var mergedNow = pr(4)
        mergedNow.state = "MERGED"
        mergedNow.closedAt = "2026-09-25T12:01:00Z"
        var closedNow = pr(5)
        closedNow.state = "CLOSED"
        closedNow.closedAt = "2026-09-25T12:01:00Z"
        await harness.refresh(answering: shopAnswer(pr(1), merged, closed, mergedNow, closedNow))
        #expect(harness.headlines.sorted() == ["everything · Closed PR #5", "everything · Merged PR #4"])
        #expect(harness.numbers("open only") == [1])
    }

    // MARK: - Old files

    @Test("an old hide-authors still hides, with a warning in the banner and the status record")
    func oldHideAuthors() async throws {
        let config = "hide-authors = [\"dependabot[bot]\"]\n\n" + shop()
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(everyAuthor[0], everyAuthor[1], everyAuthor[2], everyAuthor[3]))

        #expect(harness.numbers("shop")?.sorted() == [1, 2, 4])
        await harness.refresh(answering: shopAnswer(everyAuthor[0], everyAuthor[1], everyAuthor[2], everyAuthor[3], pr(5, author: "dependabot", type: "Bot")))
        #expect(harness.headlines.isEmpty)

        let warning = try #require(harness.shipyard.configWarnings.first)
        #expect(harness.shipyard.configWarnings.count == 1)
        #expect(warning.line == 1)
        #expect(warning.message.hasPrefix("`hide-authors` is the old form"))
        #expect(PanelText.configWarnings(harness.shipyard.configWarnings)?.contains("`hide-authors` is the old form") == true)
        #expect(try recordedWarnings(harness) == [warning.message])
    }

    @Test("old notification author strings still select, with a warning")
    func oldNotificationAuthors() async throws {
        let config = """
            [[defaults.notifications]]
            event = "pr.opened"
            authors = "others"

            """ + shop()
        let harness = try await Harness.started(config: config, graphQL: shopAnswer(pr(1)))
        await harness.refresh(answering: shopAnswer(pr(1), pr(2), pr(3, author: "octocat"), pr(4, author: "dependabot", type: "Bot")))
        #expect(harness.headlines == ["shop · New PR #3"])
        #expect(harness.shipyard.configWarnings.map(\.line) == [3])
        #expect(try recordedWarnings(harness).count == 1)
    }

    @Test("a bad author selector is rejected with its line, and the last valid configuration keeps running")
    func rejected() async throws {
        let harness = try await Harness.started(config: shop(), graphQL: shopAnswer(pr(1), pr(2, author: "octocat")))
        try await harness.reconfigure(shop(authors: #"{ hide = ["bot"] }"#), answering: shopAnswer(pr(1), pr(2, author: "octocat")))
        let error = try #require(harness.shipyard.configError)
        #expect(error.issues == [ConfigIssue(line: 4, message: "unknown author `bot` (did you mean `bots` or `@bot`?)")])
        #expect(harness.numbers("shop")?.sorted() == [1, 2])
    }

    /// The warnings' messages in `config-status.json`, as an agent reads them.
    private func recordedWarnings(_ harness: Harness) throws -> [String] {
        let data = try Data(contentsOf: harness.stateDirectory.appendingPathComponent(ConfigStatusStore.fileName))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let warnings = try #require(json["warnings"] as? [[String: Any]])
        return warnings.compactMap { $0["message"] as? String }
    }
}

@Suite("Listing: the rule")
struct ListingRuleTests {
    private static let now = Date(timeIntervalSince1970: 1_790_337_600)

    private func item(
        _ number: Int,
        kind: ItemKind = .pullRequest,
        state: ItemState = .open,
        author: String = "octocat",
        authorKind: AuthorKind = .other,
        closedHoursAgo: Double? = nil
    ) -> Item {
        Item(
            kind: kind,
            repository: "o/r",
            number: number,
            title: "Item \(number)",
            url: URL(string: "https://github.com/o/r/\(kind.rawValue)/\(number)")!,
            author: author,
            authorKind: authorKind,
            state: state,
            createdAt: Self.now.addingTimeInterval(-86_400 * 30),
            updatedAt: Self.now,
            closedAt: closedHoursAgo.map { Self.now.addingTimeInterval(-3600 * $0) }
        )
    }

    private func listed(_ items: [Item], _ settings: ProjectSettings, viewer: String? = "yabepa") -> [Int] {
        let snapshot = Snapshot(fetchedAt: Self.now, items: [settings.name: items])
        return Listing.items(for: settings, in: snapshot, viewer: viewer, now: Self.now).map(\.number)
    }

    private func project() -> ProjectSettings {
        Configuration().settings(for: Configuration.Project(name: "p", repositories: ["o/r"]))
    }

    @Test("every filter combines with AND")
    func everyFilter() {
        var settings = project()
        settings.issues.show = true
        settings.pullRequests.drafts = false
        settings.pullRequests.closedWindowDays = 1
        settings.issues.authors = AuthorFilter(hide: [.me])
        let items = [
            item(1),
            item(2, state: .draft),
            item(3, state: .closed, closedHoursAgo: 23),
            item(4, state: .merged, closedHoursAgo: 25),
            item(5, kind: .issue, author: "yabepa", authorKind: .me),
            item(6, kind: .issue),
            item(7, kind: .workflowRun, state: .running),
        ]
        #expect(listed(items, settings) == [1, 3, 6])
    }

    @Test("each kind lists only its states: a draft is open, a running run in progress")
    func states() {
        var settings = project()
        settings.issues.show = true
        settings.workflowRuns.show = true
        let items = [
            item(1),
            item(2, state: .draft),
            item(3, state: .merged, closedHoursAgo: 1),
            item(4, state: .closed, closedHoursAgo: 1),
            item(5, kind: .issue),
            item(6, kind: .issue, state: .closed, closedHoursAgo: 1),
            item(7, kind: .workflowRun, state: .running),
            item(8, kind: .workflowRun, state: .failed, closedHoursAgo: 1),
            item(9, kind: .workflowRun, state: .succeeded, closedHoursAgo: 1),
        ]
        #expect(listed(items, settings) == [1, 2, 3, 4, 5, 6, 7, 8, 9])

        settings.pullRequests.states = [.open]
        settings.issues.states = [.closed]
        settings.workflowRuns.states = [.inProgress, .failed]
        #expect(listed(items, settings) == [1, 2, 6, 7, 8])

        settings.pullRequests.states = [.merged]
        settings.issues.states = []
        settings.workflowRuns.states = [.succeeded]
        #expect(listed(items, settings) == [3, 9])
    }

    @Test("states picks which closed items; the window still says for how long")
    func statesAndWindow() {
        var settings = project()
        settings.pullRequests.states = [.closed]
        settings.pullRequests.closedWindowDays = 1
        let items = [
            item(1),
            item(2, state: .closed, closedHoursAgo: 23),
            item(3, state: .closed, closedHoursAgo: 25),
            item(4, state: .merged, closedHoursAgo: 1),
        ]
        #expect(listed(items, settings) == [2])
    }

    @Test("me is the viewer's login even where the fetch didn't mark it")
    func viewerIsMe() {
        var settings = project()
        settings.pullRequests.authors = AuthorFilter(hide: [.me])
        let items = [item(1, author: "YaBePa"), item(2)]
        #expect(listed(items, settings) == [2])
        #expect(listed(items, settings, viewer: nil) == [1, 2])
    }

    @Test("a project the snapshot has no entry for has no listing yet")
    func notFetchedYet() {
        let snapshot = Snapshot(fetchedAt: Self.now, items: ["p": [item(1)]])
        var other = project()
        other.name = "added since"
        let listings = Listing.listings(for: [project(), other], in: snapshot, now: Self.now)
        #expect(listings.mapValues { $0.map(\.number) } == ["p": [1]])
    }
}
