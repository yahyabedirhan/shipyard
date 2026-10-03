import Foundation
@testable import ShipyardCommand
@testable import ShipyardCore
@testable import ShipyardPings
import Testing

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

/// `shop`, and two remote machines.
private let twoMachines = "[remote]\nmachines = [\"hetzner-vps\", \"netcup-vps\"]\n\n" + shop

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

/// A ping as a machine's `shipyard` lists it, sent `minutes` before the
/// harness's now.
private func ping(_ id: String, _ title: String, minutes: Double = 5) -> Ping {
    Ping(id: id, title: title, projects: [], sent: Harness.now.addingTimeInterval(-minutes * 60), instance: "i-\(id)")
}

@MainActor
private extension Harness {
    /// A harness signed in with `config`, whose Herdr has saved
    /// `hetzner-vps` and `netcup-vps` listing `hetzner` and `netcup`,
    /// started and polled once.
    static func polled(_ config: String = twoMachines, hetzner: [Ping] = [], netcup: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        harness.herdr.addMachine("hetzner-vps", pings: hetzner)
        harness.herdr.addMachine("netcup-vps", pings: netcup)
        await harness.shipyard.start()
        await harness.machineTimer.fire()
        return harness
    }

    func titles(_ name: String) -> [String] {
        section(name)?.rows.map(\.title) ?? []
    }

    /// The panel's quiet lines about machines, as it shows them.
    var machineLines: [String] {
        shipyard.menu.machineNotices.map(PanelText.machineNotice)
    }

    /// Fires the machine timer, which must be armed, and waits for the poll.
    func poll(sourceLocation: SourceLocation = #_sourceLocation) async {
        let fired = await machineTimer.fire()
        #expect(fired, "the machine timer wasn't armed", sourceLocation: sourceLocation)
    }
}

/// Waits, a moment at a time, until `condition` holds; false after about two seconds.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<1000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}

/// Machines that don't answer: one down, unknown to Herdr, disabled, too
/// slow or too far apart in version keeps its last pings, and the panel
/// says why in one quiet line until its next good poll. End to end through
/// `Harness`, over a fake `herdr` with two saved machines.
@Suite("Machines that don't answer")
@MainActor
struct UnreachableMachinesTests {
    @Test("a label Herdr has no machine for is one quiet line, with the line Herdr prints read, and no last pings to keep")
    func unknownLabel() async throws {
        let harness = try await Harness.polled("[remote]\nmachines = [\"netcup-vps\", \"typo-vps\"]\n\n" + shop, netcup: [ping("q1", "Deploy?")])
        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        #expect(harness.shipyard.remote.machine("typo-vps")?.failure == "Herdr has no saved machine named typo-vps")
        #expect(harness.machineLines == ["Herdr has no saved machine named typo-vps."])
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop", "netcup-vps"])
    }

    @Test("a machine disabled in Herdr keeps its last pings, says so, and its next good poll clears the line")
    func disabledAndBack() async throws {
        let harness = try await Harness.polled(hetzner: [ping("a1", "Tests are red")], netcup: [ping("q1", "Deploy?")])
        harness.herdr.setReach(.disabled, on: "netcup-vps")
        harness.herdr.setPings([ping("q2", "Unseen while down")], on: "netcup-vps")
        await harness.poll()

        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        #expect(harness.titles("hetzner-vps") == ["Tests are red"])
        #expect(harness.machineLines == ["netcup-vps is disabled in Herdr. Its last pings stay listed."])
        #expect(harness.machineTimer.armed == Shipyard.machinePollInterval)
        // A GitHub refresh keeps the line.
        await harness.timer.fire()
        #expect(harness.machineLines == ["netcup-vps is disabled in Herdr. Its last pings stay listed."])

        harness.herdr.setReach(.up, on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Unseen while down"])
        #expect(harness.machineLines.isEmpty)
        #expect(harness.shipyard.remote.machine("netcup-vps")?.failure == nil)
    }

    @Test("a machine Herdr can't connect to keeps its last pings and is one quiet line")
    func unreachable() async throws {
        let harness = try await Harness.polled(netcup: [ping("q1", "Deploy?")])
        harness.herdr.setReach(.unreachable, on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        #expect(harness.machineLines == ["Couldn't reach netcup-vps through Herdr. Its last pings stay listed."])
    }

    @Test("without herdr, or with it stopped, every machine keeps its last pings and says why, one line each")
    func herdrMissing() async throws {
        let harness = try await Harness.polled(hetzner: [ping("a1", "Tests are red")], netcup: [ping("q1", "Deploy?")])
        harness.herdr.installed = false
        let runs = harness.herdr.runs.count
        await harness.poll()
        #expect(harness.herdr.runs.count == runs)
        #expect(harness.titles("hetzner-vps") == ["Tests are red"])
        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        #expect(harness.machineLines == [
            "Couldn't find herdr to reach hetzner-vps. Its last pings stay listed.",
            "Couldn't find herdr to reach netcup-vps. Its last pings stay listed.",
        ])

        harness.herdr.installed = true
        harness.herdr.running = false
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        #expect(harness.machineLines.last == "Herdr isn't running, so netcup-vps can't be reached. Its last pings stay listed.")
    }



    @Test("a truncated list shows what came and notes it, until a whole list comes")
    func truncated() async throws {
        let harness = try await Harness.polled()
        harness.herdr.setPings((0..<120).map { ping("p\($0)", "Ping \($0)", minutes: Double($0)) }, on: "netcup-vps")
        await harness.poll()
        #expect(harness.section("netcup-vps")?.rows.count == PingList.maxPings)
        #expect(harness.machineLines == ["netcup-vps has more pings than it could send. Showing its newest 100."])

        harness.herdr.setPings([ping("p0", "Ping 0")], on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Ping 0"])
        #expect(harness.machineLines.isEmpty)
    }


    @Test("one slow machine never delays another, or the menu, and times out on its own")
    func slowMachine() async throws {
        let harness = try await Harness.polled(hetzner: [ping("a1", "Tests are red")], netcup: [ping("q1", "Deploy?")])
        harness.herdr.setReach(.hanging, on: "netcup-vps")
        harness.herdr.setPings([ping("a2", "Fixed")], on: "hetzner-vps")
        let polling = Task { await harness.poll() }

        // hetzner lists while netcup still hangs, and GitHub refreshes meanwhile.
        #expect(await eventually { harness.titles("hetzner-vps") == ["Fixed"] })
        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        let requests = harness.graphQLRequests.count
        await harness.timer.fire()
        #expect(harness.graphQLRequests.count == requests + 1)
        #expect(harness.titles("netcup-vps") == ["Deploy?"])

        harness.herdr.timeOutReads()
        await polling.value
        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        #expect(harness.machineLines == ["netcup-vps didn't answer in time. Its last pings stay listed."])
        #expect(harness.machineTimer.armed == Shipyard.machinePollInterval)
    }

    @Test("⌘R polls every machine at once, beside the GitHub refresh")
    func refreshNowPolls() async throws {
        let harness = try await Harness.polled(hetzner: [ping("a1", "Tests are red")], netcup: [ping("q1", "Deploy?")])
        harness.herdr.setPings([ping("a2", "Fixed")], on: "hetzner-vps")
        harness.herdr.setPings([ping("q2", "Merge it?")], on: "netcup-vps")
        let requests = harness.graphQLRequests.count

        await harness.shipyard.refreshNow()

        #expect(harness.titles("hetzner-vps") == ["Fixed"])
        #expect(harness.titles("netcup-vps") == ["Merge it?"])
        #expect(harness.graphQLRequests.count > requests)
        // The machine timer comes back a full interval after.
        #expect(harness.machineTimer.armed == Shipyard.machinePollInterval)
    }

}

/// The lines Herdr prints when it refuses a machine before asking it
/// (`cli/target.rs`, `resolve_machine`, at Herdr commit 65e35a3), beyond
/// the unknown and disabled labels the scenarios above cover.
@Suite("Herdr's machine refusals")
struct HerdrRefusalTests {
    @Test("an ambiguous label is read; another machine's refusal, or a failed connection, isn't")
    func refusals() {
        #expect(HerdrCommand.refusal("error: machine label 'vps' is ambiguous; use its profile ID\n", machine: "vps")
            == "Herdr has more than one machine named vps")
        #expect(HerdrCommand.refusal("error: machine 'other' is disabled\n", machine: "netcup-vps") == nil)
        #expect(HerdrCommand.refusal("Error: Custom { kind: Other }", machine: "netcup-vps") == nil)
    }
}
