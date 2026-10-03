import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    [[projects]]
    name = "blog"
    repositories = ["yahyabedirhan/blog"]

    """

private typealias PR = PullRequestsResponse.PullRequest

/// One open pull request in `yahyabedirhan/shop`, none in the blog.
private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PR(1)]).answer

@MainActor
private extension Harness {
    /// Sends a ping through the CLI and returns its id.
    @discardableResult
    func ping(_ title: String, project: String = "shop") throws -> String {
        let result = cli("ping", title, "--project", project)
        try #require(result.status == 0, "\(result.error)")
        return result.pingID
    }

    /// The ping rows of `project`.
    func pingRows(_ project: String = "shop") -> [MenuRow] {
        section(project)?.rows.filter { $0.kind == .ping } ?? []
    }

    /// The group titles of `project`, in order.
    func groupTitles(_ project: String = "shop") -> [String] {
        section(project)?.groups.map(\.title) ?? []
    }
}

/// A ping sent with the CLI, through the shared store, to the menu: end to
/// end across the ping command and the `Shipyard` orchestrator.
@Suite("Pings in the menu")
@MainActor
struct PingsTests {
    @Test("a ping sent while the app isn't running is listed under its project when it starts, in a Pings group")
    func sentBeforeStart() async throws {
        let harness = try Harness(stored: "gho_stored", config: shop)
        let id = try harness.ping("Ready for review")
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])

        await harness.shipyard.start()

        let rows = harness.pingRows()
        #expect(rows.map(\.title) == ["Ready for review"])
        #expect(rows.first?.id == Ping.url(id: id).absoluteString)
        #expect(harness.groupTitles() == ["Pull requests", "Pings"])
        #expect(harness.pingRows("blog").isEmpty)
    }

    @Test("a ping is listed in its project's tab and in the All tab, in a Pings group")
    func inTheTabs() async throws {
        let harness = try await Harness.started(config: "[menu]\nlayout = \"tabs\"\n" + shop, graphQL: onePullRequest)
        try harness.ping("Ready for review")
        await harness.shipyard.reloadPings()

        let menu = harness.shipyard.menu
        let tab = menu.tabContent(for: .project("shop"))
        #expect(tab.groups.map(\.title) == ["Pull requests", "Pings"])
        #expect(tab.groups.last?.showsHeader == true)
        let all = menu.tabContent(for: .all)
        #expect(all.groups.map(\.title) == ["Pull requests", "Pings"])
        #expect(all.groups.last?.rows.map(\.title) == ["Ready for review"])
    }

    @Test("a ping sent while the app runs shows when the store changes, without asking GitHub")
    func sentWhileRunning() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let requests = harness.graphQLRequests.count

        try harness.ping("Waiting for your input")
        await harness.shipyard.reloadPings()

        #expect(harness.pingRows().map(\.title) == ["Waiting for your input"])
        #expect(harness.graphQLRequests.count == requests)
    }

    @Test("pings show even before GitHub has answered")
    func beforeGitHubAnswers() async throws {
        let harness = try Harness(stored: "gho_stored", config: shop)
        try harness.ping("Published")
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([.json(#"{"message":"Server Error"}"#, status: 502)])

        await harness.shipyard.start()

        #expect(harness.section("shop")?.isLoaded == false)
        #expect(harness.pingRows().map(\.title) == ["Published"])
        #expect(harness.shipyard.menu.attention.total == 1)
    }

    @Test("a new ping needs attention and counts in its project and in the menu bar")
    func newPingNeedsAttention() async throws {
        let harness = try await Harness.started(config: "[menu-bar]\ncount = \"per-kind\"\n" + shop, graphQL: onePullRequest)
        try harness.ping("Ready for review")
        await harness.shipyard.reloadPings()

        #expect(harness.pingRows().first?.needsAttention == true)
        #expect(harness.pingRows().first?.attentionReasons == [.unseen])
        #expect(harness.section("shop")?.attentionCount == 2)
        #expect(harness.section("blog")?.attentionCount == 0)
        #expect(harness.shipyard.menu.attention == AttentionCounts(pullRequests: 1, pings: 1))
        #expect(harness.shipyard.menu.menuBarLabel.text == "1 PR · 1 ping")
    }

    @Test("clicking a ping's row marks it seen, opens nothing, and stays seen after a relaunch")
    func clickMarksSeen() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try harness.ping("Ready for review")
        await harness.shipyard.reloadPings()
        let row = try #require(harness.pingRows().first)

        harness.shipyard.open(row)

        #expect(harness.actions.opened.isEmpty)
        #expect(harness.pingRows().first?.needsAttention == false)
        #expect(harness.section("shop")?.attentionCount == 1)
        #expect(harness.shipyard.menu.attention.total == 1)
        #expect(harness.pingStore.ping(id: id)?.seen == harness.clock.now)

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        await relaunched.shipyard.start()
        #expect(relaunched.pingRows().first?.needsAttention == false)
        #expect(relaunched.shipyard.menu.attention.total == 1)
    }

    @Test("⌥-click and Mark all seen mark pings seen too")
    func markSeenAndMarkAllSeen() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try harness.ping("First")
        try harness.ping("Second", project: "blog")
        await harness.shipyard.reloadPings()

        harness.shipyard.markSeen(try #require(harness.pingRows().first))
        #expect(harness.shipyard.menu.attention.pings == 1)

        harness.shipyard.markAllSeen()
        #expect(harness.shipyard.menu.attention.total == 0)
        #expect(harness.pingStore.all().allSatisfy { $0.seen != nil })
    }

    @Test("[defaults.pings] show = false hides pings, a project can show them again, and an edit applies live")
    func showSetting() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try harness.ping("In the shop")
        try harness.ping("In the blog", project: "blog")
        await harness.shipyard.reloadPings()
        #expect(harness.shipyard.menu.attention.pings == 2)

        try harness.writeConfig("""
            [defaults.pings]
            show = false

            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]

            [[projects]]
            name = "blog"
            repositories = ["yahyabedirhan/blog"]
            pings = { show = true }

            """)
        await harness.shipyard.reloadConfiguration()

        #expect(harness.pingRows().isEmpty)
        #expect(harness.groupTitles() == ["Pull requests"])
        #expect(harness.pingRows("blog").map(\.title) == ["In the blog"])
        #expect(harness.shipyard.menu.attention.pings == 1)
        #expect(harness.section("shop")?.attentionCount == 1)
    }

    @Test("grouped by repository or author, pings without one sit in a Pings group, last; the row reads \"#1 · ping\"")
    func otherGroupings() async throws {
        let harness = try await Harness.started(config: "[defaults]\ngroup-by = \"repository\"\n" + shop, graphQL: onePullRequest)
        try harness.ping("Ready")
        await harness.shipyard.reloadPings()
        #expect(harness.groupTitles() == ["yahyabedirhan/shop", "Pings"])
        let row = try #require(harness.pingRows().first)
        #expect(PanelText.rowDetail(row, showingRepository: true) == "#1 · ping")

        try harness.writeConfig("[defaults]\ngroup-by = \"author\"\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.groupTitles() == ["@yabepa", "Pings"])
    }

    @Test("a store change that changes no ping leaves the menu as it is")
    func unchangedStore() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try harness.ping("Ready")
        await harness.shipyard.reloadPings()
        let menu = harness.shipyard.menu

        await harness.shipyard.reloadPings()

        #expect(harness.shipyard.menu == menu)
    }

    @Test("a ping file that doesn't read is skipped; the others still list")
    func unreadableFile() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try harness.ping("Ready")
        try Data("{ not json".utf8).write(to: harness.pingStore.directory.appendingPathComponent("broken.json"))

        await harness.shipyard.reloadPings()

        #expect(harness.pingRows().map(\.title) == ["Ready"])
    }
}
