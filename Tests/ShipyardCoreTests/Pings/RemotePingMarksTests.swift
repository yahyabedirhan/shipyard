import Foundation
@testable import ShipyardCore
@testable import ShipyardPings
import Testing

private let shop = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private let twoMachines = "[remote]\nmachines = [\"hetzner-vps\", \"netcup-vps\"]\n\n" + shop

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

@MainActor
private extension Harness {
    static func polled(_ config: String = twoMachines, hetzner: [Ping] = [], netcup: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        await harness.startWithMachines(graphQL: onePullRequest, hetzner: hetzner, netcup: netcup, polled: true)
        return harness
    }

    func row(_ machine: String, _ title: String) throws -> MenuRow {
        try #require(section(machine)?.rows.first { $0.title == title })
    }

    func needsAttention(_ machine: String) -> [Bool] {
        section(machine)?.rows.map(\.needsAttention) ?? []
    }

    var marked: [String] { shipyard.appStateStore.state.remotePings.marks.keys.sorted() }
}

@Suite("Remote pings seen and dismissed")
@MainActor
struct RemotePingMarksTests {

    @Test("⌥-click marks a remote ping seen: it stops needing attention, on that machine only, and stays seen across polls")
    func markSeen() async throws {
        let harness = try await Harness.polled(hetzner: [remotePing("q1", "From hetzner")], netcup: [remotePing("q1", "Deploy?", minutes: 1), remotePing("q2", "Merge it?", minutes: 9)])
        #expect(harness.shipyard.menu.attention.pings == 3)

        harness.shipyard.markSeen(try harness.row("netcup-vps", "Deploy?"))
        #expect(harness.needsAttention("netcup-vps") == [false, true])
        #expect(harness.needsAttention("hetzner-vps") == [true])
        #expect(harness.shipyard.menu.attention.pings == 2)

        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy?", "Merge it?"])
        #expect(harness.needsAttention("netcup-vps") == [false, true])
        #expect(harness.shipyard.menu.attention.pings == 2)
    }

    @Test("a remote ping filed under a project is seen and dismissed from that project's section, and stays so across polls")
    func filedUnderProject() async throws {
        let harness = try await Harness.polled(netcup: [
            remotePing("q1", "Deploy?", minutes: 1, repository: "yahyabedirhan/shop"),
            remotePing("q2", "Merge it?", minutes: 2, repository: "yahyabedirhan/shop"),
        ])
        let pingRows = { harness.section("shop")?.rows.filter { $0.kind == .ping } ?? [] }
        #expect(pingRows().map(\.title) == ["Deploy?", "Merge it?"])

        harness.shipyard.markSeen(try #require(pingRows().first { $0.title == "Deploy?" }))
        await harness.shipyard.dismiss(try #require(pingRows().first { $0.title == "Merge it?" })).value
        await harness.poll()
        #expect(pingRows().map(\.title) == ["Deploy?"])
        #expect(pingRows().map(\.needsAttention) == [false])
        #expect(harness.shipyard.menu.attention.pings == 0)
    }

    @Test("Mark all seen marks remote pings too, every machine's, or only the section named")
    func markAllSeen() async throws {
        let harness = try await Harness.polled(hetzner: [remotePing("a1", "Tests are red")], netcup: [remotePing("q1", "Deploy?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2)])
        harness.shipyard.markAllSeen(project: "netcup-vps")
        #expect(harness.needsAttention("netcup-vps") == [false, false])
        #expect(harness.needsAttention("hetzner-vps") == [true])

        harness.shipyard.markAllSeen()
        #expect(harness.needsAttention("hetzner-vps") == [false])
        #expect(harness.shipyard.menu.attention.pings == 0)
    }

    @Test("a replaced remote ping needs attention again; one sent anew under its id does too")
    func replaceIsUnseen() async throws {
        let harness = try await Harness.polled(netcup: [remotePing("q1", "Deploy?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2)])
        harness.shipyard.markAllSeen()

        harness.herdr.setPings([remotePing("q1", "Deploy now?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2, instance: "again")], on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy now?", "Merge it?"])
        #expect(harness.needsAttention("netcup-vps") == [true, true])
    }

    @Test("a seen remote ping leaves after the defaults' seen-window, from when it was seen")
    func seenWindow() async throws {
        let harness = try await Harness.polled("[defaults.pings]\nseen-window = \"30m\"\n\n" + twoMachines, netcup: [remotePing("q1", "Deploy?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2)])
        harness.clock.advance(by: 3600)
        harness.shipyard.markSeen(try harness.row("netcup-vps", "Deploy?"))

        harness.clock.advance(by: 30 * 60 - 1)
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy?", "Merge it?"])
        #expect(harness.notifier.removed.isEmpty)

        harness.clock.advance(by: 1)
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Merge it?"])
        #expect(harness.shipyard.menu.attention.pings == 1)
        #expect(harness.notifier.removed == ["ping.sent \(Ping.url(machine: "netcup-vps", id: "q1").absoluteString) i-q1"])
        await harness.poll()
        #expect(harness.notifier.posted.filter { $0.event == .pingSent }.count == 2)
    }

    @Test("✕ hides a remote ping until its machine stops listing that instance, replaced or not")
    func dismiss() async throws {
        let harness = try await Harness.polled(hetzner: [remotePing("q1", "From hetzner")], netcup: [remotePing("q1", "Deploy?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2)])
        await harness.shipyard.dismiss(try harness.row("netcup-vps", "Deploy?")).value
        #expect(harness.titles("netcup-vps") == ["Merge it?"])
        #expect(harness.titles("hetzner-vps") == ["From hetzner"])
        #expect(harness.shipyard.menu.attention.pings == 2)

        harness.herdr.setPings([remotePing("q1", "Deploy now?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2)], on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Merge it?"])

        harness.herdr.setPings([remotePing("q2", "Merge it?", minutes: 2)], on: "netcup-vps")
        await harness.poll()
        harness.herdr.setPings([remotePing("q1", "Deploy?", minutes: 1, instance: "again"), remotePing("q2", "Merge it?", minutes: 2)], on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy?", "Merge it?"])
        #expect(harness.needsAttention("netcup-vps") == [true, true])
    }

    @Test("seen and dismissed are kept across a restart, even before the machines answer")
    func keptAcrossRestart() async throws {
        let pings = [remotePing("q1", "Deploy?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2), remotePing("q3", "Ship it?", minutes: 3)]
        let harness = try await Harness.polled(netcup: pings)
        harness.shipyard.markSeen(try harness.row("netcup-vps", "Deploy?"))
        await harness.shipyard.dismiss(try harness.row("netcup-vps", "Merge it?")).value

        let next = harness.relaunched()
        next.stub.on(Harness.userURL, Harness.viewerAnswer)
        next.graphQL([onePullRequest])
        next.herdr.addMachine("hetzner-vps")
        next.herdr.addMachine("netcup-vps", pings: pings)
        await next.shipyard.start()
        #expect(next.marked.count == 2)
        await next.poll()
        #expect(next.titles("netcup-vps") == ["Deploy?", "Ship it?"])
        #expect(next.needsAttention("netcup-vps") == [false, true])
    }

    @Test("marks for pings no machine lists any more are pruned; a machine that fails keeps its own, and one whose list stops early those past its end")
    func pruned() async throws {
        let harness = try await Harness.polled(hetzner: [remotePing("a1", "Tests are red")], netcup: [remotePing("q1", "Deploy?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2)])
        harness.shipyard.markAllSeen()
        #expect(harness.marked == ["shipyard://ping/hetzner-vps/a1", "shipyard://ping/netcup-vps/q1", "shipyard://ping/netcup-vps/q2"])

        let newer = (0..<PingList.maxPings).map { remotePing("n\($0)", "Newer \($0)", minutes: Double($0) / 1000) }
        harness.herdr.setPings(newer + [remotePing("q1", "Deploy?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2)], on: "netcup-vps")
        await harness.poll()
        #expect(harness.shipyard.remote.machine("netcup-vps")?.truncated == true)
        #expect(harness.marked.count == 3)
        harness.herdr.setPings([remotePing("q1", "Deploy?", minutes: 1), remotePing("q2", "Merge it?", minutes: 2)], on: "netcup-vps")
        await harness.poll()
        #expect(harness.needsAttention("netcup-vps") == [false, false])

        harness.herdr.setPings([remotePing("q1", "Deploy?", minutes: 1)], on: "netcup-vps")
        harness.herdr.setListOutput("not json", on: "hetzner-vps")
        await harness.poll()
        #expect(harness.shipyard.remote.machine("hetzner-vps")?.failure != nil)
        #expect(harness.marked == ["shipyard://ping/hetzner-vps/a1", "shipyard://ping/netcup-vps/q1"])

        harness.herdr.setPings([remotePing("q1", "Deploy?", minutes: 1, instance: "again")], on: "netcup-vps")
        await harness.poll()
        #expect(harness.marked == ["shipyard://ping/hetzner-vps/a1"])

        try harness.writeConfig("[remote]\nmachines = [\"netcup-vps\"]\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.marked.isEmpty)
    }
}
