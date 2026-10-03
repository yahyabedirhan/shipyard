import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

private typealias PR = PullRequestsResponse.PullRequest
private typealias Issue = PullRequestsResponse.Issue

private let web = "yahyabedirhan/shop-web"
private let blogRepo = "yahyabedirhan/blog"

/// Two projects, "shop" (pull requests capped at 5, issues shown) and
/// "blog" grouped by `blogGroupBy`, under `layout`.
private func config(layout: MenuLayout = .tabs, blogGroupBy: String = "kind") -> String {
    """
    [menu]
    layout = "\(layout.rawValue)"

    [defaults.issues]
    show = true

    [[projects]]
    name = "shop"
    repositories = ["\(web)"]
    show-first = 5

    [[projects]]
    name = "blog"
    repositories = ["\(blogRepo)"]
    group-by = "\(blogGroupBy)"
    """
}

/// Seven pull requests and an issue in shop, one pull request in blog.
private let answer = PullRequestsResponse.answer([
    PullRequestsResponse(web, (1...7).map { number in
        var pr = PR(number)
        pr.updatedAt = "2026-09-25T0\(9 - number):00:00Z"
        return pr
    }, issues: [Issue(8)]),
    PullRequestsResponse(blogRepo, [PR(20)], issues: []),
])

private let shopPullRequests = GroupID(project: "shop", key: .kind(.pullRequest))

// `shipyard panel fold`, `unfold` and `show-more` reach the orchestrator's
// own operations by name, and `tab` finds its tab in the menu; whatever
// they name that isn't there is refused with what is.
@MainActor
@Suite("Steering the panel by name")
struct PanelSteeringTests {
    @Test("fold and unfold collapse and expand a project's or a machine's section by name, only when it differs; the status lists both")
    func foldUnfold() async throws {
        let harness = try Harness(stored: "gho_stored", config: "[remote]\nmachines = [\"netcup-vps\"]\n\n" + config())
        await harness.startWithMachines(graphQL: answer, netcup: [remotePing("q1", "Deploy?")], polled: true)
        #expect(harness.shipyard.menu.projectNames == ["shop", "blog", "netcup-vps"])

        try harness.shipyard.setCollapsed("blog", true)
        try harness.shipyard.setCollapsed("blog", true)
        try harness.shipyard.setCollapsed("netcup-vps", true)

        #expect(harness.section("blog")?.isCollapsed == true)
        #expect(harness.shipyard.menu.collapsedProjects == ["blog", "netcup-vps"])
        try harness.shipyard.setCollapsed("netcup-vps", false)

        try harness.shipyard.setCollapsed("blog", false)
        try harness.shipyard.setCollapsed("blog", false)

        #expect(harness.section("blog")?.isCollapsed == false)
        #expect(harness.shipyard.menu.collapsedProjects.isEmpty)
    }

    @Test("fold refuses a project that isn't there, naming the projects")
    func foldUnknown() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)

        #expect(throws: PanelRefusal("no project is named `shopp`; the projects are `shop`, `blog`")) {
            try harness.shipyard.setCollapsed("shopp", true)
        }
        #expect(harness.shipyard.menu.collapsedProjects.isEmpty)
    }

    @Test("show-more opens a project's group of one kind, which the menu closing caps again")
    func showMore() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)

        try harness.shipyard.showMore("shop", kind: "pull-requests")

        #expect(harness.shipyard.menu.group(shopPullRequests)?.rows.count == 7)
        #expect(harness.shipyard.menu.kindGroupsShowingAll.map { "\($0.project) \($0.kind.commandName)" } == ["shop pull-requests"])
        // A group under its cap stays as it is.
        try harness.shipyard.showMore("shop", kind: "issues")
        #expect(harness.shipyard.expandedGroups == [shopPullRequests])

        harness.shipyard.panelClosed()

        #expect(harness.shipyard.menu.kindGroupsShowingAll.isEmpty)
    }

    @Test("show-more refuses an unknown project or kind, and a kind the project doesn't list, naming what it has", arguments: [
        ("shopp", "pull-requests", "no project is named `shopp`; the projects are `shop`, `blog`"),
        ("shop", "prs", "no kind is named `prs`; the kinds are `pull-requests`, `issues`, `workflow-runs`, `pings`"),
        ("shop", "workflow-runs", "`shop` lists no workflow-runs; its kinds are `pull-requests`, `issues`"),
        ("blog", "pull-requests", "`blog` lists no group by kind; show-more needs `group-by = \"kind\"`, the default"),
    ])
    func showMoreRefused(project: String, kind: String, reason: String) async throws {
        let harness = try await Harness.started(config: config(blogGroupBy: "repository"), graphQL: answer)

        #expect(throws: PanelRefusal(reason)) { try harness.shipyard.showMore(project, kind: kind) }
        #expect(harness.shipyard.expandedGroups.isEmpty)
    }

    @Test("tab finds a project's tab or All (in any case), and refuses another name with the tabs")
    func tab() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        let menu = harness.shipyard.menu

        #expect(try menu.tab(named: "blog") == .project("blog"))
        #expect(try menu.tab(named: "All") == .all)
        #expect(try menu.tab(named: "all") == .all)
        #expect(throws: PanelRefusal("no tab is named `Blog`; the tabs are `All`, `shop`, `blog`")) {
            try menu.tab(named: "Blog")
        }
    }

    @Test("tab is refused in the list layout, which has no tabs")
    func tabInList() async throws {
        let harness = try await Harness.started(config: config(layout: .list), graphQL: answer)

        #expect(throws: PanelRefusal("the menu uses the list layout; tabs need `[menu] layout = \"tabs\"`")) {
            try harness.shipyard.menu.tab(named: "shop")
        }
    }
}
