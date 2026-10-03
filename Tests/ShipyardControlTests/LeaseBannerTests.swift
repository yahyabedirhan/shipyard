import Foundation
import ShipyardControl
import Testing

/// The banner's words while an agent holds the lease, the owner test: who,
/// where, the countdown and the queue, as the maintainer reads them.
@Suite("The lease banner")
struct LeaseBannerTests {
    @Test("the banner names the agent and its place, the time left and how many wait", arguments: [
        (AppStatus.Lease(holder: "Claude Code", place: "/Users/me/shop", secondsLeft: 48, waiting: 0),
         "Claude Code uses shipyard · shop · 48s"),
        (AppStatus.Lease(holder: "codex", place: "Herdr pane w1-2", secondsLeft: 300, waiting: 1),
         "Codex uses shipyard · Herdr pane w1-2 · 5m 00s · 1 waiting"),
        (AppStatus.Lease(holder: "an unknown agent", place: "/", secondsLeft: 65, waiting: 3),
         "An unknown agent uses shipyard · / · 1m 05s · 3 waiting"),
        (AppStatus.Lease(holder: "Claude Code", place: "/Users/me/shop/", secondsLeft: 0, waiting: 0),
         "Claude Code uses shipyard · shop · 0s"),
    ])
    func words(lease: AppStatus.Lease, text: String) {
        let banner = LeaseBanner(lease)

        #expect(banner.text == text)
        #expect(banner.agent == lease.holder)
    }

    @Test("after Stop, the quiet line names the agent taken back from")
    func tookBack() {
        var lease = ControlLease()
        _ = lease.use(by: Holder(key: "process:300@800250000", name: "codex", place: "Herdr pane w1-2"), at: Date(timeIntervalSince1970: 0))
        _ = lease.stop(at: Date(timeIntervalSince1970: 10))

        let lines = lease.stopped(at: Date(timeIntervalSince1970: 20)).map { LeaseBanner.tookBack(from: $0.holder.name) }

        #expect(lines == ["You took shipyard back from codex"])
    }

    @Test("the countdown ticks with the time the banner is made at, from the lease the app holds")
    func countdown() {
        var lease = ControlLease()
        let holder = Holder(key: "CLAUDE_CODE_SESSION_ID=a", name: "Claude Code", place: "/work/shop")
        _ = lease.use(by: holder, at: Date(timeIntervalSince1970: 0))

        let shown = [0, 1, 12, 59.5].map { seconds in
            lease.status(at: Date(timeIntervalSince1970: seconds)).map { LeaseBanner($0).timeLeft }
        }

        #expect(shown == ["1m 00s", "59s", "48s", "1s"])
        // At its end the lease is free, and there's no banner to draw.
        #expect(lease.status(at: Date(timeIntervalSince1970: 60)) == nil)
    }
}
