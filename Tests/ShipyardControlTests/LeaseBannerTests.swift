import Foundation
import ShipyardControl
import Testing

/// The banner's words while an agent holds the lease, the owner test: who,
/// why, the step, the countdown, the queue and where, as the maintainer reads them.
@Suite("The lease banner")
struct LeaseBannerTests {
    @Test("the banner heads with the purpose or the agent, over its step and how many wait", arguments: [
        (AppStatus.Lease(holder: "Claude Code", place: "/Users/me/shop", secondsLeft: 48, waiting: 0),
         "Claude Code uses shipyard", nil as String?, "48s left", "Claude Code in shop"),
        (AppStatus.Lease(holder: "codex", place: "Herdr pane w1-2", secondsLeft: 300, waiting: 1),
         "Codex uses shipyard", "1 waiting", "5m 00s left", "codex in Herdr pane w1-2"),
        (AppStatus.Lease(holder: "an unknown agent", place: "/", secondsLeft: 65, waiting: 3,
                         step: "Taking a screenshot…"),
         "An unknown agent uses shipyard", "Taking a screenshot… · 3 waiting", "1m 05s left", "an unknown agent in /"),
        (AppStatus.Lease(holder: "Claude Code", place: "/Users/me/shop/", secondsLeft: 0, waiting: 0),
         "Claude Code uses shipyard", nil, "0s left", "Claude Code in shop"),
        (AppStatus.Lease(holder: "codex", place: "/Users/me/shop", secondsLeft: 48, waiting: 2,
                         purpose: "checking the header icons", step: "Took a screenshot · 12s ago"),
         "Checking the header icons", "Took a screenshot · 12s ago · 2 waiting", "48s left", "codex in shop"),
    ])
    func words(lease: AppStatus.Lease, headline: String, detail: String?, timeLeft: String, help: String) {
        let banner = LeaseBanner(lease)

        #expect(banner.headline == headline)
        #expect(banner.detail == detail)
        #expect(banner.timeLeft == timeLeft)
        #expect(banner.help == help)
        #expect(banner.text == ([headline, detail, timeLeft, help].compactMap { $0 }).joined(separator: " · "))
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

        #expect(shown == ["1m 00s left", "59s left", "48s left", "1s left"])
        // At its end the lease is free, and there's no banner to draw.
        #expect(lease.status(at: Date(timeIntervalSince1970: 60)) == nil)
    }
}
