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

    """

private func answer(_ numbers: Int...) -> StubHTTP.Answer {
    PullRequestsResponse("yahyabedirhan/shop", numbers.map { PullRequestsResponse.PullRequest($0) }).answer
}

// `[menu] layout` picks how the panel draws the menu model: the list
// (the default) or the tabs. Like every setting it applies as soon as the
// configuration changes.
@MainActor
@Suite("The menu layout")
struct MenuLayoutTests {
    @Test("without the key the menu is the list; with it, the configured layout")
    func configured() async throws {
        let list = try await Harness.started(config: shop, graphQL: answer(1))
        #expect(list.shipyard.menu.layout == .list)

        let tabs = try await Harness.started(config: "[menu]\nlayout = \"tabs\"\n\n" + shop, graphQL: answer(1))
        #expect(tabs.shipyard.menu.layout == .tabs)
        #expect(tabs.section("shop")?.rows.map(\.number) == [1])
    }

    @Test("changing the layout switches the open menu at once, keeping its rows, even when the refresh fails")
    func liveChange() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(1, 2))
        #expect(harness.shipyard.menu.layout == .list)
        let rows = harness.section("shop")?.rows.map(\.number)
        #expect(rows?.count == 2)

        harness.graphQL([.failure()])
        try harness.writeConfig("[menu]\nlayout = \"tabs\"\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.menu.layout == .tabs)
        #expect(harness.section("shop")?.rows.map(\.number) == rows)
        #expect(harness.shipyard.menu.fetchError != nil)

        try harness.writeConfig("[menu]\nlayout = \"list\"\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.menu.layout == .list)
    }

    @Test("the layouts form a cycle: list, then tabs, then back to list")
    func cycle() {
        #expect(MenuLayout.list.next == .tabs)
        #expect(MenuLayout.tabs.next == .list)
    }

    @Test("stepping through the cycle visits every layout once before wrapping")
    func cycleVisitsEveryLayout() {
        for start in MenuLayout.allCases {
            var visited: [MenuLayout] = [start]
            var layout = start.next
            while layout != start {
                visited.append(layout)
                layout = layout.next
            }
            #expect(Set(visited) == Set(MenuLayout.allCases))
            #expect(visited.count == MenuLayout.allCases.count)
        }
    }

    @Test("the layout button writes the next layout to the file and the menu follows, wrapping back to list")
    func buttonCyclesLayouts() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(1, 2))
        let rows = harness.section("shop")?.rows.map(\.number)

        await harness.shipyard.switchToNextLayout()
        #expect(harness.shipyard.menu.layout == .tabs)
        #expect(harness.section("shop")?.rows.map(\.number) == rows)
        #expect(try String(contentsOf: harness.configURL, encoding: .utf8) == "[menu]\nlayout = \"tabs\"\n\n" + shop)

        await harness.shipyard.switchToNextLayout()
        #expect(harness.shipyard.menu.layout == .list)
        #expect(try String(contentsOf: harness.configURL, encoding: .utf8) == "[menu]\nlayout = \"list\"\n\n" + shop)
        #expect(harness.shipyard.configError == nil)
    }

    @Test("with a broken file the layout button changes nothing, and the banner says why")
    func buttonOnBrokenFile() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(1))
        let broken = shop + "[menu]\nlayout = \"grid\"\n"
        try harness.writeConfig(broken)

        await harness.shipyard.switchToNextLayout()
        #expect(harness.shipyard.menu.layout == .list)
        #expect(harness.shipyard.configError?.issues
            == [ConfigIssue(line: 5, message: "unknown value `grid` for `layout` (expected one of `list`, `tabs`)")])
        #expect(try String(contentsOf: harness.configURL, encoding: .utf8) == broken)
    }

    @Test("a [menu] the button can't edit leaves the layout, says why, and the next good reload clears it")
    func buttonOnUneditableMenu() async throws {
        let inline = "menu = { layout = \"list\" }\n" + shop
        let harness = try await Harness.started(config: inline, graphQL: answer(1))

        await harness.shipyard.switchToNextLayout()
        #expect(harness.shipyard.menu.layout == .list)
        #expect(harness.shipyard.configError?.line == 1)
        #expect(try String(contentsOf: harness.configURL, encoding: .utf8) == inline)

        try harness.writeConfig("menu = { layout = \"tabs\" }\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.menu.layout == .tabs)
    }

    @Test("an unknown layout is a configuration error, and the menu keeps the last valid layout")
    func unknownLayout() async throws {
        let harness = try await Harness.started(config: "[menu]\nlayout = \"tabs\"\n\n" + shop, graphQL: answer(1))

        try harness.writeConfig("[menu]\nlayout = \"grid\"\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError?.issues
            == [ConfigIssue(line: 2, message: "unknown value `grid` for `layout` (expected one of `list`, `tabs`)")])
        #expect(harness.shipyard.menu.layout == .tabs)
    }
}
