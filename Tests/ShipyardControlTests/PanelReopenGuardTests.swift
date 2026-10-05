import Foundation
import ShipyardControl
import Testing

/// App control's wait after the user closes the panel, the owner test:
/// closes at given times (seconds from a fake clock's start), and what an
/// open by app control gets after them.
@Suite("Reopening the panel")
struct PanelReopenGuardTests {
    static let utc = TimeZone(identifier: "UTC")!

    static func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    @Test("after the user closes the panel, app control can't open it for 30 seconds; after app control closes it, at once")
    func cooldown() {
        var guarding = PanelReopenGuard()
        #expect(guarding.refusal(at: Self.at(0), timeZone: Self.utc) == nil)

        guarding.panelClosed(byControl: false, at: Self.at(100))
        #expect(guarding.refusal(at: Self.at(101), timeZone: Self.utc) == "you closed the panel 1 second ago; app control can open it again at 00:02:10")
        #expect(guarding.refusal(at: Self.at(129), timeZone: Self.utc) == "you closed the panel 29 seconds ago; app control can open it again at 00:02:10")
        #expect(guarding.refusal(at: Self.at(130), timeZone: Self.utc) == nil)

        // The user closing it again starts the wait again; app control's own close ends it.
        guarding.panelClosed(byControl: false, at: Self.at(200))
        #expect(guarding.refusal(at: Self.at(205), timeZone: Self.utc) != nil)
        guarding.panelClosed(byControl: true, at: Self.at(206))
        #expect(guarding.refusal(at: Self.at(207), timeZone: Self.utc) == nil)
    }
}
