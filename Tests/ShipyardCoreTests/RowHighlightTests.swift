import Foundation
@testable import ShipyardCore
import Testing

@Suite("Row highlight")
struct RowHighlightTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    private func row(_ kind: ItemKind, _ number: Int, repository: String = "yahyabedirhan/shipyard") -> MenuRow {
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
        ))
    }

    private func place(_ section: String?, _ row: MenuRow) -> MenuRowPlace {
        MenuRowPlace(section: section, row: row.id)
    }

    // MARK: - The pointer

    @Test("nothing is highlighted before the pointer enters a row")
    func startsEmpty() {
        #expect(RowHighlight().place == nil)
    }

    @Test("the row the pointer enters is highlighted")
    func enter() {
        let a = place("shipyard", row(.pullRequest, 1))
        var highlight = RowHighlight()

        highlight.pointerEntered(a)

        #expect(highlight.place == a)
        #expect(highlight.isHighlighted(a))
    }

    @Test("moving down, the next row's enter arriving before the last row's exit still leaves the next row highlighted")
    func enterBeforeExit() {
        let a = place("shipyard", row(.pullRequest, 1))
        let b = place("shipyard", row(.pullRequest, 2))
        var highlight = RowHighlight()
        highlight.pointerEntered(a)

        highlight.pointerEntered(b)
        highlight.pointerExited(a)

        #expect(highlight.place == b)
        #expect(!highlight.isHighlighted(a))
    }

    @Test("moving down, the last row's exit arriving first, then the next row's enter, highlights the next row")
    func exitBeforeEnter() {
        let a = place("shipyard", row(.pullRequest, 1))
        let b = place("shipyard", row(.pullRequest, 2))
        var highlight = RowHighlight()
        highlight.pointerEntered(a)

        highlight.pointerExited(a)
        highlight.pointerEntered(b)

        #expect(highlight.place == b)
    }

    @Test("leaving the highlighted row clears the highlight")
    func exitClears() {
        let a = place("shipyard", row(.pullRequest, 1))
        var highlight = RowHighlight()
        highlight.pointerEntered(a)

        highlight.pointerExited(a)

        #expect(highlight.place == nil)
    }

    @Test("leaving the list clears the highlight, even when the last row's exit never arrived")
    func leaveList() {
        let a = place("shipyard", row(.pullRequest, 1))
        var highlight = RowHighlight()
        highlight.pointerEntered(a)

        highlight.pointerLeftRows()

        #expect(highlight.place == nil)
    }

    @Test("an item listed under two projects is highlighted only where the pointer is")
    func sameItemTwoProjects() {
        let shared = row(.pullRequest, 1)
        let inShipyard = place("shipyard", shared)
        let inMirror = place("mirror", shared)
        var highlight = RowHighlight()

        highlight.pointerEntered(inMirror)

        #expect(highlight.isHighlighted(inMirror))
        #expect(!highlight.isHighlighted(inShipyard))
    }

    // MARK: - The rows changing under it

    @Test("a highlighted row that's no longer listed (collapsed, filtered out, another tab) loses the highlight")
    func rowGone() {
        let a = place("shipyard", row(.pullRequest, 1))
        let b = place("shipyard", row(.pullRequest, 2))
        var highlight = RowHighlight()
        highlight.pointerEntered(a)

        highlight.keep(in: [b])

        #expect(highlight.place == nil)
    }

    @Test("a highlighted row still listed keeps the highlight when the rows change")
    func rowStays() {
        let a = place("shipyard", row(.pullRequest, 1))
        let b = place("shipyard", row(.pullRequest, 2))
        var highlight = RowHighlight()
        highlight.pointerEntered(a)

        highlight.keep(in: [b, a])

        #expect(highlight.place == a)
    }

    // MARK: - The rows a highlight can rest on

    @Test("the list layout's rows run top to bottom through the expanded projects, skipping collapsed ones, errors and unloaded projects")
    func listPlaces() {
        let shared = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        let hidden = row(.pullRequest, 3, repository: "yahyabedirhan/hidden")
        var broken = MenuSection(name: "broken", rows: [])
        broken.errors = [MenuErrorRow(RepositoryError(repository: "yahyabedirhan/gone", kind: .notFound, message: ""))]
        let menu = MenuModel(sections: [
            MenuSection(name: "shipyard", rows: [shared, issue]),
            MenuSection(name: "collapsed", rows: [hidden], isCollapsed: true),
            broken,
            MenuSection(name: "loading", rows: [], isLoaded: false),
            MenuSection(name: "mirror", rows: [shared]),
        ])

        #expect(menu.listRowPlaces == [
            place("shipyard", shared),
            place("shipyard", issue),
            place("mirror", shared),
        ])
    }

    @Test("a tab's rows run through its kind groups in order, each row once")
    func tabPlaces() {
        let pull = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        let run = row(.workflowRun, 3)
        let menu = MenuModel(sections: [
            MenuSection(name: "shipyard", rows: [pull, issue, run]),
            MenuSection(name: "mirror", rows: [pull]),
        ])

        #expect(menu.tabContent(for: .all).rowPlaces == [place(nil, pull), place(nil, issue), place(nil, run)])
    }
}
