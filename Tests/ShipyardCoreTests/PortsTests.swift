import Foundation
import ShipyardCore
import Testing

// The doubles later tests drive the orchestrator with. These check they
// behave like the real services they stand in for.
@Suite("Port doubles")
struct PortsTests {
    @Test("the token store keeps, replaces and deletes one token")
    func tokenStore() throws {
        let store: any TokenStore = InMemoryTokenStore()
        #expect(try store.token() == nil)
        try store.save("gho_first")
        try store.save("gho_second")
        #expect(try store.token() == "gho_second")
        try store.delete()
        try store.delete()
        #expect(try store.token() == nil)
    }

    @Test("the notifier records posts in order")
    func notifier() async {
        let notifier = RecordingNotifier()
        let url = URL(string: "https://github.com/yahyabedirhan/shipyard/pull/7")!
        let first = PostedNotification(id: "pr.opened#7", title: "shipyard · New PR #7", body: "Add core", itemURL: url)
        let second = PostedNotification(id: "pr.merged#7", title: "shipyard · Merged PR #7", body: "Add core", itemURL: url)
        await notifier.post(first)
        await notifier.post(second)
        #expect(notifier.posted == [first, second])
    }

    @Test("the clock stays put until moved")
    func clock() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let clock = ManualClock(start)
        #expect(clock.now == start)
        clock.advance(by: 120)
        #expect(clock.now == start.addingTimeInterval(120))
    }

    @Test("the system clock tells the real time")
    func systemClock() {
        let before = Date()
        let now = SystemClock().now
        #expect(now >= before && now <= Date())
    }

    @Test("the URL opener records what it opened")
    func urlOpener() {
        let opener = RecordingURLOpener()
        let url = URL(string: "https://github.com/yahyabedirhan/shipyard/pull/7")!
        opener.open(url)
        #expect(opener.opened == [url])
    }

    @Test("the version is 0.0.1")
    func version() {
        #expect(ShipyardVersion.current == "0.0.1")
    }
}
