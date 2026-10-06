import Foundation
@testable import ShipyardApp
import Testing

/// The time the panel draws its banners for. SwiftUI hands a draw before
/// any entry is due the schedule's first date, the end of a snooze an hour
/// away; drawn for that time, a banner just dismissed would stay.
@Suite("Banner draw time")
struct BannerDateTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    @Test("a snooze's end an hour away draws for now, so the dismissed banner hides")
    func futureEntryIsNow() {
        #expect(Panel.bannerDate(now.addingTimeInterval(3600), now: now) == now)
    }

    @Test("an entry that fires a moment early draws for its end, so the banner comes back")
    func earlyEntryIsItsEnd() {
        let end = now.addingTimeInterval(0.4)
        #expect(Panel.bannerDate(end, now: now) == end)
    }

    @Test("an entry already passed draws for now")
    func pastEntryIsNow() {
        #expect(Panel.bannerDate(now.addingTimeInterval(-60), now: now) == now)
    }
}
