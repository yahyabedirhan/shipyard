import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let repository = "yahyabedirhan/shop"

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

/// The projects `graphql-pull-requests.json` answers for.
private let twoProjects = """
    [[projects]]
    name = "e-commerce"
    repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]

    [[projects]]
    name = "job-search"
    repositories = ["yahyabedirhan/job-search"]

    """

private typealias PR = PullRequestsResponse.PullRequest

private func answer(_ pullRequests: PR...) -> StubHTTP.Answer {
    PullRequestsResponse(repository, pullRequests).answer
}

@MainActor
private extension Harness {
    /// The row for pull request `number` in `project`.
    func row(_ number: Int, in project: String = "shop") throws -> MenuRow {
        try #require(section(project)?.rows.first { $0.number == number })
    }

    /// Refreshes with GitHub answering `answer`.
    func refresh(answering answer: StubHTTP.Answer) async {
        graphQL([answer])
        clock.advance(by: 120)
        await shipyard.refresh()
    }

    /// The attention count.
    var count: Int { shipyard.menu.attention.total }
}

@Suite("Attention through the refresh pipeline")
@MainActor
struct AttentionTests {
    // MARK: - What counts

    @Test("a new pull request counts, and one arriving later counts too")
    func newPullRequestCounts() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(PR(1)))

        #expect(harness.count == 1)
        #expect(try harness.row(1).needsAttention)
        #expect(harness.section("shop")?.attentionCount == 1)

        harness.shipyard.markSeen(try harness.row(1))
        await harness.refresh(answering: answer(PR(1), PR(2)))

        #expect(harness.count == 1)
        #expect(try !harness.row(1).needsAttention)
        #expect(try harness.row(2).needsAttention)
    }

    @Test("opening an item opens it and marks it seen; ⌥-click marks it seen without opening")
    func markingSeenClearsIt() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(PR(1), PR(2)))
        #expect(harness.count == 2)

        harness.shipyard.open(try harness.row(1))

        #expect(harness.opener.opened == [PR(1).url(in: repository)])
        #expect(harness.count == 1)
        #expect(try !harness.row(1).needsAttention)

        harness.shipyard.markSeen(try harness.row(2))

        #expect(harness.opener.opened.count == 1)
        #expect(harness.count == 0)
        #expect(harness.section("shop")?.attentionCount == 0)

        // Refreshing without a change keeps them seen; opening the panel marks nothing.
        await harness.refresh(answering: answer(PR(1), PR(2)))
        #expect(harness.count == 0)
    }

    @Test("a new push resurfaces a seen pull request, even when the push was made as the user")
    func pushResurfaces() async throws {
        var pullRequest = PR(1)
        pullRequest.author = "yabepa"
        let harness = try await Harness.started(config: shop, graphQL: answer(pullRequest))
        harness.shipyard.open(try harness.row(1))
        #expect(harness.count == 0)

        pullRequest.updatedAt = "2026-09-25T11:30:00Z"
        await harness.refresh(answering: answer(pullRequest))

        #expect(harness.count == 1)
        #expect(try harness.row(1).needsAttention)
        #expect(try harness.row(1).authorKind == .me)
    }

    @Test("new comments, reviews and check results are changes too")
    func otherChanges() async throws {
        var pullRequest = PR(1)
        let harness = try await Harness.started(config: shop, graphQL: answer(pullRequest))

        let changes: [(inout PR) -> Void] = [
            { $0.comments += 1 },
            { $0.reviews += 1 },
            { $0.checks = "SUCCESS" },
            { $0.isDraft = true },
        ]
        for change in changes {
            harness.shipyard.markSeen(try harness.row(1))
            #expect(harness.count == 0)
            change(&pullRequest)
            await harness.refresh(answering: answer(pullRequest))
            #expect(harness.count == 1)
        }
    }

    @Test("a review request and failed checks count on their own, until seen")
    func reviewRequestAndFailedChecks() async throws {
        let config = "[attention]\nunseen = false\nchanged = false\n\n" + shop
        var review = PR(1)
        review.author = "octocat"
        review.reviewRequests = ["yabepa"]
        var failing = PR(2)
        failing.checks = "FAILURE"
        var quiet = PR(3)
        quiet.reviewRequests = ["someone-else"]
        let harness = try await Harness.started(config: config, graphQL: answer(review, failing, quiet))

        #expect(try harness.row(1).needsAttention)
        #expect(try harness.row(2).needsAttention)
        #expect(try !harness.row(3).needsAttention)
        #expect(harness.count == 2)

        // A click clears them until the item changes.
        harness.shipyard.markSeen(try harness.row(1))
        harness.shipyard.markSeen(try harness.row(2))
        #expect(harness.count == 0)

        failing.updatedAt = "2026-09-25T11:00:00Z"
        await harness.refresh(answering: answer(review, failing, quiet))
        #expect(try harness.row(2).needsAttention)
        #expect(harness.count == 1)
    }

    @Test("a review request that arrives after the item was seen counts")
    func reviewRequestAfterSeen() async throws {
        var pullRequest = PR(1)
        pullRequest.author = "octocat"
        let harness = try await Harness.started(config: shop, graphQL: answer(pullRequest))
        harness.shipyard.markSeen(try harness.row(1))

        pullRequest.reviewRequests = ["yabepa"]
        await harness.refresh(answering: answer(pullRequest))

        #expect(harness.count == 1)
    }

    @Test("closed and merged pull requests never count, whatever their checks or review requests")
    func closedNeverCounts() async throws {
        var merged = PR(1)
        merged.state = "MERGED"
        merged.closedAt = "2026-09-25T11:00:00Z"
        merged.checks = "FAILURE"
        var closed = PR(2)
        closed.state = "CLOSED"
        closed.closedAt = "2026-09-25T11:00:00Z"
        closed.reviewRequests = ["yabepa"]
        let harness = try await Harness.started(config: shop, graphQL: answer(merged, closed))

        #expect(harness.section("shop")?.rows.count == 2)
        #expect(harness.section("shop")?.rows.allSatisfy { !$0.needsAttention } == true)
        #expect(harness.count == 0)

        // An unseen open one stops counting once it's merged.
        var open = PR(3)
        await harness.refresh(answering: answer(merged, closed, open))
        #expect(harness.count == 1)
        open.state = "MERGED"
        open.closedAt = "2026-09-25T12:01:00Z"
        await harness.refresh(answering: answer(merged, closed, open))
        #expect(harness.count == 0)
    }

    @Test("[attention] unseen = false keeps new items out of the count; changed = false keeps pushes out")
    func toggles() async throws {
        var pullRequest = PR(1)
        let harness = try await Harness.started(config: "[attention]\nunseen = false\n\n" + shop, graphQL: answer(pullRequest))
        #expect(harness.count == 0)

        try harness.writeConfig("[attention]\nchanged = false\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.count == 1)

        harness.shipyard.markSeen(try harness.row(1))
        pullRequest.updatedAt = "2026-09-25T11:30:00Z"
        await harness.refresh(answering: answer(pullRequest))
        #expect(harness.count == 0)
    }

    @Test("hidden rows don't count")
    func hiddenRowsDontCount() async throws {
        var bot = PR(1)
        bot.author = "dependabot"
        bot.authorType = "Bot"
        let harness = try await Harness.started(config: "hide-authors = [\"dependabot[bot]\"]\n\n" + shop, graphQL: answer(bot, PR(2)))

        #expect(harness.count == 1)
    }

    // MARK: - Mark all seen

    @Test("mark all seen, per project and for everything")
    func markAllSeen() async throws {
        let harness = try await Harness.started(config: twoProjects, graphQL: Harness.fixture("graphql-pull-requests.json"))
        // e-commerce: open #14 (draft), #57, #12, #56, #55; job-search: #3. Closed #54 and #9 don't count.
        #expect(harness.section("e-commerce")?.attentionCount == 5)
        #expect(harness.section("job-search")?.attentionCount == 1)
        #expect(harness.count == 6)

        harness.shipyard.markAllSeen(project: "e-commerce")

        #expect(harness.section("e-commerce")?.attentionCount == 0)
        #expect(harness.section("job-search")?.attentionCount == 1)
        #expect(harness.count == 1)

        harness.shipyard.markAllSeen()

        #expect(harness.count == 0)
        #expect(harness.shipyard.menu.sections.allSatisfy { $0.attentionCount == 0 })
    }

    @Test("a repository in two projects counts once in the total and in each project's header")
    func sharedRepositoryCountsOnce() async throws {
        let config = """
            [[projects]]
            name = "job-search"
            repositories = ["yahyabedirhan/job-search"]

            [[projects]]
            name = "archive"
            repositories = ["yahyabedirhan/job-search", "yahyabedirhan/gone"]

            """
        let harness = try await Harness.started(config: config, graphQL: Harness.fixture("graphql-missing-repository.json"))

        #expect(harness.section("job-search")?.attentionCount == 1)
        #expect(harness.section("archive")?.attentionCount == 1)
        #expect(harness.count == 1)

        harness.shipyard.markAllSeen(project: "archive")
        #expect(harness.section("job-search")?.attentionCount == 0)
    }

    // MARK: - The menu bar

    @Test("the menu bar label follows [menu-bar] count, with per-kind counts")
    func menuBarLabel() async throws {
        let fixture = try Harness.fixture("graphql-pull-requests.json")
        let total = try await Harness.started(config: twoProjects, graphQL: fixture)
        #expect(total.shipyard.menu.attention == AttentionCounts(pullRequests: 6))
        #expect(total.shipyard.menu.menuBarLabel == .total(6))
        #expect(total.shipyard.menu.menuBarLabel.text == "6")

        let perKind = try await Harness.started(config: "[menu-bar]\ncount = \"per-kind\"\n\n" + twoProjects, graphQL: fixture)
        #expect(perKind.shipyard.menu.menuBarLabel == .perKind(AttentionCounts(pullRequests: 6)))
        #expect(perKind.shipyard.menu.menuBarLabel.text == "6 PRs")

        let none = try await Harness.started(config: "[menu-bar]\ncount = \"none\"\n\n" + twoProjects, graphQL: fixture)
        #expect(none.shipyard.menu.menuBarLabel == .hidden)
        #expect(none.shipyard.menu.menuBarLabel.text == nil)
        #expect(none.shipyard.menu.attention.total == 6)

        total.shipyard.markAllSeen()
        #expect(total.shipyard.menu.menuBarLabel == .total(0))
        #expect(total.shipyard.menu.menuBarLabel.text == nil)
    }

    @Test("without projects the menu bar shows no count; adding them back shows it after the next refresh")
    func menuBarLabelWithoutProjects() async throws {
        let harness = try await Harness.started(config: twoProjects, graphQL: Harness.fixture("graphql-pull-requests.json"))
        #expect(harness.shipyard.menu.menuBarLabel.text == "6")

        try harness.writeConfig("")
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.shipyard.menu.menuBarLabel.text == nil)

        // A collapse recomputes attention; the count stays hidden.
        harness.shipyard.toggleCollapsed("job-search")
        #expect(harness.shipyard.menu.menuBarLabel.text == nil)

        try harness.writeConfig(twoProjects)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.menu.menuBarLabel.text == "6")
    }

    @Test("signed out, the menu bar shows no count")
    func menuBarLabelSignedOut() async throws {
        let harness = try await Harness.started(config: twoProjects, graphQL: Harness.fixture("graphql-pull-requests.json"))
        #expect(harness.shipyard.menu.menuBarLabel.text == "6")

        harness.shipyard.signOut()
        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.shipyard.menu.menuBarLabel.text == nil)

        harness.shipyard.toggleCollapsed("job-search")
        #expect(harness.shipyard.menu.menuBarLabel.text == nil)
    }

    // MARK: - App state

    @Test("collapsed projects and seen items survive a restart")
    func survivesRestart() async throws {
        let harness = try await Harness.started(config: twoProjects, graphQL: Harness.fixture("graphql-pull-requests.json"))
        harness.shipyard.toggleCollapsed("job-search")
        harness.shipyard.markAllSeen(project: "e-commerce")

        #expect(harness.section("job-search")?.isCollapsed == true)
        #expect(harness.section("e-commerce")?.isCollapsed == false)
        // Collapsing hides rows; they still count.
        #expect(harness.count == 1)

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([try Harness.fixture("graphql-pull-requests.json")])
        await relaunched.shipyard.start()

        #expect(relaunched.section("job-search")?.isCollapsed == true)
        #expect(relaunched.section("e-commerce")?.attentionCount == 0)
        #expect(relaunched.count == 1)

        relaunched.shipyard.toggleCollapsed("job-search")
        #expect(relaunched.section("job-search")?.isCollapsed == false)
    }

    @Test("app state lives in state.json in the directory given, and never touches the configuration")
    func stateFile() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(PR(1)))
        let configuration = try Data(contentsOf: harness.configURL)

        harness.shipyard.open(try harness.row(1))
        harness.shipyard.toggleCollapsed("shop")

        #expect(harness.stateURL == harness.stateDirectory.appendingPathComponent("state.json"))
        #expect(try Data(contentsOf: harness.configURL) == configuration)
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: harness.stateURL)) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        #expect((json["seen"] as? [String: Any])?.keys.first == PR(1).url(in: repository).absoluteString)
        #expect(json["collapsed"] as? [String] == ["shop"])
    }

    @Test("a corrupt state file is set aside and treated as a first run")
    func corruptStateFile() async throws {
        let harness = try Harness(stored: "gho_stored", config: shop)
        try Data("{ not json".utf8).write(to: harness.stateURL)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([answer(PR(1))])

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .ready)
        #expect(harness.count == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: harness.stateDirectory.path)
        let setAside = try #require(files.first { $0.hasPrefix("state-corrupt-") })
        #expect(try String(contentsOf: harness.stateDirectory.appendingPathComponent(setAside), encoding: .utf8) == "{ not json")

        harness.shipyard.markSeen(try harness.row(1))
        #expect(try JSONSerialization.jsonObject(with: Data(contentsOf: harness.stateURL)) is [String: Any])
    }

    @Test("signing out keeps what was seen")
    func signOutKeepsSeen() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(PR(1)))
        harness.shipyard.markSeen(try harness.row(1))

        harness.shipyard.signOut()

        #expect(harness.shipyard.appStateStore.state.attention.seen.count == 1)
    }
}
