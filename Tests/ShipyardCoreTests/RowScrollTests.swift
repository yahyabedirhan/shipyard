@testable import ShipyardCore
import Testing

/// How the list scrolls to keep the row the keys highlighted in view (#45):
/// not at all while it's visible, just enough to show it otherwise, and
/// clear of the pinned project header.
@Suite("Row scroll")
struct RowScrollTests {
    private let item = MenuRowPlace(section: "shipyard", row: "https://github.com/yahyabedirhan/shipyard/pull/2")
    private let next = MenuRowPlace(section: "shipyard", row: "https://github.com/yahyabedirhan/shipyard/pull/3")
    private var places: [MenuRowPlace] { [.header("shipyard"), item, next] }

    /// A 560 pt list, 26 pt headers, 24 pt rows.
    private func reveal(_ target: MenuRowPlace, from previous: MenuRowPlace?, top: Double?, pinnedHeader: Double = 26) -> RowScroll {
        RowScroll.reveal(
            target,
            from: previous,
            in: places,
            frame: top.map { RowSpan(top: $0, bottom: $0 + (target.isHeader ? 26 : 24)) },
            visibleHeight: 560,
            pinnedHeader: pinnedHeader
        )
    }

    @Test("a row in full view doesn't scroll the list")
    func visibleStays() {
        #expect(reveal(next, from: item, top: 200) == .stay)
        #expect(reveal(next, from: item, top: 536) == .stay)
        #expect(reveal(item, from: next, top: 26) == .stay)
    }

    @Test("a row past the bottom edge scrolls just enough to sit on it")
    func belowScrollsToBottom() {
        #expect(reveal(next, from: item, top: 540) == .alignBottom)
        #expect(reveal(next, from: item, top: 700) == .alignBottom)
    }

    @Test("a row above the top, or under the pinned header, scrolls to sit just below the header")
    func aboveScrollsBelowHeader() {
        let belowHeader = RowScroll.alignTop(anchor: 26.0 / (560 - 24))

        #expect(reveal(item, from: next, top: -30) == belowHeader)
        #expect(reveal(item, from: next, top: 10) == belowHeader)
    }

    @Test("the tabs layout has no pinned header: a row above the top scrolls to the very top")
    func noPinnedHeader() {
        #expect(reveal(item, from: next, top: -30, pinnedHeader: 0) == .alignTop(anchor: 0))
        #expect(reveal(item, from: next, top: 0, pinnedHeader: 0) == .stay)
    }

    @Test("a project's header pinned at the top is in view; one scrolled above goes to the very top, where it pins")
    func headers() {
        #expect(reveal(.header("shipyard"), from: item, top: 0) == .stay)
        #expect(reveal(.header("shipyard"), from: item, top: -40) == .alignTop(anchor: 0))
    }

    @Test("a row the list hasn't laid out yet is scrolled to by the way the highlight moved: up to the top, down to the bottom")
    func notLaidOut() {
        // ↓ wrapping from the last row to the first.
        #expect(reveal(.header("shipyard"), from: next, top: nil) == .alignTop(anchor: 0))
        // ↑ from the header wrapping to the last row.
        #expect(reveal(next, from: .header("shipyard"), top: nil) == .alignBottom)
        // An item above: below the pinned header, near enough without its height.
        #expect(reveal(item, from: next, top: nil) == .alignTop(anchor: 26.0 / 560))
    }

    @Test("with nothing highlighted before, a row not laid out goes to the top if it's the first, else to the bottom")
    func notLaidOutFromNothing() {
        #expect(reveal(.header("shipyard"), from: nil, top: nil) == .alignTop(anchor: 0))
        #expect(reveal(next, from: nil, top: nil) == .alignBottom)
    }

    @Test("a list shorter than the row shows the row's top; a short one keeps the anchor in range")
    func shortList() {
        let tiny = RowScroll.reveal(
            item, from: next, in: places, frame: RowSpan(top: -10, bottom: 14), visibleHeight: 20, pinnedHeader: 26
        )
        let short = RowScroll.reveal(
            item, from: next, in: places, frame: RowSpan(top: -10, bottom: 14), visibleHeight: 40, pinnedHeader: 26
        )

        #expect(tiny == .alignTop(anchor: 0))
        #expect(short == .alignTop(anchor: 1))
    }
}
