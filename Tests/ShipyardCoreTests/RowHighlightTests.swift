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

    @Test("the list layout's rows run top to bottom: each project's header, then its rows while it's expanded; errors and placeholders aren't rows")
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
            .header("shipyard"),
            place("shipyard", shared),
            place("shipyard", issue),
            .header("collapsed"),
            .header("broken"),
            .header("loading"),
            .header("mirror"),
            place("mirror", shared),
        ])
    }

    @Test("a project's header is a place of its own, apart from its rows")
    func headerPlace() {
        #expect(MenuRowPlace.header("shipyard").isHeader)
        #expect(MenuRowPlace.header("shipyard").section == "shipyard")
        #expect(!place("shipyard", row(.pullRequest, 1)).isHeader)
        #expect(MenuRowPlace.header("shipyard") != MenuRowPlace.header("mirror"))
    }

    @Test("a tab's rows run through its kind groups in order, each under its subheader, each row once")
    func tabPlaces() {
        let pull = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        let run = row(.workflowRun, 3)
        let menu = MenuModel(sections: [
            MenuSection(name: "shipyard", rows: [pull, issue, run]),
            MenuSection(name: "mirror", rows: [pull]),
        ])

        #expect(menu.tabContent(for: .all).rowPlaces == [
            .groupHeader(.allTab(.kind(.pullRequest)), in: nil), place(nil, pull),
            .groupHeader(.allTab(.kind(.issue)), in: nil), place(nil, issue),
            .groupHeader(.allTab(.kind(.workflowRun)), in: nil), place(nil, run),
        ])
    }

    // MARK: - ↑ and ↓

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

    @Test("↓ on the last row wraps to the first, and ↑ on the first to the last, like a menu")
    func keysWrap() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[2])

        highlight.moveDown(in: places)
        #expect(highlight.place == places[0])

        highlight.moveUp(in: places)
        #expect(highlight.place == places[2])
    }

    @Test("in a tab, ↓ and ↑ wrap too")
    func keysWrapInTab() {
        let pull = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        let tab = MenuModel(sections: [MenuSection(name: "shipyard", rows: [pull, issue])]).tabContent(for: .all)
        var highlight = RowHighlight()
        highlight.pointerEntered(place(nil, issue))

        highlight.moveDown(in: tab.rowPlaces)
        #expect(highlight.place == .groupHeader(.allTab(.kind(.pullRequest)), in: nil))

        highlight.moveUp(in: tab.rowPlaces)
        #expect(highlight.place == place(nil, issue))
    }

    @Test("a single row stays highlighted when ↓ or ↑ wraps")
    func keysWrapOneRow() {
        let only = [place("shipyard", row(.pullRequest, 1))]
        var highlight = RowHighlight()

        highlight.moveDown(in: only)
        highlight.moveDown(in: only)
        highlight.moveUp(in: only)

        #expect(highlight.place == only[0])
    }

    @Test("↓ steps through headers and items in order: a collapsed, failed or unloaded project gives only its header")
    func keysThroughHeaders() throws {
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

        var visited: [MenuRowPlace] = []
        for _ in 0..<6 {
            highlight.moveDown(in: menu.listRowPlaces)
            visited.append(try #require(highlight.place))
        }

        #expect(visited == [
            .header("collapsed"), .header("broken"), .header("loading"), .header("mirror"), place("mirror", last),
            .header("shipyard"),
        ])
    }

    @Test("in a tab, the keys cross from one kind's group to the next, through its subheader")
    func keysAcrossKindGroups() {
        let pull = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        let tab = MenuModel(sections: [MenuSection(name: "shipyard", rows: [pull, issue])]).tabContent(for: .all)
        var highlight = RowHighlight()
        highlight.pointerEntered(place(nil, pull))

        highlight.moveDown(in: tab.rowPlaces)
        #expect(highlight.place == .groupHeader(.allTab(.kind(.issue)), in: nil))

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

    @Test("a new tab's first row takes the highlight from the keys; an empty tab highlights nothing")
    func moveToFirst() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[2])

        highlight.moveToFirst(in: places)
        #expect(highlight.place == places[0])
        #expect(!highlight.followsPointer)

        highlight.moveToFirst(in: [])
        #expect(highlight.place == nil)
    }

    // MARK: - ← and → in the list layout

    private struct Fold {
        let pull: MenuRow
        let issue: MenuRow
        let menu: MenuModel
    }

    private var fold: Fold {
        let pull = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        return Fold(pull: pull, issue: issue, menu: MenuModel(sections: [
            MenuSection(name: "shipyard", rows: [pull, issue]),
            MenuSection(name: "collapsed", rows: [row(.pullRequest, 3)], isCollapsed: true),
            MenuSection(name: "empty", rows: []),
        ]))
    }

    @Test("← on an item goes to its project's header, without collapsing it")
    func leftOnItem() {
        let fold = fold
        var highlight = RowHighlight()
        highlight.pointerEntered(place("shipyard", fold.issue))

        #expect(highlight.moveLeft(in: fold.menu) == nil)
        #expect(highlight.place == .header("shipyard"))
        #expect(!highlight.followsPointer)
    }

    @Test("← on an expanded header collapses its project and keeps the header highlighted")
    func leftOnExpandedHeader() {
        let fold = fold
        var highlight = RowHighlight()
        highlight.pointerEntered(.header("shipyard"))

        #expect(highlight.moveLeft(in: fold.menu) == .collapse("shipyard"))
        #expect(highlight.place == .header("shipyard"))
        #expect(!highlight.followsPointer)
    }

    @Test("← on a collapsed header does nothing")
    func leftOnCollapsedHeader() {
        let fold = fold
        var highlight = RowHighlight()
        highlight.pointerEntered(.header("collapsed"))

        #expect(highlight.moveLeft(in: fold.menu) == nil)
        #expect(highlight.place == .header("collapsed"))
    }

    @Test("→ on a collapsed header expands its project and keeps the header highlighted")
    func rightOnCollapsedHeader() {
        let fold = fold
        var highlight = RowHighlight()
        highlight.pointerEntered(.header("collapsed"))

        #expect(highlight.moveRight(in: fold.menu) == .expand("collapsed"))
        #expect(highlight.place == .header("collapsed"))
    }

    @Test("→ on an expanded header goes to its first item")
    func rightOnExpandedHeader() {
        let fold = fold
        var highlight = RowHighlight()
        highlight.pointerEntered(.header("shipyard"))

        #expect(highlight.moveRight(in: fold.menu) == nil)
        #expect(highlight.place == place("shipyard", fold.pull))
        #expect(!highlight.followsPointer)
    }

    @Test("→ on an expanded header without items, and → on an item, do nothing")
    func rightWithNowhereToGo() {
        let fold = fold
        var empty = RowHighlight()
        empty.pointerEntered(.header("empty"))
        #expect(empty.moveRight(in: fold.menu) == nil)
        #expect(empty.place == .header("empty"))

        var item = RowHighlight()
        item.pointerEntered(place("shipyard", fold.issue))
        #expect(item.moveRight(in: fold.menu) == nil)
        #expect(item.place == place("shipyard", fold.issue))
    }

    @Test("← and → with nothing highlighted, or on a project that's gone, do nothing")
    func leftRightWithoutHighlight() {
        let fold = fold
        var none = RowHighlight()
        #expect(none.moveLeft(in: fold.menu) == nil)
        #expect(none.moveRight(in: fold.menu) == nil)
        #expect(none.place == nil)

        var gone = RowHighlight()
        gone.pointerEntered(.header("gone"))
        #expect(gone.moveLeft(in: fold.menu) == nil)
        #expect(gone.moveRight(in: fold.menu) == nil)
        #expect(gone.place == .header("gone"))
    }

    // MARK: - Subsections

    private struct Subsections {
        let pulls: RowGroup
        let issues: RowGroup
        let pull: MenuRow
        let issue: MenuRow
        let menu: MenuModel
    }

    /// "shipyard" under two subheaders, pull requests open and issues
    /// folded, then "plain", whose groups are drawn after a divider.
    private var subsections: Subsections {
        let pull = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        let pulls = RowGroup(id: GroupID(project: "shipyard", key: .kind(.pullRequest)), title: "Pull requests", rows: [pull], showsHeader: true)
        let issues = RowGroup(id: GroupID(project: "shipyard", key: .kind(.issue)), title: "Issues", rows: [issue], showsHeader: true, isFolded: true)
        let plain = RowGroup(id: GroupID(project: "plain", key: .kind(.pullRequest)), title: "Pull requests", rows: [row(.pullRequest, 3)])
        return Subsections(pulls: pulls, issues: issues, pull: pull, issue: issue, menu: MenuModel(sections: [
            MenuSection(name: "shipyard", groups: [pulls, issues]),
            MenuSection(name: "plain", groups: [plain]),
        ]))
    }

    @Test("↑ and ↓ stop on subheaders; a folded subsection gives only its subheader; a divider isn't a stop")
    func subheaderPlaces() {
        let s = subsections

        #expect(s.menu.listRowPlaces == [
            .header("shipyard"),
            .groupHeader(s.pulls.id, in: "shipyard"),
            place("shipyard", s.pull),
            .groupHeader(s.issues.id, in: "shipyard"),
            .header("plain"),
            place("plain", row(.pullRequest, 3)),
        ])
        #expect(s.menu.tabContent(for: .project("shipyard")).rowPlaces == [
            .groupHeader(s.pulls.id, in: nil),
            place(nil, s.pull),
            .groupHeader(s.issues.id, in: nil),
        ])

        var highlight = RowHighlight(place: place("shipyard", s.pull))
        highlight.moveDown(in: s.menu.listRowPlaces)
        #expect(highlight.place == .groupHeader(s.issues.id, in: "shipyard"))
        #expect(highlight.place?.isHeader == false)
    }

    @Test("← on an item goes to its subheader; on an open subheader folds it; from a folded one to the project's header")
    func leftOnSubsection() {
        let s = subsections
        var highlight = RowHighlight()
        highlight.pointerEntered(place("shipyard", s.pull))

        #expect(highlight.moveLeft(in: s.menu) == nil)
        #expect(highlight.place == .groupHeader(s.pulls.id, in: "shipyard"))
        #expect(!highlight.followsPointer)

        #expect(highlight.moveLeft(in: s.menu) == .fold(s.pulls.id))
        #expect(highlight.place == .groupHeader(s.pulls.id, in: "shipyard"))

        var folded = RowHighlight(place: .groupHeader(s.issues.id, in: "shipyard"))
        #expect(folded.moveLeft(in: s.menu) == nil)
        #expect(folded.place == .header("shipyard"))

        // Without a subheader, an item goes straight to its project's header.
        var plain = RowHighlight(place: place("plain", row(.pullRequest, 3)))
        #expect(plain.moveLeft(in: s.menu) == nil)
        #expect(plain.place == .header("plain"))
    }

    @Test("→ on a folded subheader unfolds it; on an open one goes to its first item; on a header to its first subheader")
    func rightOnSubsection() {
        let s = subsections
        var folded = RowHighlight(place: .groupHeader(s.issues.id, in: "shipyard"))
        #expect(folded.moveRight(in: s.menu) == .unfold(s.issues.id))
        #expect(folded.place == .groupHeader(s.issues.id, in: "shipyard"))

        var open = RowHighlight(place: .groupHeader(s.pulls.id, in: "shipyard"))
        #expect(open.moveRight(in: s.menu) == nil)
        #expect(open.place == place("shipyard", s.pull))

        var header = RowHighlight(place: .header("shipyard"))
        #expect(header.moveRight(in: s.menu) == nil)
        #expect(header.place == .groupHeader(s.pulls.id, in: "shipyard"))
    }

    @Test("in a tab, ← and → fold and unfold a subheader, and do nothing on an item")
    func tabSubheader() {
        let s = subsections
        let content = s.menu.tabContent(for: .project("shipyard"))

        var open = RowHighlight(place: .groupHeader(s.pulls.id, in: nil))
        #expect(open.moveLeft(in: content) == .fold(s.pulls.id))
        #expect(open.moveRight(in: content) == nil)
        #expect(open.place == place(nil, s.pull))

        var folded = RowHighlight(place: .groupHeader(s.issues.id, in: nil))
        #expect(folded.moveLeft(in: content) == nil)
        #expect(folded.moveRight(in: content) == .unfold(s.issues.id))

        var item = RowHighlight(place: place(nil, s.pull))
        #expect(item.moveLeft(in: content) == nil)
        #expect(item.moveRight(in: content) == nil)
        #expect(item.place == place(nil, s.pull))
    }

    @Test("Return on a subheader folds or unfolds it; a folded subsection's items aren't targets")
    func subheaderTarget() {
        let s = subsections
        let content = s.menu.tabContent(for: .project("shipyard"))

        #expect(s.menu.listTarget(at: .groupHeader(s.pulls.id, in: "shipyard")) == .group(s.pulls))
        #expect(s.menu.listTarget(at: place("shipyard", s.issue)) == nil)
        #expect(content.subsection(at: .groupHeader(s.issues.id, in: nil)) == s.issues)
        #expect(content.subsection(at: place(nil, s.pull)) == nil)
        #expect(content.row(at: place(nil, s.issue)) == nil)
        #expect(content.row(at: .groupHeader(s.pulls.id, in: nil)) == nil)
    }

    // MARK: - ← and → in the tabs layout

    @Test("← and → switch to the previous or next tab, wrapping at the ends")
    func tabSwitch() {
        let menu = MenuModel(sections: [MenuSection(name: "shipyard", rows: []), MenuSection(name: "mirror", rows: [])])

        #expect(menu.tab(beside: .all, by: 1) == .project("shipyard"))
        #expect(menu.tab(beside: .project("shipyard"), by: 1) == .project("mirror"))
        #expect(menu.tab(beside: .project("mirror"), by: 1) == .all)
        #expect(menu.tab(beside: .all, by: -1) == .project("mirror"))
        #expect(menu.tab(beside: .project("shipyard"), by: -1) == .all)
        // A tab whose project was removed counts as All.
        #expect(menu.tab(beside: .project("gone"), by: 1) == .project("shipyard"))
        #expect(MenuModel().tab(beside: .all, by: 1) == .all)
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

    @Test("the pointer onto an error row or a placeholder clears the highlight, even when the last row's exit is lost")
    func pointerOntoErrorRow() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[0])

        // The error row's enter (pointerLeftRows); row 0's exit never arrives.
        highlight.pointerLeftRows()

        #expect(highlight.place == nil)
    }

    @Test("the pointer onto a project's header highlights the header, like a row")
    func pointerOntoHeader() {
        let places = threeRows
        var highlight = RowHighlight()
        highlight.pointerEntered(places[0])

        highlight.pointerEntered(.header("shipyard"))
        highlight.pointerExited(places[0])

        #expect(highlight.place == .header("shipyard"))
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

    // MARK: - What Return acts on

    @Test("Return's target: an item under its expanded project or a project's header in the list; a row among the tab's groups in a tab")
    func targetAtPlace() {
        let pull = row(.pullRequest, 1)
        let issue = row(.issue, 2)
        let shipyard = MenuSection(name: "shipyard", rows: [pull, issue], repositories: ["yahyabedirhan/shipyard"])
        let collapsed = MenuSection(name: "collapsed", rows: [issue], isCollapsed: true)
        let menu = MenuModel(sections: [shipyard, collapsed])
        let tab = menu.tabContent(for: .all)

        #expect(menu.listTarget(at: place("shipyard", issue)) == .item(issue))
        #expect(menu.listTarget(at: place("collapsed", issue)) == nil)
        #expect(menu.listTarget(at: place("gone", pull)) == nil)
        #expect(menu.listTarget(at: .header("shipyard")) == .project(shipyard))
        #expect(menu.listTarget(at: .header("collapsed")) == .project(collapsed))
        #expect(menu.listTarget(at: .header("gone")) == nil)
        #expect(tab.row(at: place(nil, issue)) == issue)
        #expect(tab.row(at: place(nil, row(.pullRequest, 9))) == nil)
    }

    @Test("a project's header opens the first repository listed in the configuration")
    func projectRepositoryURL() {
        let several = MenuSection(name: "shop", rows: [], repositories: ["yahyabedirhan/shop-web", "yahyabedirhan/shop-api"])

        #expect(several.repositoryURL == URL(string: "https://github.com/yahyabedirhan/shop-web"))
        #expect(MenuSection(name: "none", rows: []).repositoryURL == nil)
    }
}
