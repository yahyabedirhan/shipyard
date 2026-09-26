@testable import ShipyardCore
import Testing

/// How the list scrolls to keep the row the keys highlighted in view:
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
        // An item above: below the pinned header, near enough without its height.
        #expect(reveal(item, from: next, top: nil) == .alignTop(anchor: 26.0 / 560))
        // An item below.
        #expect(reveal(next, from: item, top: nil) == .alignBottom)
    }

    @Test("↓ from the last row wraps to the first: the list goes straight to its top, laid out or not")
    func wrapToTop() {
        #expect(reveal(.header("shipyard"), from: next, top: nil) == .wrapToTop)
        #expect(reveal(.header("shipyard"), from: next, top: -400) == .wrapToTop)
        #expect(reveal(.header("shipyard"), from: next, top: 0) == .wrapToTop)
    }

    @Test("↑ from the first row wraps to the last: the list goes straight to its bottom, laid out or not")
    func wrapToBottom() {
        #expect(reveal(next, from: .header("shipyard"), top: nil) == .wrapToBottom)
        #expect(reveal(next, from: .header("shipyard"), top: 900) == .wrapToBottom)
        #expect(reveal(next, from: .header("shipyard"), top: 300) == .wrapToBottom)
    }

    @Test("a list of one row doesn't wrap")
    func oneRowDoesNotWrap() {
        let only = RowScroll.reveal(item, from: item, in: [item], frame: RowSpan(top: 0, bottom: 24), visibleHeight: 560, pinnedHeader: 0)

        #expect(only == .stay)
    }

    @Test("from a pinned header to its first item not laid out: just below the header, not to the bottom")
    func fromPinnedHeaderToFirstItem() {
        // Scrolled into the middle of the project, its first item is above
        // the visible area, under the header pinned at the top.
        #expect(reveal(item, from: .header("shipyard"), top: nil) == .alignTop(anchor: 26.0 / 560))
        // A row further down still goes the way the highlight moved.
        #expect(RowScroll.reveal(
            next, from: .header("shipyard"), in: places + [.header("other")], frame: nil, visibleHeight: 560, pinnedHeader: 26
        ) == .alignBottom)
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

    @Test("a wrap to the bottom keeps scrolling to the end until its row lands in full view")
    func wrapLandsAtBottom() {
        var landing = RowWrapLanding(.wrapToBottom, to: next)
        // The lazy stack guessed the rows above too short: once they're
        // laid out, the last row is still below the list's bottom edge.
        #expect(landing?.check(frame: RowSpan(top: 580, bottom: 604), visibleHeight: 560) == .scrollAgain)
        // Not laid out at all yet: short of the end too.
        #expect(landing?.check(frame: nil, visibleHeight: 560) == .scrollAgain)
        #expect(landing?.check(frame: RowSpan(top: 533, bottom: 557), visibleHeight: 560) == .landed)
    }

    @Test("a wrap to the top lands once its row is in full view at the top")
    func wrapLandsAtTop() {
        var landing = RowWrapLanding(.wrapToTop, to: .header("shipyard"))

        #expect(landing?.check(frame: RowSpan(top: -26, bottom: 0), visibleHeight: 560) == .scrollAgain)
        #expect(landing?.check(frame: RowSpan(top: 0, bottom: 26), visibleHeight: 560) == .landed)
    }

    @Test("a wrap that doesn't land after a few scrolls gives up, so it can't hold the list")
    func wrapGivesUp() {
        var landing = RowWrapLanding(.wrapToBottom, to: next)
        var steps: [RowWrapLanding.Step] = []
        for _ in 0..<5 {
            steps.append(landing!.check(frame: nil, visibleHeight: 560))
        }

        #expect(steps == [.scrollAgain, .scrollAgain, .scrollAgain, .scrollAgain, .giveUp])
    }

    @Test("only a wrap is followed until it lands")
    func onlyWrapsLand() {
        #expect(RowWrapLanding(.alignBottom, to: next) == nil)
        #expect(RowWrapLanding(.stay, to: next) == nil)
    }
}
