@testable import ShipyardApp
import CoreGraphics
import Testing

@Suite("Tab strip scroll")
struct TabStripScrollTests {
    private let width: CGFloat = 376
    private let fade: CGFloat = 24

    /// Where the tab's leading edge lands once the strip scrolls to the anchor.
    private func landing(_ tab: ClosedRange<CGFloat>) -> CGFloat? {
        guard let anchor = TabStripScroll.anchor(revealing: tab, in: width, fade: fade) else { return nil }
        return (anchor.x * (width - (tab.upperBound - tab.lowerBound))).rounded()
    }

    @Test("a picked tab clear of the faded edges leaves the strip where it is", arguments: [
        CGFloat(24)...CGFloat(80), CGFloat(150)...CGFloat(230), CGFloat(290)...CGFloat(352),
    ])
    func inView(tab: ClosedRange<CGFloat>) {
        #expect(TabStripScroll.anchor(revealing: tab, in: width, fade: fade) == nil)
    }

    @Test("a tab cut off at the trailing edge moves in just far enough to clear the fade")
    func trailing() {
        #expect(landing(330...410) == CGFloat(272))
        #expect(landing(340...380) == CGFloat(312))
    }

    @Test("a tab cut off at the leading edge moves in just far enough to clear the fade")
    func leading() {
        #expect(landing(-60...20) == 24)
        #expect(landing(10...60) == 24)
    }
}
