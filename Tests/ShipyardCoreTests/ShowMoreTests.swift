import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private typealias PR = PullRequestsResponse.PullRequest
private typealias Issue = PullRequestsResponse.Issue

private let web = "yahyabedirhan/shop-web"

/// One project, "shop", with issues shown, arranged by `settings` under
/// `[menu] layout`.
private func config(_ settings: String = "show-first = 5", layout: MenuLayout = .list) -> String {
    """
    [menu]
    layout = "\(layout.rawValue)"

    [defaults.issues]
    show = true

    [[projects]]
    name = "shop"
    repositories = ["\(web)"]
    \(settings)
    """
}

/// Seven open pull requests, #1 the newest, and one issue.
private let answer = PullRequestsResponse.answer([
    PullRequestsResponse(web, (1...7).map { number in
        var pr = PR(number)
        pr.updatedAt = "2026-09-25T0\(9 - number):00:00Z"
        return pr
    }, issues: [Issue(8)]),
])

private let pullRequests = GroupID(project: "shop", key: .kind(.pullRequest))
private let issues = GroupID(project: "shop", key: .kind(.issue))

@MainActor
private extension Harness {
    var shop: MenuSection? { section("shop") }

    func group(_ id: GroupID) -> RowGroup? {
        shop?.groups.first { $0.id == id }
    }

    func place(_ number: Int, in section: String? = "shop") -> MenuRowPlace {
        MenuRowPlace(section: section, row: PR(number).url(in: web).absoluteString)
    }
}

// `show-first` caps each group at its first rows, with a Show more row that
// shows the rest and then reads Show less. The expansion lives in memory
// only, and the menu closing caps every group again.
@MainActor
@Suite("Show more")
struct ShowMoreTests {
    @Test("show-first = 5 shows five rows and Show 2 more for a group of seven; Show more then Show less toggle it")
    func toggle() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        let capped = try #require(harness.group(pullRequests))
        #expect(capped.rows.map(\.number) == [1, 2, 3, 4, 5])
        #expect(capped.hiddenCount == 2)
        #expect(PanelText.showMore(capped) == "Show 2 more")
        #expect(harness.group(issues)?.hasShowMore == false)

        harness.shipyard.showMore(pullRequests)

        let expanded = try #require(harness.group(pullRequests))
        #expect(expanded.rows.map(\.number) == [1, 2, 3, 4, 5, 6, 7])
        #expect(PanelText.showMore(expanded) == "Show less")
        #expect(harness.shipyard.expandedGroups == [pullRequests])

        harness.shipyard.showLess(pullRequests)

        #expect(harness.group(pullRequests) == capped)
        #expect(harness.shipyard.expandedGroups.isEmpty)
        // No refresh: only the menu model changed, and nothing was saved.
        #expect(harness.graphQLRequests.count == 1)
        #expect(!((try? String(contentsOf: harness.stateURL, encoding: .utf8)) ?? "").contains("expanded"))
    }

    @Test("closing the menu brings every cap back")
    func closingCaps() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        harness.shipyard.showMore(pullRequests)
        #expect(harness.group(pullRequests)?.isExpanded == true)

        harness.shipyard.panelClosed()

        #expect(harness.shipyard.expandedGroups.isEmpty)
        #expect(harness.group(pullRequests)?.rows.count == 5)
        #expect(harness.group(pullRequests)?.hiddenCount == 2)
    }

    @Test("an expansion holds through a refresh while the menu stays open")
    func refreshKeepsExpansion() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        harness.shipyard.showMore(pullRequests)

        await harness.timer.fire()

        #expect(harness.graphQLRequests.count == 2)
        #expect(harness.group(pullRequests)?.rows.count == 7)
        #expect(harness.group(pullRequests)?.isExpanded == true)
    }

    @Test("counts include the rows Show more hides: the header's, the menu bar's, and Mark all seen's")
    func countsIncludeHidden() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        let group = try #require(harness.group(pullRequests))
        #expect(group.attentionCount == 7)
        #expect(group.allRows.count == 7)
        #expect(harness.shop?.attentionCount == 8)
        #expect(harness.shipyard.menu.menuBarLabel == .total(8))
        // The All tab isn't capped, and lists the hidden rows too.
        #expect(harness.shipyard.menu.tabContent(for: .all).groups.first?.rows.count == 7)

        harness.shipyard.markAllSeen(project: "shop")

        #expect(harness.shipyard.menu.menuBarLabel == .total(0))
    }

    @Test("with group-by none, the cap applies to the whole project")
    func wholeProject() async throws {
        let harness = try await Harness.started(config: config("show-first = 3\ngroup-by = \"none\""), graphQL: answer)
        let only = try #require(harness.shop?.groups.first)
        #expect(harness.shop?.groups.count == 1)
        #expect(only.rows.count == 3)
        #expect(PanelText.showMore(only) == "Show 5 more")
    }

    @Test("show-first applies live, and 0 shows every row")
    func appliesLive() async throws {
        let harness = try await Harness.started(config: config("show-first = 0"), graphQL: answer)
        #expect(harness.group(pullRequests)?.rows.count == 7)
        #expect(harness.group(pullRequests)?.hasShowMore == false)

        try harness.writeConfig(config("show-first = 2"))
        await harness.shipyard.reloadConfiguration()

        #expect(harness.group(pullRequests)?.rows.count == 2)
        #expect(harness.group(pullRequests)?.hiddenCount == 5)
    }

    @Test("Show more on a group that isn't capped changes nothing")
    func uncappedIgnored() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)

        harness.shipyard.showMore(issues)
        harness.shipyard.showMore(GroupID(project: "gone", key: .ungrouped))

        #expect(harness.shipyard.expandedGroups.isEmpty)
        #expect(harness.group(issues)?.hasShowMore == false)
    }

    // MARK: - The keys

    @Test("↑ and ↓ reach the Show more row after a group's rows, and Return's target is its group")
    func keysReachShowMore() async throws {
        let harness = try await Harness.started(config: config("show-first = 5\nsubsections = true"), graphQL: answer)
        let menu = harness.shipyard.menu
        let showMore = MenuRowPlace.showMore(pullRequests, in: "shop")
        #expect(menu.listRowPlaces == [
            .header("shop"),
            .groupHeader(pullRequests, in: "shop"),
            harness.place(1), harness.place(2), harness.place(3), harness.place(4), harness.place(5),
            showMore,
            .groupHeader(issues, in: "shop"),
            MenuRowPlace(section: "shop", row: Issue(8).url(in: web).absoluteString),
        ])

        var highlight = RowHighlight(place: harness.place(5))
        highlight.moveDown(in: menu.listRowPlaces)
        #expect(highlight.place == showMore)
        #expect(menu.listTarget(at: showMore) == .showMore(try #require(harness.group(pullRequests))))

        // Return toggles it; the highlight stays on the row, now Show less.
        harness.shipyard.showMore(pullRequests)
        let expanded = harness.shipyard.menu
        highlight.keep(in: expanded.listRowPlaces)
        #expect(highlight.place == showMore)
        #expect(expanded.listRowPlaces.firstIndex(of: showMore) == 9)
        #expect(expanded.listTarget(at: showMore) == .showMore(try #require(harness.group(pullRequests))))

        // ← goes to the group's subheader; → does nothing.
        #expect(highlight.moveRight(in: expanded) == nil)
        #expect(highlight.place == showMore)
        #expect(highlight.moveLeft(in: expanded) == nil)
        #expect(highlight.place == .groupHeader(pullRequests, in: "shop"))
    }

    @Test("after a divider, ← on the Show more row goes to the project's header")
    func leftAfterDivider() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        var highlight = RowHighlight(place: .showMore(pullRequests, in: "shop"))
        _ = highlight.moveLeft(in: harness.shipyard.menu)
        #expect(highlight.place == .header("shop"))
    }

    @Test("a folded group has no Show more row, and neither does a collapsed project")
    func foldedHidesShowMore() async throws {
        let harness = try await Harness.started(config: config("show-first = 5\nsubsections = true"), graphQL: answer)
        let showMore = MenuRowPlace.showMore(pullRequests, in: "shop")

        harness.shipyard.toggleGroup(pullRequests)
        #expect(!harness.shipyard.menu.listRowPlaces.contains(showMore))
        #expect(harness.shipyard.menu.listTarget(at: showMore) == nil)

        harness.shipyard.toggleGroup(pullRequests)
        harness.shipyard.toggleCollapsed("shop")
        #expect(harness.shipyard.menu.listRowPlaces == [.header("shop")])
        #expect(harness.shipyard.menu.listTarget(at: showMore) == nil)
    }

    @Test("in a project's tab, the keys reach the Show more row and Return finds its group")
    func tabs() async throws {
        let harness = try await Harness.started(config: config(layout: .tabs), graphQL: answer)
        let content = harness.shipyard.menu.tabContent(for: .project("shop"))
        let showMore = MenuRowPlace.showMore(pullRequests, in: nil)
        #expect(content.rowPlaces.contains(showMore))
        #expect(content.rowPlaces.firstIndex(of: showMore) == 6)
        #expect(content.showMoreGroup(at: showMore)?.id == pullRequests)
        #expect(content.subsection(at: showMore) == nil)
        #expect(content.row(at: showMore) == nil)
    }
}
