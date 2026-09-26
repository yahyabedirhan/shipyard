import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private typealias PR = PullRequestsResponse.PullRequest
private typealias Issue = PullRequestsResponse.Issue

private let web = "yahyabedirhan/shop-web"
private let api = "yahyabedirhan/shop-api"

/// One project over two repositories, issues shown, arranged by `settings`
/// (lines written into its block) under `[menu] layout`.
private func config(_ settings: String = "", layout: MenuLayout = .list) -> String {
    """
    [menu]
    layout = "\(layout.rawValue)"

    [defaults.issues]
    show = true

    [[projects]]
    name = "shop"
    repositories = ["\(web)", "\(api)"]
    \(settings)

    """
}

private func pr(_ number: Int, title: String, created: String, updated: String, author: String = "yabepa") -> PR {
    var pr = PR(number)
    pr.title = title
    pr.createdAt = created
    pr.updatedAt = updated
    pr.author = author
    return pr
}

/// Web: #1 (updated 11:00, created 08:00, "Zebra") and issue #5 ("A
/// problem", updated yesterday). Api: #2 (updated 10:00, created 09:30, "apple", by
/// octocat) and #3 (updated 2026-09-22, created 09:00, "Mango").
private let answer = PullRequestsResponse.answer([
    PullRequestsResponse(web, [
        pr(1, title: "Zebra", created: "2026-09-25T08:00:00Z", updated: "2026-09-25T11:00:00Z"),
    ], issues: {
        var issue = Issue(5)
        issue.updatedAt = "2026-09-24T15:00:00Z"
        issue.author = "yabepa"
        return [issue]
    }()),
    PullRequestsResponse(api, [
        pr(2, title: "apple", created: "2026-09-25T09:30:00Z", updated: "2026-09-25T10:00:00Z", author: "octocat"),
        pr(3, title: "Mango", created: "2026-09-25T09:00:00Z", updated: "2026-09-22T10:00:00Z"),
    ], issues: []),
])

@MainActor
private extension Harness {
    var shop: MenuSection? { section("shop") }
    /// Each group's title and its rows' numbers.
    var arranged: [String: [Int]] {
        Dictionary(uniqueKeysWithValues: (shop?.groups ?? []).map { ($0.title, $0.rows.map(\.number)) })
    }
}

// `group-by`, `sort-by` and `subsections` arrange a project's listed items,
// in the list and in a project's tab alike; the All tab keeps its own look.
@MainActor
@Suite("Arranging a project")
struct MenuArrangementTests {
    @Test("a file without the keys shows today's menu: by kind, newest first, dividers in the list")
    func defaultList() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)

        let groups = try #require(harness.shop?.groups)
        #expect(groups.map(\.id.key) == [.kind(.pullRequest), .kind(.issue)])
        #expect(groups.map(\.showsHeader) == [false, false])
        #expect(harness.shop?.rows.map(\.number) == [1, 2, 3, 5])
    }

    @Test("a file without the keys shows today's tabs: kind subheaders in a project's tab and in All")
    func defaultTabs() async throws {
        let harness = try await Harness.started(config: config(layout: .tabs), graphQL: answer)

        for tab in [MenuTab.project("shop"), .all] {
            let content = harness.shipyard.menu.tabContent(for: tab)
            #expect(content.groups.map(\.title) == ["Pull requests", "Issues"])
            #expect(content.groups.map(\.showsHeader) == [true, true])
            #expect(content.groups.map { $0.rows.map(\.number) } == [[1, 2, 3], [5]])
        }
    }

    @Test("group-by repository: A to Z; author: A to Z; date: newest first; none: one group")
    func groupBy() async throws {
        let harness = try await Harness.started(config: config("group-by = \"repository\""), graphQL: answer)
        #expect(harness.shop?.groups.map(\.title) == [api, web])
        #expect(harness.arranged == [api: [2, 3], web: [1, 5]])

        try harness.writeConfig(config("group-by = \"author\""))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shop?.groups.map(\.title) == ["@octocat", "@yabepa"])
        #expect(harness.arranged == ["@octocat": [2], "@yabepa": [1, 5, 3]])

        try harness.writeConfig(config("group-by = \"date\""))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shop?.groups.map(\.title) == ["Today", "Yesterday", "This week"])
        #expect(harness.arranged == ["Today": [1, 2], "Yesterday": [5], "This week": [3]])

        try harness.writeConfig(config("group-by = \"none\""))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shop?.groups.count == 1)
        #expect(harness.shop?.rows.map(\.number) == [1, 2, 5, 3])
    }

    @Test("sort-by created: newest created first; title: A to Z")
    func sortBy() async throws {
        let harness = try await Harness.started(config: config("sort-by = \"created\""), graphQL: answer)
        #expect(harness.arranged["Pull requests"] == [2, 3, 1])

        try harness.writeConfig(config("sort-by = \"title\""))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.arranged["Pull requests"] == [2, 3, 1])

        try harness.writeConfig(config("sort-by = \"title\"\ngroup-by = \"date\""))
        await harness.shipyard.reloadConfiguration()
        // Sorting by title buckets by the last update.
        #expect(harness.arranged == ["Today": [2, 1], "Yesterday": [5], "This week": [3]])
    }

    @Test("subsections = true in the list shows subheaders; false in tabs shows dividers")
    func subsections() async throws {
        let list = try await Harness.started(config: config("subsections = true"), graphQL: answer)
        #expect(list.shop?.groups.map(\.showsHeader) == [true, true])

        let tabs = try await Harness.started(config: config("subsections = false", layout: .tabs), graphQL: answer)
        #expect(tabs.shipyard.menu.tabContent(for: .project("shop")).groups.map(\.showsHeader) == [false, false])
    }

    @Test("a project's tab is arranged like the list; the All tab keeps its fixed look")
    func tabs() async throws {
        let harness = try await Harness.started(
            config: config("group-by = \"repository\"\nsort-by = \"title\"", layout: .tabs),
            graphQL: answer
        )

        let project = harness.shipyard.menu.tabContent(for: .project("shop"))
        #expect(project.groups.map(\.title) == [api, web])
        // By title across kinds: "A problem" (#5) before "Zebra" (#1).
        #expect(project.groups.map { $0.rows.map(\.number) } == [[2, 3], [5, 1]])
        #expect(project.groups.map(\.showsHeader) == [true, true])

        let all = harness.shipyard.menu.tabContent(for: .all)
        #expect(all.groups.map(\.title) == ["Pull requests", "Issues"])
        #expect(all.groups.map { $0.rows.map(\.number) } == [[1, 2, 3], [5]])
    }

    @Test("a project's own setting overrides the defaults")
    func projectOverrides() async throws {
        let text = "[defaults]\ngroup-by = \"repository\"\nsubsections = true\n\n" + config("group-by = \"none\"")
        let harness = try await Harness.started(config: text, graphQL: answer)

        #expect(harness.shop?.groups.map(\.id.key) == [.ungrouped])
        #expect(harness.shop?.groups.map(\.showsHeader) == [false])
    }
}
