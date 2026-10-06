import Foundation
@testable import ShipyardCore
@testable import ShipyardPings
import Testing

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

@MainActor
private extension Harness {
    /// The banners the panel shows at the clock's time, in order.
    var banners: [PanelBanner] { shipyard.banners(at: clock.now) }

    /// The keys of the banners the panel shows now, in order.
    var bannerKeys: [String] { banners.map(\.id) }

    /// The words of the banner `key` the panel shows now; `nil` while it's hidden.
    func bannerText(_ key: String) -> String? {
        banners.first { $0.id == key }?.text
    }

    /// Refreshes now, with GitHub answering `answer`.
    func refreshNow(answering answer: StubHTTP.Answer) async {
        graphQL([answer])
        await shipyard.refresh()
    }
}

/// Dismissing a panel banner snoozes it for an hour: it stays hidden while
/// its condition holds, shows again once the hour ends, and a condition
/// that stops and starts again shows its banner at once. End to end through
/// `Harness`, at the manual clock, reading what the panel shows
/// (`Shipyard.banners(at:)`).
@Suite("Banner snoozes")
@MainActor
struct BannerSnoozeTests {
    @Test("a dismissed banner stays hidden for 59 minutes and shows at 60 while its condition holds, without a refresh")
    func hiddenForAnHour() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        await harness.refreshNow(answering: .failure())
        #expect(harness.bannerKeys.contains("fetch"))

        harness.shipyard.dismissBanner("fetch")
        #expect(!harness.bannerKeys.contains("fetch"))

        // Still failing at 59 minutes: still hidden.
        harness.clock.advance(by: 59 * 60)
        await harness.refreshNow(answering: .failure())
        #expect(!harness.bannerKeys.contains("fetch"))
        #expect(harness.shipyard.bannerSnoozeEnds == [Harness.now.addingTimeInterval(3600)])

        // At 60 minutes it's back, with no refresh in between.
        harness.clock.advance(by: 60)
        #expect(harness.bannerKeys.contains("fetch"))
        #expect(harness.shipyard.bannerSnoozeEnds.isEmpty)
    }

    @Test("a condition that stops clears its snooze, so it shows at once when it starts again")
    func stoppedAndRestarted() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        await harness.refreshNow(answering: .failure())
        harness.shipyard.dismissBanner("fetch")
        #expect(!harness.bannerKeys.contains("fetch"))

        harness.clock.advance(by: 120)
        await harness.refreshNow(answering: onePullRequest)
        #expect(!harness.bannerKeys.contains("fetch"))

        harness.clock.advance(by: 120)
        await harness.refreshNow(answering: .failure())
        #expect(harness.bannerKeys.contains("fetch"))
    }

    @Test("one machine's snooze hides only its own line, whatever its words become")
    func oneMachine() async throws {
        let harness = try Harness(stored: "gho_stored", config: "[remote]\nmachines = [\"hetzner-vps\", \"netcup-vps\"]\n\n" + shop)
        await harness.startWithMachines(graphQL: onePullRequest)
        harness.herdr.setReach(.unreachable, on: "hetzner-vps")
        harness.herdr.setReach(.unreachable, on: "netcup-vps")
        await harness.poll()
        #expect(harness.bannerKeys == ["machine-hetzner-vps", "machine-netcup-vps"])

        harness.shipyard.dismissBanner("machine-netcup-vps")
        #expect(harness.bannerKeys == ["machine-hetzner-vps"])

        // netcup's line now says something else; it's the same condition.
        harness.herdr.setReach(.disabled, on: "netcup-vps")
        await harness.poll()
        #expect(harness.bannerKeys == ["machine-hetzner-vps"])

        // netcup answers, then goes down again: its line is back at once.
        harness.herdr.setReach(.up, on: "netcup-vps")
        await harness.poll()
        harness.herdr.setReach(.unreachable, on: "netcup-vps")
        await harness.poll()
        #expect(harness.bannerKeys == ["machine-hetzner-vps", "machine-netcup-vps"])
    }

    @Test("a refresh delay whose words change stays hidden, since the snooze is the delay's, not its words'")
    func delayWordsChange() async throws {
        // 3 points a refresh at 1% of 5,000 an hour: one every 216 s.
        let pullRequests = try Harness.fixture("graphql-pull-requests.json")
        let projects = """
            [[projects]]
            name = "e-commerce"
            repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]

            """
        let harness = try await Harness.started(config: "[rate-limit]\nmax-share-percent = 1\n\n" + projects, graphQL: pullRequests)
        let before = try #require(harness.bannerText("delay"))
        harness.shipyard.dismissBanner("delay")
        #expect(harness.bannerText("delay") == nil)

        // 900 of 5,000 left: backed off to every 10 minutes, other words, still the delay.
        harness.clock.advance(by: 216)
        await harness.refreshNow(answering: try Harness.fixture("graphql-pull-requests.json", remaining: 900))
        #expect(harness.shipyard.menu.refreshDelay == .backedOff(600, api: .graphql))
        #expect(harness.bannerText("delay") == nil)

        harness.clock.advance(by: 3600 - 216)
        let after = try #require(harness.bannerText("delay"))
        #expect(after != before)
    }

    @Test("the notifications-off banner, which the app's notifier reports, snoozes and follows its condition too")
    func notificationsOff() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.shipyard.notificationsAreOff = true
        #expect(harness.bannerKeys == ["notifications"])

        harness.shipyard.dismissBanner("notifications")
        #expect(harness.bannerKeys.isEmpty)

        harness.shipyard.notificationsAreOff = false
        harness.shipyard.notificationsAreOff = true
        #expect(harness.bannerKeys == ["notifications"])
    }

    @Test("a restart keeps the snoozes through the first refresh, the first machine poll and the notifier's first word, and the banners show again when the hour ends")
    func keptAcrossRestart() async throws {
        let config = "[remote]\nmachines = [\"netcup-vps\"]\n\n" + shop
        let harness = try Harness(stored: "gho_stored", config: config)
        await harness.startWithMachines(graphQL: .failure())
        harness.herdr.setReach(.unreachable, on: "netcup-vps")
        await harness.poll()
        harness.shipyard.notificationsAreOff = true
        #expect(harness.bannerKeys == ["fetch", "machine-netcup-vps", "notifications"])
        for key in harness.bannerKeys { harness.shipyard.dismissBanner(key) }
        #expect(harness.bannerKeys.isEmpty)

        // Half an hour later the app quits and starts again over the same
        // support folder. Until the first refresh, the first poll and the
        // notifier's first word, none of the conditions is known: their
        // snoozes must survive the sign-in and the menu changes before them.
        harness.clock.advance(by: 30 * 60)
        let relaunched = harness.relaunched()
        relaunched.herdr.addMachine("netcup-vps")
        relaunched.herdr.setReach(.unreachable, on: "netcup-vps")
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([.failure()])
        await relaunched.shipyard.start()
        await relaunched.poll()
        relaunched.shipyard.notificationsAreOff = true
        #expect(relaunched.bannerKeys.isEmpty)
        let end = Harness.now.addingTimeInterval(3600)
        #expect(relaunched.shipyard.bannerSnoozeEnds == [end, end, end])

        // At the hour's end all three are back, without a refresh.
        relaunched.clock.advance(by: 30 * 60)
        #expect(relaunched.bannerKeys == ["fetch", "machine-netcup-vps", "notifications"])
        await relaunched.refreshNow(answering: .failure())
        #expect(relaunched.shipyard.appStateStore.state.bannerSnoozes == BannerSnoozes())
    }

    @Test("a snooze whose condition stopped before a restart is gone after it")
    func stoppedBeforeRestart() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        await harness.refreshNow(answering: .failure())
        harness.shipyard.dismissBanner("fetch")
        await harness.refreshNow(answering: onePullRequest)
        #expect(harness.shipyard.appStateStore.state.bannerSnoozes == BannerSnoozes())

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([.failure()])
        await relaunched.shipyard.start()
        #expect(relaunched.bannerKeys == ["fetch"])
    }

    @Test("the configuration error's banner snoozes too, and is back after the hour while the file is still rejected")
    func configErrorSnoozes() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try harness.writeConfig("version = \n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.bannerKeys.first == "config")

        harness.shipyard.dismissBanner("config")
        #expect(!harness.bannerKeys.contains("config"))

        // Read again at 59 minutes, still rejected: still hidden.
        harness.clock.advance(by: 59 * 60)
        await harness.shipyard.reloadConfiguration()
        #expect(!harness.bannerKeys.contains("config"))

        harness.clock.advance(by: 60)
        #expect(harness.bannerKeys.first == "config")
    }

    @Test("the lease's banner snoozes through its renewals; a lease that ends, or is handed to the next holder, clears it, so the next lease shows")
    func lease() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let first = PanelBanner.Lease.Held(term: "agent@0.0", headline: "Checking the header icons")
        harness.shipyard.lease = PanelBanner.Lease(held: first)
        #expect(harness.bannerKeys == ["lease"])
        #expect(harness.bannerText("lease") == "Checking the header icons")

        // Hidden while the same lease is renewed. The menu bar icon's dot is
        // the app's, read from its lease indicator: no snooze reaches it.
        harness.shipyard.dismissBanner("lease")
        #expect(harness.bannerKeys.isEmpty)
        harness.clock.advance(by: 60)
        harness.shipyard.lease = PanelBanner.Lease(held: first)
        #expect(harness.bannerKeys.isEmpty)

        // It ends; the same agent's next lease shows its banner at once.
        harness.shipyard.lease = PanelBanner.Lease()
        harness.shipyard.lease = PanelBanner.Lease(held: .init(term: "agent@120.0", headline: "Agent uses shipyard"))
        #expect(harness.bannerKeys == ["lease"])

        // Handed straight to a waiting agent: its lease shows too.
        harness.shipyard.dismissBanner("lease")
        harness.shipyard.lease = PanelBanner.Lease(held: .init(term: "other@180.0", headline: "Codex uses shipyard"))
        #expect(harness.bannerKeys == ["lease"])
        #expect(harness.bannerText("lease") == "Codex uses shipyard")
    }

    @Test("each stopped agent's quiet line snoozes on its own, under the lease's banner, and shows at once when that agent is stopped again")
    func stoppedHolders() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let claude = PanelBanner.Lease.Stopped(key: "claude", text: "You took shipyard back from Claude Code")
        let codex = PanelBanner.Lease.Stopped(key: "codex", text: "You took shipyard back from codex")
        let held = PanelBanner.Lease.Held(term: "other@0.0", headline: "Pi uses shipyard")
        harness.shipyard.lease = PanelBanner.Lease(held: held, stopped: [claude, codex])
        #expect(harness.bannerKeys == ["lease", "stopped-claude", "stopped-codex"])

        harness.shipyard.dismissBanner("stopped-claude")
        #expect(harness.bannerKeys == ["lease", "stopped-codex"])

        // Allowed back, then stopped again: its line is back at once.
        harness.shipyard.lease = PanelBanner.Lease(held: held, stopped: [codex])
        harness.shipyard.lease = PanelBanner.Lease(held: held, stopped: [claude, codex])
        #expect(harness.bannerKeys == ["lease", "stopped-claude", "stopped-codex"])
    }

    @Test("a restart drops the lease's snoozes: a lease handed over shows its banner, and no stopped holder survives")
    func leaseAcrossRestart() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let held = PanelBanner.Lease.Held(term: "agent@0.0", headline: "Checking the header icons")
        let stopped = PanelBanner.Lease.Stopped(key: "codex", text: "You took shipyard back from codex")
        harness.shipyard.lease = PanelBanner.Lease(held: held, stopped: [stopped])
        harness.shipyard.dismissBanner("lease")
        harness.shipyard.dismissBanner("stopped-codex")
        #expect(harness.bannerKeys.isEmpty)

        // The relaunch is handed the same lease; the bar didn't survive.
        harness.clock.advance(by: 60)
        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        await relaunched.shipyard.start()
        relaunched.shipyard.lease = PanelBanner.Lease(held: held)
        #expect(relaunched.bannerKeys == ["lease"])
        #expect(relaunched.shipyard.appStateStore.state.bannerSnoozes == BannerSnoozes())
    }
}
