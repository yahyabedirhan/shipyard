import Foundation
@testable import ShipyardCore
import Testing

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private let twoMachines = "[remote]\nmachines = [\"hetzner-vps\", \"netcup-vps\"]\n\n" + shop

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

/// A ping as a machine's `shipyard` lists it, sent `minutes` before the
/// harness's now, as the sending `instance` (its own by default).
private func ping(_ id: String, _ title: String, minutes: Double = 5, repository: String? = nil, instance: String? = nil) -> Ping {
    Ping(id: id, title: title, projects: [], sent: Harness.now.addingTimeInterval(-minutes * 60), repository: repository, instance: instance ?? "i-\(id)")
}

@MainActor
private extension Harness {
    /// A harness signed in with `config`, whose Herdr has saved
    /// `hetzner-vps` and `netcup-vps` listing `hetzner` and `netcup`,
    /// started and polled once.
    static func polled(_ config: String = twoMachines, hetzner: [Ping] = [], netcup: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        try await harness.startPolled(hetzner: hetzner, netcup: netcup)
        return harness
    }

    func startPolled(hetzner: [Ping] = [], netcup: [Ping] = []) async throws {
        stub.on(Harness.userURL, Harness.viewerAnswer)
        graphQL([onePullRequest])
        herdr.addMachine("hetzner-vps", pings: hetzner)
        herdr.addMachine("netcup-vps", pings: netcup)
        await shipyard.start()
        await poll()
    }

    func titles(_ name: String) -> [String] {
        section(name)?.rows.map(\.title) ?? []
    }

    func row(_ machine: String, _ title: String) throws -> MenuRow {
        try #require(section(machine)?.rows.first { $0.title == title })
    }

    func needsAttention(_ machine: String) -> [Bool] {
        section(machine)?.rows.map(\.needsAttention) ?? []
    }

    func poll(sourceLocation: SourceLocation = #_sourceLocation) async {
        let fired = await machineTimer.fire()
        #expect(fired, "the machine timer wasn't armed", sourceLocation: sourceLocation)
    }

    /// The URLs of the remote pings with a mark in the app state.
    var marked: [String] { shipyard.appStateStore.state.remotePings.marks.keys.sorted() }
}

/// Seen, dismiss and expiry for remote pings: kept on the Mac in the app
/// state, by the ping's URL and instance, since nothing is written back to
/// a machine. End to end across `Shipyard`, a fake `herdr` with two saved
/// machines, the app state and the menu model.
@Suite("Remote pings seen and dismissed")
@MainActor
struct RemotePingMarksTests {
    // MARK: Seen

    @Test("⌥-click marks a remote ping seen: it stops needing attention, on that machine only, and stays seen across polls")
    func markSeen() async throws {
        let harness = try await Harness.polled(hetzner: [ping("q1", "From hetzner")], netcup: [ping("q1", "Deploy?", minutes: 1), ping("q2", "Merge it?", minutes: 9)])
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
            ping("q1", "Deploy?", minutes: 1, repository: "yahyabedirhan/shop"),
            ping("q2", "Merge it?", minutes: 2, repository: "yahyabedirhan/shop"),
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
        let harness = try await Harness.polled(hetzner: [ping("a1", "Tests are red")], netcup: [ping("q1", "Deploy?", minutes: 1), ping("q2", "Merge it?", minutes: 2)])
        harness.shipyard.markAllSeen(project: "netcup-vps")
        #expect(harness.needsAttention("netcup-vps") == [false, false])
        #expect(harness.needsAttention("hetzner-vps") == [true])

        harness.shipyard.markAllSeen()
        #expect(harness.needsAttention("hetzner-vps") == [false])
        #expect(harness.shipyard.menu.attention.pings == 0)
    }

    @Test("a replaced remote ping needs attention again; one sent anew under its id does too")
    func replaceIsUnseen() async throws {
        let harness = try await Harness.polled(netcup: [ping("q1", "Deploy?", minutes: 1), ping("q2", "Merge it?", minutes: 2)])
        harness.shipyard.markAllSeen()

        // q1 replaced (same instance, new title), q2 withdrawn and sent anew.
        harness.herdr.setPings([ping("q1", "Deploy now?", minutes: 1), ping("q2", "Merge it?", minutes: 2, instance: "again")], on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy now?", "Merge it?"])
        #expect(harness.needsAttention("netcup-vps") == [true, true])
    }

    // MARK: Expiry

    @Test("a seen remote ping leaves after the defaults' seen-window, from when it was seen")
    func seenWindow() async throws {
        let harness = try await Harness.polled("[defaults.pings]\nseen-window = \"30m\"\n\n" + twoMachines, netcup: [ping("q1", "Deploy?", minutes: 1), ping("q2", "Merge it?", minutes: 2)])
        harness.clock.advance(by: 3600)
        harness.shipyard.markSeen(try harness.row("netcup-vps", "Deploy?"))

        harness.clock.advance(by: 30 * 60 - 1)
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy?", "Merge it?"])
        #expect(harness.notifier.removed.isEmpty)

        // Leaving takes its notification with it, as a local ping's does.
        harness.clock.advance(by: 1)
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Merge it?"])
        #expect(harness.shipyard.menu.attention.pings == 1)
        #expect(harness.notifier.removed == ["ping.sent \(Ping.url(machine: "netcup-vps", id: "q1").absoluteString) i-q1"])
        await harness.poll()
        #expect(harness.notifier.posted.filter { $0.event == .pingSent }.count == 2)
    }

    // MARK: Dismiss

    @Test("✕ hides a remote ping until its machine stops listing that instance, replaced or not")
    func dismiss() async throws {
        let harness = try await Harness.polled(hetzner: [ping("q1", "From hetzner")], netcup: [ping("q1", "Deploy?", minutes: 1), ping("q2", "Merge it?", minutes: 2)])
        await harness.shipyard.dismiss(try harness.row("netcup-vps", "Deploy?")).value
        #expect(harness.titles("netcup-vps") == ["Merge it?"])
        #expect(harness.titles("hetzner-vps") == ["From hetzner"])
        #expect(harness.shipyard.menu.attention.pings == 2)

        // Replaced: still hidden.
        harness.herdr.setPings([ping("q1", "Deploy now?", minutes: 1), ping("q2", "Merge it?", minutes: 2)], on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Merge it?"])

        // Withdrawn, then sent anew under its id: shown.
        harness.herdr.setPings([ping("q2", "Merge it?", minutes: 2)], on: "netcup-vps")
        await harness.poll()
        harness.herdr.setPings([ping("q1", "Deploy?", minutes: 1, instance: "again"), ping("q2", "Merge it?", minutes: 2)], on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy?", "Merge it?"])
        #expect(harness.needsAttention("netcup-vps") == [true, true])
    }

    // MARK: Kept and pruned

    @Test("seen and dismissed are kept across a restart, even before the machines answer")
    func keptAcrossRestart() async throws {
        let pings = [ping("q1", "Deploy?", minutes: 1), ping("q2", "Merge it?", minutes: 2), ping("q3", "Ship it?", minutes: 3)]
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

    @Test("marks for pings no machine lists any more are pruned; a machine that fails keeps its own")
    func pruned() async throws {
        let harness = try await Harness.polled(hetzner: [ping("a1", "Tests are red")], netcup: [ping("q1", "Deploy?", minutes: 1), ping("q2", "Merge it?", minutes: 2)])
        harness.shipyard.markAllSeen()
        #expect(harness.marked == ["shipyard://ping/hetzner-vps/a1", "shipyard://ping/netcup-vps/q1", "shipyard://ping/netcup-vps/q2"])

        // netcup stops listing q2; hetzner fails, keeping a1 listed.
        harness.herdr.setPings([ping("q1", "Deploy?", minutes: 1)], on: "netcup-vps")
        harness.herdr.setListOutput("not json", on: "hetzner-vps")
        await harness.poll()
        #expect(harness.shipyard.remote.machine("hetzner-vps")?.failure != nil)
        #expect(harness.marked == ["shipyard://ping/hetzner-vps/a1", "shipyard://ping/netcup-vps/q1"])

        // q1 sent anew: the old instance's mark goes.
        harness.herdr.setPings([ping("q1", "Deploy?", minutes: 1, instance: "again")], on: "netcup-vps")
        await harness.poll()
        #expect(harness.marked == ["shipyard://ping/hetzner-vps/a1"])

        // hetzner taken out of the configuration: its marks go with it.
        try harness.writeConfig("[remote]\nmachines = [\"netcup-vps\"]\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.marked.isEmpty)
    }
}
