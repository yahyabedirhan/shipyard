import Foundation
@testable import ShipyardCore
import Testing

@Suite("Menu tabs")
struct MenuTabsTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    private func row(
        _ kind: ItemKind,
        _ number: Int,
        repository: String = "yahyabedirhan/shipyard",
        attention: Bool = false
    ) -> MenuRow {
        let path = switch kind {
        case .pullRequest: "pull"
        case .issue: "issues"
        case .workflowRun: "actions/runs"
        }
        return MenuRow(Item(
            kind: kind,
            repository: repository,
            number: number,
            title: "Item \(number)",
            url: URL(string: "https://github.com/\(repository)/\(path)/\(number)")!,
            author: "yahyabedirhan",
            authorKind: .me,
            state: kind == .workflowRun ? .running : .open,
            createdAt: now,
            updatedAt: now
        ), needsAttention: attention)
    }

    private func section(_ name: String, _ rows: [MenuRow], showsRepository: Bool = false, isLoaded: Bool = true) -> MenuSection {
        MenuSection(
            name: name,
            rows: rows,
            showsRepository: showsRepository,
            attentionCount: rows.filter(\.needsAttention).count,
            isLoaded: isLoaded
        )
    }

    private func model(_ sections: [MenuSection]) -> MenuModel {
        let rows = sections.flatMap(\.rows)
        var unique: [String: MenuRow] = [:]
        for row in rows { unique[row.id] = row }
        var counts = AttentionCounts()
        for row in unique.values where row.needsAttention {
            switch row.kind {
            case .pullRequest: counts.pullRequests += 1
            case .issue: counts.issues += 1
            case .workflowRun: counts.workflowRuns += 1
            }
        }
        return MenuModel(sections: sections, attention: counts)
    }

    @Test("the tabs are All, then one per project in configuration order")
    func tabs() {
        let menu = model([section("shipyard", []), section("e-commerce", [])])

        #expect(menu.tabs == [.all, .project("shipyard"), .project("e-commerce")])
    }

    @Test("a tab's count is its project's attention count; All counts a row listed in two projects once")
    func counts() {
        let shared = row(.pullRequest, 1, attention: true)
        let menu = model([
            section("shipyard", [shared, row(.issue, 2, attention: true), row(.issue, 3)]),
            section("mirror", [shared]),
        ])

        #expect(menu.attentionCount(for: .project("shipyard")) == 2)
        #expect(menu.attentionCount(for: .project("mirror")) == 1)
        #expect(menu.attentionCount(for: .all) == 2)
        #expect(menu.attentionCount(for: .project("gone")) == 0)
    }

    @Test("a selected project that was removed from the configuration goes back to All")
    func selectionFallsBack() {
        let menu = model([section("shipyard", [])])

        #expect(menu.resolved(.project("shipyard")) == .project("shipyard"))
        #expect(menu.resolved(.project("gone")) == .all)
        #expect(menu.resolved(.all) == .all)
    }

    @Test("a project's tab groups its rows by kind: pull requests, issues, runs, keeping their order")
    func groups() {
        let menu = model([
            section("shipyard", [
                row(.pullRequest, 1, attention: true), row(.pullRequest, 2),
                row(.workflowRun, 9, attention: true),
            ]),
            section("other", [row(.issue, 5, repository: "yahyabedirhan/other")]),
        ])

        let content = menu.tabContent(for: .project("shipyard"))

        #expect(content.groups.map(\.kind) == [.pullRequest, .workflowRun])
        #expect(content.groups[0].rows.map(\.number) == [1, 2])
        #expect(content.groups[0].attentionCount == 1)
        #expect(content.groups[1].rows.map(\.number) == [9])
        #expect(content.attentionCount == 2)
        #expect(content.projectCount == 1)
    }

    @Test("All lists every project's rows, in project order, a row listed in two projects once")
    func allTab() {
        let shared = row(.pullRequest, 1)
        let menu = model([
            section("shipyard", [shared, row(.issue, 2)]),
            section("other", [row(.pullRequest, 7, repository: "yahyabedirhan/other"), shared]),
        ])

        let content = menu.tabContent(for: .all)

        #expect(content.groups.map(\.kind) == [.pullRequest, .issue])
        #expect(content.groups[0].rows.map(\.number) == [1, 7])
        #expect(content.projectCount == 2)
    }

    @Test("All names each row's repository once it holds more than one project; a project's tab only when it has several repositories")
    func showsRepository() {
        let one = model([section("shipyard", [row(.issue, 1)])])
        let two = model([section("shipyard", [row(.issue, 1)]), section("other", [])])
        let several = model([section("shipyard", [row(.issue, 1)], showsRepository: true), section("other", [])])

        #expect(one.tabContent(for: .all).showsRepository == false)
        #expect(two.tabContent(for: .all).showsRepository == true)
        #expect(two.tabContent(for: .project("shipyard")).showsRepository == false)
        #expect(several.tabContent(for: .project("shipyard")).showsRepository == true)
    }

    @Test("a tab lists its projects' error rows")
    func errors() {
        var broken = section("shipyard", [])
        broken.errors = [MenuErrorRow(RepositoryError(repository: "yahyabedirhan/gone", kind: .notFound, message: ""))]
        let menu = model([broken, section("other", [])])

        #expect(menu.tabContent(for: .all).errors.map(\.repository) == ["yahyabedirhan/gone"])
        #expect(menu.tabContent(for: .project("other")).errors.isEmpty)
    }

    @Test("an empty tab says nothing is open, or not loaded yet while any of its projects isn't")
    func empty() {
        let menu = model([section("shipyard", []), section("new", [], isLoaded: false), section("busy", [row(.issue, 1)])])

        let loading = model([section("shipyard", []), section("new", [], isLoaded: false)])

        #expect(PanelText.emptyTab(menu.tabContent(for: .project("shipyard"))) == "Nothing open")
        #expect(PanelText.emptyTab(menu.tabContent(for: .project("new"))) == "Not loaded yet")
        #expect(PanelText.emptyTab(menu.tabContent(for: .project("busy"))) == nil)
        #expect(PanelText.emptyTab(loading.tabContent(for: .all)) == "Not loaded yet")
        #expect(PanelText.emptyTab(model([section("shipyard", [])]).tabContent(for: .all)) == "Nothing open")
    }

    // MARK: - Words

    @Test("a tab's title is All or its project's name")
    func titles() {
        #expect(PanelText.tabTitle(.all) == "All")
        #expect(PanelText.tabTitle(.project("e-commerce")) == "e-commerce")
    }

    @Test("the line under the tabs counts what needs attention, and All its projects")
    func summary() {
        #expect(PanelText.tabSummary(attention: 5, projects: 4, tab: .all) == "5 need attention · 4 projects")
        #expect(PanelText.tabSummary(attention: 1, projects: 1, tab: .all) == "1 needs attention · 1 project")
        #expect(PanelText.tabSummary(attention: 0, projects: 3, tab: .all) == "All caught up · 3 projects")
        #expect(PanelText.tabSummary(attention: 2, projects: 1, tab: .project("shipyard")) == "2 need attention")
        #expect(PanelText.tabSummary(attention: 0, projects: 1, tab: .project("shipyard")) == "All caught up")
    }

    @Test("All marks every project seen; a project's tab marks it seen")
    func markSeen() {
        #expect(PanelText.markTabSeen(.all) == "Mark all seen")
        #expect(PanelText.markTabSeen(.project("shipyard")) == "Mark seen")
    }

    @Test("a tab's row keeps its age apart, aligned on the right, so its second line leaves it out")
    func rowDetailWithoutAge() {
        let pull = row(.pullRequest, 21)
        let run = row(.workflowRun, 41)

        #expect(PanelText.rowDetail(pull, showingRepository: true) == "#21 · shipyard · yahyabedirhan")
        #expect(PanelText.rowDetail(pull, showingRepository: false) == "#21 · yahyabedirhan")
        #expect(PanelText.rowDetail(run, showingRepository: false) == "#41 · running")
    }

    @Test("each kind's group has a small header")
    func kindHeaders() {
        #expect(PanelText.kindGroup(.pullRequest) == "Pull requests")
        #expect(PanelText.kindGroup(.issue) == "Issues")
        #expect(PanelText.kindGroup(.workflowRun) == "Runs")
    }
}
