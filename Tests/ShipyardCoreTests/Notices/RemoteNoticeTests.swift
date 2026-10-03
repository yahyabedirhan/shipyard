import Foundation
@testable import ShipyardCore
import ShipyardNotices
@testable import ShipyardPings
import Testing

/// `shop`, which watches `yahyabedirhan/shop`, `quiet`, whose own rules
/// leave `agent.notice` out, and two remote machines.
private let twoMachines = """
    [remote]
    machines = ["hetzner-vps", "netcup-vps"]

    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    [[projects]]
    name = "quiet"
    repositories = ["yahyabedirhan/quiet"]
    notifications = [{ event = "pr.opened" }]

    """

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

private let plugin = ["--plugin", "yahyabedirhan.herdr-shipyard"]

/// A notice an agent on another machine queued `minutes` before the
/// harness's now, filed under `project`.
private func queued(_ title: String, minutes: Double = 1, project: String = "shop", id: String? = nil) -> QueuedNotice {
    QueuedNotice(
        id: id ?? "n-\(title)",
        sent: Harness.now.addingTimeInterval(-minutes * 60),
        notice: Notice(title: title, sender: "claude", project: project)
    )
}

@MainActor
private extension Harness {
    /// A harness signed in, whose Herdr has saved `hetzner-vps` and
    /// `netcup-vps` with `netcup` pings, started and not yet polled.
    static func withMachines(netcup: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: twoMachines)
        await harness.startWithMachines(graphQL: onePullRequest, netcup: netcup)
        return harness
    }

    /// The titles of the notices posted, in order.
    var noticeTitles: [String] { notifier.posted.filter { $0.event == .agentNotice }.map(\.title) }
}

/// Notices agents on another machine left with its herdr-shipyard plugin
/// (the poll route): collected on the remote-ping poll through `FakeHerdr`,
/// shown by the same rules as any notice unless they waited more than ten
/// minutes, and removed from the machine once read. Prior art:
/// `RemotePingNotificationTests`, `NoticeTests`.
@Suite("A notice on the poll route")
@MainActor
struct RemoteNoticeTests {
    @Test("the poll shows the notices waiting on a machine, oldest first, then removes them there, so the next poll shows nothing again")
    func shownThenRemoved() async throws {
        let harness = try await Harness.withMachines()
        harness.herdr.queue(queued("Tests running", minutes: 3), on: "netcup-vps")
        harness.herdr.queue(queued("Done"), on: "netcup-vps")

        await harness.poll()

        #expect(harness.noticeTitles == ["shop · Tests running", "shop · Done"])
        #expect(harness.notifier.posted.last?.body == "from claude")
        #expect(harness.herdr.queued(on: "netcup-vps").isEmpty)
        let runs = harness.herdr.runs(on: "netcup-vps").filter { $0.starts(with: ["plugin", "action"]) }
        #expect(runs == [
            ["plugin", "action", "invoke", "list"] + plugin,
            ["plugin", "action", "invoke", "notices"] + plugin,
            ["plugin", "action", "invoke", "notices-read"] + plugin,
        ])
        // Never listed or counted.
        #expect(harness.titles("netcup-vps").isEmpty)
        #expect(harness.shipyard.menu.attention.pings == 0)

        await harness.poll()
        #expect(harness.noticeTitles.count == 2)
    }

    @Test("a notice more than ten minutes old when it arrives is dropped, and removed all the same", arguments: [
        (minutes: 9.0, shown: true),
        (minutes: 10.0, shown: true),
        (minutes: 10.5, shown: false),
        (minutes: 60.0, shown: false),
    ])
    func dropsStale(minutes: Double, shown: Bool) async throws {
        let harness = try await Harness.withMachines()
        harness.herdr.queue(queued("Deployed", minutes: minutes), on: "netcup-vps")

        await harness.poll()

        #expect(harness.noticeTitles == (shown ? ["shop · Deployed"] : []))
        #expect(harness.herdr.queued(on: "netcup-vps").isEmpty)
    }

    @Test("the rules apply as to any notice: a project whose rules leave agent.notice out, or no project, shows nothing")
    func rulesApply() async throws {
        let harness = try await Harness.withMachines()
        harness.herdr.queue(queued("Quiet run", project: "quiet"), on: "hetzner-vps")
        harness.herdr.queue(queued("Nowhere", project: "gone"), on: "hetzner-vps")
        harness.herdr.queue(queued("Shown"), on: "hetzner-vps")

        await harness.poll()

        #expect(harness.noticeTitles == ["shop · Shown"])
        #expect(harness.herdr.queued(on: "hetzner-vps").isEmpty)
    }

    @Test("a notice that doesn't read is dropped; the others show")
    func unreadable() async throws {
        let harness = try await Harness.withMachines()
        harness.herdr.queue(#"{"id":"x","sent":"yesterday"}"#, on: "netcup-vps")
        harness.herdr.queue(queued("Done"), on: "netcup-vps")

        await harness.poll()

        #expect(harness.noticeTitles == ["shop · Done"])
        #expect(harness.herdr.queued(on: "netcup-vps").isEmpty)
    }

    @Test("pings are unaffected: they list and notify beside the notices, and a plugin from before notices leaves them as they were")
    func pingsUnaffected() async throws {
        let harness = try await Harness.withMachines(netcup: [remotePing("q1", "Deploy?")])
        harness.herdr.withoutNotices(on: "netcup-vps")
        harness.herdr.queue(queued("Done"), on: "hetzner-vps")

        await harness.poll()

        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        #expect(harness.pingNotifications.map(\.title) == ["netcup-vps · Deploy?"])
        #expect(harness.noticeTitles == ["shop · Done"])
        // No machine line: a plugin without notices isn't a failure.
        #expect(harness.shipyard.menu.machineNotices.isEmpty)
        #expect(harness.machineTimer.armed == 30)
    }

    @Test("a machine whose pings couldn't be read isn't asked for its notices; they wait for a poll that reaches it")
    func unreachableKeepsThem() async throws {
        let harness = try await Harness.withMachines()
        harness.herdr.queue(queued("Done"), on: "netcup-vps")
        harness.herdr.setReach(.unreachable, on: "netcup-vps")

        await harness.poll()

        #expect(harness.noticeTitles.isEmpty)
        #expect(harness.herdr.queued(on: "netcup-vps").count == 1)
        #expect(!harness.herdr.runs(on: "netcup-vps").contains(["plugin", "action", "invoke", "notices"] + plugin))

        harness.herdr.setReach(.up, on: "netcup-vps")
        await harness.poll()
        #expect(harness.noticeTitles == ["shop · Done"])
    }
}
