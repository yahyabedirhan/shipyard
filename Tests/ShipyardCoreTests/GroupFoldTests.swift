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

/// One project, "shop", over two repositories with issues shown, arranged
/// by `settings` under `[menu] layout`; `more` adds lines after it (another
/// project).
private func config(_ settings: String = "subsections = true", layout: MenuLayout = .list, more: String = "") -> String {
    """
    [menu]
    layout = "\(layout.rawValue)"

    [defaults.issues]
    show = true

    [[projects]]
    name = "shop"
    repositories = ["\(web)", "\(api)"]
    \(settings)

    \(more)
    """
}

/// Web: PRs #1 and #2, issue #5; api: PR #3.
private let answer = PullRequestsResponse.answer([
    PullRequestsResponse(web, [PR(1), PR(2)], issues: [Issue(5)]),
    PullRequestsResponse(api, [PR(3)], issues: []),
])

private let pullRequests = GroupID(project: "shop", key: .kind(.pullRequest))
private let issues = GroupID(project: "shop", key: .kind(.issue))

@MainActor
private extension Harness {
    var shop: MenuSection? { section("shop") }

    func group(_ id: GroupID) -> RowGroup? {
        shop?.groups.first { $0.id == id }
    }

    /// `collapsedGroups` as `state.json` has it.
    var savedFolds: [[String: String]]? {
        guard let data = try? Data(contentsOf: stateURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["collapsedGroups"] as? [[String: String]]
    }
}

// A subsection (a group under a subheader) folds and unfolds like a
// project: the fold is app state, survives a relaunch, and is pruned with
// its group or its project. A group drawn after a divider doesn't fold.
@MainActor
@Suite("Folding a subsection")
struct GroupFoldTests {
    @Test("folding a subsection keeps its rows and its count; folding it again unfolds it")
    func toggle() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        let before = try #require(harness.group(pullRequests))
        #expect(before.showsHeader)
        #expect(!before.isFolded)

        harness.shipyard.toggleGroup(pullRequests)

        let folded = try #require(harness.group(pullRequests))
        #expect(folded.isFolded)
        #expect(folded.rows == before.rows)
        #expect(folded.attentionCount == before.attentionCount)
        #expect(harness.group(issues)?.isFolded == false)
        // Its rows still count, in the project and in the menu bar.
        #expect(harness.shop?.attentionCount == 4)
        #expect(harness.shipyard.menu.menuBarLabel == .total(4))
        // No refresh: only the app state changed.
        #expect(harness.graphQLRequests.count == 1)

        harness.shipyard.toggleGroup(pullRequests)
        #expect(harness.group(pullRequests)?.isFolded == false)
    }

    @Test("a folded subsection gives only its subheader to the keys")
    func foldedPlaces() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        harness.shipyard.toggleGroup(pullRequests)

        let places = harness.shipyard.menu.listRowPlaces
        #expect(places == [
            .header("shop"),
            .groupHeader(pullRequests, in: "shop"),
            .groupHeader(issues, in: "shop"),
            MenuRowPlace(section: "shop", row: Issue(5).url(in: web).absoluteString),
        ])
    }

    @Test("a group drawn after a divider can't be folded")
    func dividersDontFold() async throws {
        let harness = try await Harness.started(config: config(""), graphQL: answer)
        #expect(harness.group(pullRequests)?.showsHeader == false)

        harness.shipyard.toggleGroup(pullRequests)

        #expect(harness.group(pullRequests)?.isFolded == false)
        #expect(harness.shipyard.appStateStore.state.collapsedGroups.isEmpty)
        #expect(harness.shipyard.menu.listRowPlaces.allSatisfy { $0.group == nil })
    }

    @Test("a fold kept while subsections are off comes back when they're on again")
    func dividersKeepTheFold() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        harness.shipyard.toggleGroup(pullRequests)

        harness.graphQL([answer])
        try harness.writeConfig(config("subsections = false"))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.group(pullRequests)?.isFolded == false)

        try harness.writeConfig(config())
        await harness.shipyard.reloadConfiguration()
        #expect(harness.group(pullRequests)?.isFolded == true)
    }

    @Test("a fold survives a relaunch, and is saved in state.json")
    func survivesRelaunch() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        harness.shipyard.toggleGroup(issues)
        #expect(harness.savedFolds == [["project": "shop", "group": "kind:issue"]])

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([answer])
        await relaunched.shipyard.start()

        #expect(relaunched.group(issues)?.isFolded == true)
        #expect(relaunched.group(pullRequests)?.isFolded == false)
    }

    @Test("a fold whose group is gone is pruned after a refresh")
    func prunedWithItsGroup() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        harness.shipyard.toggleGroup(issues)
        harness.shipyard.toggleGroup(pullRequests)

        // The issue was closed: its group is gone, and so is its fold.
        harness.graphQL([PullRequestsResponse.answer([
            PullRequestsResponse(web, [PR(1), PR(2)], issues: []),
            PullRequestsResponse(api, [PR(3)], issues: []),
        ])])
        await harness.timer.fire()

        #expect(harness.shipyard.appStateStore.state.collapsedGroups == [pullRequests])
        #expect(harness.savedFolds == [["project": "shop", "group": "kind:pullRequest"]])
    }

    @Test("grouped another way, the old groups' folds are pruned")
    func prunedWhenRegrouped() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        harness.shipyard.toggleGroup(issues)

        harness.graphQL([answer])
        try harness.writeConfig(config("subsections = true\ngroup-by = \"repository\""))
        await harness.shipyard.reloadConfiguration()

        #expect(harness.shipyard.appStateStore.state.collapsedGroups.isEmpty)
        let byRepository = GroupID(project: "shop", key: .repository(api))
        harness.shipyard.toggleGroup(byRepository)
        #expect(harness.group(byRepository)?.isFolded == true)
    }

    @Test("a removed project's folds are pruned with it")
    func prunedWithItsProject() async throws {
        let blog = """
        [[projects]]
        name = "blog"
        repositories = ["yahyabedirhan/blog"]
        subsections = true
        """
        let harness = try await Harness.started(config: config(more: blog), graphQL: PullRequestsResponse.answer([
            PullRequestsResponse(web, [PR(1)], issues: []),
            PullRequestsResponse(api, [], issues: []),
            PullRequestsResponse("yahyabedirhan/blog", [PR(9)], issues: []),
        ]))
        let blogPulls = GroupID(project: "blog", key: .kind(.pullRequest))
        harness.shipyard.toggleGroup(blogPulls)
        harness.shipyard.toggleGroup(pullRequests)
        #expect(harness.shipyard.appStateStore.state.collapsedGroups == [blogPulls, pullRequests])

        harness.graphQL([PullRequestsResponse.answer([
            PullRequestsResponse(web, [PR(1)], issues: []),
            PullRequestsResponse(api, [], issues: []),
        ])])
        try harness.writeConfig(config())
        await harness.shipyard.reloadConfiguration()

        #expect(harness.shipyard.appStateStore.state.collapsedGroups == [pullRequests])
    }

    @Test("a failed refresh, or a project with a repository that failed, keeps its folds")
    func keptWhileFailing() async throws {
        let harness = try await Harness.started(config: config(), graphQL: answer)
        harness.shipyard.toggleGroup(issues)

        harness.graphQL([.failure()])
        await harness.timer.fire()
        #expect(harness.shipyard.menu.fetchError != nil)
        #expect(harness.shipyard.appStateStore.state.collapsedGroups == [issues])

        // Web, which has the issue, can't be fetched: the group may come back.
        harness.graphQL([PullRequestsResponse.answer([
            PullRequestsResponse(web, [], missing: true),
            PullRequestsResponse(api, [PR(3)], issues: []),
        ])])
        await harness.timer.fire()
        #expect(harness.shop?.errors.isEmpty == false)
        #expect(harness.group(issues) == nil)
        #expect(harness.shipyard.appStateStore.state.collapsedGroups == [issues])
    }

    @Test("the All tab's subheaders fold on their own, apart from a project's tab")
    func allTab() async throws {
        let harness = try await Harness.started(config: config("", layout: .tabs), graphQL: answer)
        let allIssues = GroupID.allTab(.kind(.issue))

        harness.shipyard.toggleGroup(allIssues)

        let all = harness.shipyard.menu.tabContent(for: .all)
        #expect(all.groups.map(\.isFolded) == [false, true])
        #expect(all.rowPlaces.last == .groupHeader(allIssues, in: nil))
        #expect(harness.shipyard.menu.tabContent(for: .project("shop")).groups.map(\.isFolded) == [false, false])

        // Kept after a refresh while the All tab lists issues.
        harness.graphQL([answer])
        await harness.timer.fire()
        #expect(harness.shipyard.appStateStore.state.collapsedGroups == [allIssues])
    }
}
