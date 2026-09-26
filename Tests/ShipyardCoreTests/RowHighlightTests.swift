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

    // MARK: - The keys (#45)

    private var threeRows: [MenuRowPlace] {
        [place("shipyard", row(.pullRequest, 1)), place("shipyard", row(.issue, 2)), place("mirror", row(.pullRequest, 1))]
    }

    @Test("↓ with nothing highlighted highlights the first row; ↑ the last")
    func keysStart() {
        let places = threeRows
        var down = RowHighlight()
        var up = RowHighlight()

        down.moveDown(in: places)
        up.moveUp(in: places)

        #expect(down.place == places[0])
        #expect(up.place == places[2])
    }

    @Test("↓ and ↑ move row by row, across projects")
    func keysStep() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[1])

        highlight.moveDown(in: places)
        #expect(highlight.place == places[2])

        highlight.moveUp(in: places)
        highlight.moveUp(in: places)
        #expect(highlight.place == places[0])
    }

    @Test("the keys stop at the first and the last row")
    func keysStopAtEnds() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[2])
        highlight.moveDown(in: places)
        #expect(highlight.place == places[2])

        var top = RowHighlight()
        top.pointerEntered(places[0])
        top.moveUp(in: places)
        #expect(top.place == places[0])
    }

    @Test("the keys cross from one project to the next, skipping collapsed projects, error rows and unloaded projects")
    func keysSkipNonRows() {
        let first = row(.pullRequest, 1)
        let hidden = row(.pullRequest, 3, repository: "yahyabedirhan/hidden")
        let last = row(.issue, 4, repository: "yahyabedirhan/mirror")
        var broken = MenuSection(name: "broken", rows: [])
        broken.errors = [MenuErrorRow(RepositoryError(repository: "yahyabedirhan/gone", kind: .notFound, message: ""))]
        let menu = MenuModel(sections: [
            MenuSection(name: "shipyard", rows: [first]),
            MenuSection(name: "collapsed", rows: [hidden], isCollapsed: true),
            broken,
            MenuSection(name: "loading", rows: [], isLoaded: false),
            MenuSection(name: "mirror", rows: [last]),
        ])
        var highlight = RowHighlight()
        highlight.pointerEntered(place("shipyard", first))

        highlight.moveDown(in: menu.listRowPlaces)
        #expect(highlight.place == place("mirror", last))

        highlight.moveUp(in: menu.listRowPlaces)
        #expect(highlight.place == place("shipyard", first))
    }

    @Test("in a tab, the keys cross from one kind's group to the next")
    func keysAcrossKindGroups() {
        let pull = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        let tab = MenuModel(sections: [MenuSection(name: "shipyard", rows: [pull, issue])]).tabContent(for: .all)
        var highlight = RowHighlight()
        highlight.pointerEntered(place(nil, pull))

        highlight.moveDown(in: tab.rowPlaces)

        #expect(highlight.place == place(nil, issue))
    }

    @Test("with no rows, the keys highlight nothing")
    func keysNoRows() {
        var highlight = RowHighlight()

        highlight.moveDown(in: [])
        highlight.moveUp(in: [])

        #expect(highlight.place == nil)
    }

    @Test("a highlighted row that's no longer listed: ↓ starts again from the first row")
    func keysFromGoneRow() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(place("gone", row(.pullRequest, 9)))

        highlight.moveDown(in: places)

        #expect(highlight.place == places[0])
    }

    // MARK: - The pointer and the keys share one highlight

    @Test("the keys continue from the row the pointer highlighted")
    func keysContinueFromPointer() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[0])

        highlight.moveDown(in: places)

        #expect(highlight.place == places[1])
    }

    @Test("rows scrolling under a resting pointer don't take the highlight from the keys")
    func scrollUnderRestingPointer() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[0])
        highlight.moveDown(in: places)

        // The list scrolls to the highlighted row, moving rows and headers under the pointer.
        highlight.pointerExited(places[0])
        highlight.pointerEntered(places[2])
        highlight.pointerLeftRows()

        #expect(highlight.place == places[1])
    }

    @Test("moving the pointer after the keys takes the highlight to the row under it")
    func pointerTakesOver() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[0])
        highlight.moveDown(in: places)
        highlight.pointerExited(places[0])
        highlight.pointerEntered(places[2])

        highlight.pointerMoved()

        #expect(highlight.place == places[2])
        // It follows the pointer again.
        highlight.pointerEntered(places[0])
        #expect(highlight.place == places[0])
    }

    @Test("moving the pointer after the keys, when it isn't on a row, clears the highlight")
    func pointerTakesOverOffRows() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[0])
        highlight.moveDown(in: places)
        highlight.pointerLeftRows()

        highlight.pointerMoved()

        #expect(highlight.place == nil)
    }

    @Test("the pointer onto a header or an error row clears the highlight, even when the last row's exit is lost")
    func pointerOntoHeader() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[0])

        // The header's enter (pointerLeftRows); row 0's exit never arrives.
        highlight.pointerLeftRows()

        #expect(highlight.place == nil)
    }

    @Test("a row gone from the list isn't brought back when the pointer moves")
    func goneRowNotRestored() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[0])
        highlight.moveDown(in: places)

        highlight.keep(in: [places[1]])
        highlight.pointerMoved()

        #expect(highlight.place == nil)
    }

    // MARK: - The highlighted row's item

    @Test("a place finds its row: under its expanded project in the list, among the tab's groups in a tab")
    func rowAtPlace() {
        let pull = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        let menu = MenuModel(sections: [
            MenuSection(name: "shipyard", rows: [pull, issue]),
            MenuSection(name: "collapsed", rows: [issue], isCollapsed: true),
        ])
        let tab = menu.tabContent(for: .all)

        #expect(menu.listRow(at: place("shipyard", issue)) == issue)
        #expect(menu.listRow(at: place("collapsed", issue)) == nil)
        #expect(menu.listRow(at: place("gone", pull)) == nil)
        #expect(tab.row(at: place(nil, issue)) == issue)
        #expect(tab.row(at: place(nil, row(.pullRequest, 9))) == nil)
    }
}
