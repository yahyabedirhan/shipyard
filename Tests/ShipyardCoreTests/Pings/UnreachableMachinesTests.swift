import Foundation
@testable import ShipyardCommand
@testable import ShipyardCore
@testable import ShipyardPings
import Testing

private let shop = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private let twoMachines = "[remote]\nmachines = [\"alpha-vps\", \"beta-vps\"]\n\n" + shop

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

@MainActor
private extension Harness {
    static func polled(_ config: String = twoMachines, alpha: [Ping] = [], beta: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        await harness.startWithMachines(graphQL: onePullRequest, alpha: alpha, beta: beta, polled: true)
        return harness
    }

    var machineLines: [String] {
        shipyard.menu.machineNotices.map(PanelText.machineNotice)
    }
}

@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<1000 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return condition()
}

@Suite("Machines that don't answer")
@MainActor
struct UnreachableMachinesTests {
    @Test("a label Herdr has no machine for is one quiet line, with the line Herdr prints read, and no last pings to keep")
    func unknownLabel() async throws {
        let harness = try await Harness.polled("[remote]\nmachines = [\"beta-vps\", \"typo-vps\"]\n\n" + shop, beta: [remotePing("q1", "Deploy?")])
        #expect(harness.titles("beta-vps") == ["Deploy?"])
        #expect(harness.shipyard.remote.machine("typo-vps")?.failure == "Herdr has no saved machine named typo-vps")
        #expect(harness.machineLines == ["Herdr has no saved machine named typo-vps."])
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop", "beta-vps"])
    }

    @Test("a machine disabled in Herdr keeps its last pings, says so, and its next good poll clears the line")
    func disabledAndBack() async throws {
        let harness = try await Harness.polled(alpha: [remotePing("a1", "Tests are red")], beta: [remotePing("q1", "Deploy?")])
        harness.herdr.setReach(.disabled, on: "beta-vps")
        harness.herdr.setPings([remotePing("q2", "Unseen while down")], on: "beta-vps")
        await harness.poll()

        #expect(harness.titles("beta-vps") == ["Deploy?"])
        #expect(harness.titles("alpha-vps") == ["Tests are red"])
        #expect(harness.machineLines == ["beta-vps is disabled in Herdr. Its last pings stay listed."])
        #expect(harness.machineTimer.armed == Shipyard.machinePollInterval)
        await harness.timer.fire()
        #expect(harness.machineLines == ["beta-vps is disabled in Herdr. Its last pings stay listed."])

        harness.herdr.setReach(.up, on: "beta-vps")
        await harness.poll()
        #expect(harness.titles("beta-vps") == ["Unseen while down"])
        #expect(harness.machineLines.isEmpty)
        #expect(harness.shipyard.remote.machine("beta-vps")?.failure == nil)
    }

    @Test("a machine Herdr can't connect to keeps its last pings and is one quiet line")
    func unreachable() async throws {
        let harness = try await Harness.polled(beta: [remotePing("q1", "Deploy?")])
        harness.herdr.setReach(.unreachable, on: "beta-vps")
        await harness.poll()
        #expect(harness.titles("beta-vps") == ["Deploy?"])
        #expect(harness.machineLines == ["Couldn't reach beta-vps through Herdr. Its last pings stay listed."])
    }

    @Test("without herdr, or with it stopped, every machine keeps its last pings and says why, one line each")
    func herdrMissing() async throws {
        let harness = try await Harness.polled(alpha: [remotePing("a1", "Tests are red")], beta: [remotePing("q1", "Deploy?")])
        harness.herdr.installed = false
        let runs = harness.herdr.runs.count
        await harness.poll()
        #expect(harness.herdr.runs.count == runs)
        #expect(harness.titles("alpha-vps") == ["Tests are red"])
        #expect(harness.titles("beta-vps") == ["Deploy?"])
        #expect(harness.machineLines == [
            "Couldn't find herdr to reach alpha-vps. Its last pings stay listed.",
            "Couldn't find herdr to reach beta-vps. Its last pings stay listed.",
        ])

        harness.herdr.installed = true
        harness.herdr.running = false
        await harness.poll()
        #expect(harness.titles("beta-vps") == ["Deploy?"])
        #expect(harness.machineLines.last == "Herdr isn't running, so beta-vps can't be reached. Its last pings stay listed.")
    }

    @Test("a truncated list shows what came and notes it, until a whole list comes")
    func truncated() async throws {
        let harness = try await Harness.polled()
        harness.herdr.setPings((0..<120).map { remotePing("p\($0)", "Ping \($0)", minutes: Double($0)) }, on: "beta-vps")
        await harness.poll()
        #expect(harness.section("beta-vps")?.rows.count == PingList.maxPings)
        #expect(harness.machineLines == ["beta-vps has more pings than it could send. Showing its newest 100."])

        harness.herdr.setPings([remotePing("p0", "Ping 0")], on: "beta-vps")
        await harness.poll()
        #expect(harness.titles("beta-vps") == ["Ping 0"])
        #expect(harness.machineLines.isEmpty)
    }

    @Test("one slow machine never delays another, or the menu, and times out on its own")
    func slowMachine() async throws {
        let harness = try await Harness.polled(alpha: [remotePing("a1", "Tests are red")], beta: [remotePing("q1", "Deploy?")])
        harness.herdr.setReach(.hanging, on: "beta-vps")
        harness.herdr.setPings([remotePing("a2", "Fixed")], on: "alpha-vps")
        let polling = Task { await harness.poll() }

        #expect(await eventually { harness.titles("alpha-vps") == ["Fixed"] })
        #expect(harness.titles("beta-vps") == ["Deploy?"])
        let requests = harness.graphQLRequests.count
        await harness.timer.fire()
        #expect(harness.graphQLRequests.count == requests + 1)
        #expect(harness.titles("beta-vps") == ["Deploy?"])

        harness.herdr.timeOutReads()
        await polling.value
        #expect(harness.titles("beta-vps") == ["Deploy?"])
        #expect(harness.machineLines == ["beta-vps didn't answer in time. Its last pings stay listed."])
        #expect(harness.machineTimer.armed == Shipyard.machinePollInterval)
    }

    @Test("⌘R polls every machine at once, beside the GitHub refresh")
    func refreshNowPolls() async throws {
        let harness = try await Harness.polled(alpha: [remotePing("a1", "Tests are red")], beta: [remotePing("q1", "Deploy?")])
        harness.herdr.setPings([remotePing("a2", "Fixed")], on: "alpha-vps")
        harness.herdr.setPings([remotePing("q2", "Merge it?")], on: "beta-vps")
        let requests = harness.graphQLRequests.count

        await harness.shipyard.refreshNow()

        #expect(harness.titles("alpha-vps") == ["Fixed"])
        #expect(harness.titles("beta-vps") == ["Merge it?"])
        #expect(harness.graphQLRequests.count > requests)
        #expect(harness.machineTimer.armed == Shipyard.machinePollInterval)
    }
}

@Suite("Herdr's machine refusals")
struct HerdrRefusalTests {
    @Test("an ambiguous label is read; another machine's refusal, or a failed connection, isn't")
    func refusals() {
        #expect(HerdrCommand.refusal("error: machine label 'vps' is ambiguous; use its profile ID\n", machine: "vps")
            == "Herdr has more than one machine named vps")
        #expect(HerdrCommand.refusal("error: machine 'other' is disabled\n", machine: "beta-vps") == nil)
        #expect(HerdrCommand.refusal("Error: Custom { kind: Other }", machine: "beta-vps") == nil)
    }
}
