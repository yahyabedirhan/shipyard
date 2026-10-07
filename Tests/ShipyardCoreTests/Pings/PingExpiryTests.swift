import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shopAndBlog = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    [[projects]]
    slug = "blog"
    repositories = ["yahyabedirhan/blog"]

    """

private typealias PR = PullRequestsResponse.PullRequest

/// One open pull request in `yahyabedirhan/shop`, none in the blog.
private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PR(1)]).answer

@MainActor
private extension Harness {
    /// Sends a ping through the CLI with `flags`, lets the app see the
    /// store change, and returns its id.
    @discardableResult
    func send(_ title: String, _ flags: String...) async throws -> String {
        let result = cli(["ping", title] + (flags.contains("--project") || flags.contains("--repo") ? [] : ["--project", "shop"]) + flags)
        try #require(result.status == 0, "\(result.error)")
        await shipyard.reloadPings()
        return result.pingID
    }

    /// The ping rows' titles in `project`.
    func pingTitles(_ project: String = "shop") -> [String] {
        section(project)?.rows.filter { $0.kind == .ping }.map(\.title) ?? []
    }

    /// The ping row titled `title` in `project`.
    func pingRow(_ title: String, in project: String = "shop") throws -> MenuRow {
        try #require(section(project)?.rows.first { $0.kind == .ping && $0.title == title })
    }

    /// Refreshes with GitHub answering `onePullRequest` again.
    func refreshAgain() async {
        graphQL([onePullRequest])
        await shipyard.refresh()
    }
}

/// How pings leave: a seen one after its `seen-window`, any one when it's
/// dismissed; an unseen one never on its own. End to end from the CLI
/// through the store to the menu, with the clock double.
@Suite("Pings leaving")
@MainActor
struct PingExpiryTests {
    // MARK: seen-window

    @Test("a seen ping stays listed for 24 hours by default, then leaves on the next refresh and is removed from the store")
    func seenWindowDefault() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        let id = try await harness.send("Ready")
        harness.shipyard.markSeen(try harness.pingRow("Ready"))

        harness.clock.advance(by: 24 * 3600 - 1)
        await harness.refreshAgain()
        #expect(harness.pingTitles() == ["Ready"])
        #expect(harness.pingStore.ping(id: id) != nil)

        harness.clock.advance(by: 1)
        await harness.refreshAgain()
        #expect(harness.pingTitles().isEmpty)
        #expect(harness.pingStore.ping(id: id) == nil)
        #expect(harness.pingStore.all().isEmpty)
    }

    @Test("the window counts from when the ping was seen, not when it was sent")
    func countsFromSeen() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Ready")
        harness.clock.advance(by: 20 * 3600)
        harness.shipyard.markSeen(try harness.pingRow("Ready"))

        harness.clock.advance(by: 20 * 3600)
        await harness.refreshAgain()
        #expect(harness.pingTitles() == ["Ready"])
    }

    @Test("an unseen ping never leaves on its own")
    func unseenStays() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        let id = try await harness.send("Waiting for you")

        harness.clock.advance(by: 365 * 86_400)
        await harness.refreshAgain()

        #expect(harness.pingTitles() == ["Waiting for you"])
        #expect(try harness.pingRow("Waiting for you").needsAttention)
        #expect(harness.pingStore.ping(id: id) != nil)
    }

    @Test("a seen ping whose window has passed leaves when the store changes too, without a refresh")
    func leavesOnStoreChange() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        let old = try await harness.send("Old")
        harness.shipyard.markSeen(try harness.pingRow("Old"))
        harness.clock.advance(by: 24 * 3600)

        try await harness.send("New")

        #expect(harness.pingTitles() == ["New"])
        #expect(harness.pingStore.ping(id: old) == nil)
    }

    @Test("[defaults.pings] seen-window sets every project's, and a project's own overrides it")
    func seenWindowSetting() async throws {
        let harness = try await Harness.started(config: """
            [defaults.pings]
            seen-window = "30m"

            [[projects]]
            slug = "shop"
            repositories = ["yahyabedirhan/shop"]

            [[projects]]
            slug = "blog"
            repositories = ["yahyabedirhan/blog"]
            pings = { seen-window = "2h" }

            """, graphQL: onePullRequest)
        let quick = try await harness.send("Quick")
        let slow = try await harness.send("Slow", "--project", "blog")
        harness.shipyard.markAllSeen()

        harness.clock.advance(by: 30 * 60)
        await harness.refreshAgain()
        #expect(harness.pingTitles().isEmpty)
        #expect(harness.pingTitles("blog") == ["Slow"])
        #expect(harness.pingStore.ping(id: quick) == nil)

        harness.clock.advance(by: 90 * 60)
        await harness.refreshAgain()
        #expect(harness.pingTitles("blog").isEmpty)
        #expect(harness.pingStore.ping(id: slow) == nil)
    }

    @Test("a ping filed under two projects leaves each by its own window, and is removed once it has left both")
    func filedTwice() async throws {
        let harness = try await Harness.started(config: """
            [[projects]]
            slug = "shop"
            repositories = ["yahyabedirhan/shop"]
            pings = { seen-window = "1h" }

            [[projects]]
            slug = "shop-too"
            repositories = ["yahyabedirhan/shop"]

            """, graphQL: onePullRequest)
        let id = try await harness.send("Both", "--repo", "yahyabedirhan/shop")
        harness.shipyard.markSeen(try harness.pingRow("Both"))

        harness.clock.advance(by: 3600)
        await harness.refreshAgain()
        #expect(harness.pingTitles().isEmpty)
        #expect(harness.pingTitles("shop-too") == ["Both"])
        #expect(harness.pingStore.ping(id: id) != nil)

        harness.clock.advance(by: 23 * 3600)
        await harness.refreshAgain()
        #expect(harness.pingTitles("shop-too").isEmpty)
        #expect(harness.pingStore.ping(id: id) == nil)
    }

    @Test("seen-window = \"0\" lets a ping leave as soon as it's seen")
    func zeroWindow() async throws {
        let harness = try await Harness.started(config: """
            [defaults.pings]
            seen-window = "0"

            [[projects]]
            slug = "shop"
            repositories = ["yahyabedirhan/shop"]

            """, graphQL: onePullRequest)
        let id = try await harness.send("Gone once seen")

        await harness.shipyard.open(try harness.pingRow("Gone once seen")).value

        #expect(harness.pingTitles().isEmpty)
        #expect(harness.pingStore.ping(id: id) == nil)
    }

    @Test("an edit to seen-window applies live")
    func liveEdit() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Ready")
        harness.shipyard.markSeen(try harness.pingRow("Ready"))
        harness.clock.advance(by: 3600)

        try harness.writeConfig("[defaults.pings]\nseen-window = \"1h\"\n\n" + shopAndBlog)
        harness.graphQL([onePullRequest])
        _ = await harness.shipyard.reloadConfiguration()

        #expect(harness.pingTitles().isEmpty)
        #expect(harness.pingStore.all().isEmpty)
    }

    // MARK: Mark all seen

    @Test("Mark all seen for one project marks only its pings seen")
    func markAllSeenInProject() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        let shopPing = try await harness.send("In the shop")
        let blogPing = try await harness.send("In the blog", "--project", "blog")

        harness.shipyard.markAllSeen(project: "blog")

        #expect(harness.pingStore.ping(id: blogPing)?.seen == harness.clock.now)
        #expect(harness.pingStore.ping(id: shopPing)?.seen == nil)
        #expect(try harness.pingRow("In the shop").needsAttention)
        #expect(try harness.pingRow("In the blog", in: "blog").needsAttention == false)
    }

    // MARK: Dismiss

    @Test("dismissing a ping removes it now, seen or not, and it no longer counts")
    func dismiss() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        let unseen = try await harness.send("Unseen")
        let seen = try await harness.send("Seen")
        harness.shipyard.markSeen(try harness.pingRow("Seen"))
        #expect(harness.shipyard.menu.attention.pings == 1)

        harness.shipyard.dismiss(try harness.pingRow("Unseen"))
        harness.shipyard.dismiss(try harness.pingRow("Seen"))

        #expect(harness.pingTitles().isEmpty)
        #expect(harness.shipyard.menu.attention.pings == 0)
        #expect(harness.pingStore.ping(id: unseen) == nil)
        #expect(harness.pingStore.ping(id: seen) == nil)
        #expect(harness.actions.ran.isEmpty)
    }

    @Test("dismissing a ping filed under two projects removes it from both")
    func dismissEverywhere() async throws {
        let harness = try await Harness.started(config: """
            [[projects]]
            slug = "shop"
            repositories = ["yahyabedirhan/shop"]

            [[projects]]
            slug = "shop-too"
            repositories = ["yahyabedirhan/shop"]

            """, graphQL: onePullRequest)
        try await harness.send("Both", "--repo", "yahyabedirhan/shop")

        harness.shipyard.dismiss(try harness.pingRow("Both"))

        #expect(harness.pingTitles().isEmpty)
        #expect(harness.pingTitles("shop-too").isEmpty)
    }

    @Test("dismiss does nothing to a pull request's row")
    func dismissPullRequest() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        let row = try #require(harness.section("shop")?.rows.first { $0.kind == .pullRequest })

        harness.shipyard.dismiss(row)

        #expect(harness.section("shop")?.rows.contains { $0.kind == .pullRequest } == true)
    }
}
