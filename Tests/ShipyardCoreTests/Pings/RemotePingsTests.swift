import Foundation
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

private let plugin = ["--plugin", "yahyabedirhan.herdr-shipyard"]

@MainActor
private extension Harness {
    static func withMachines(_ config: String = twoMachines, alpha: [Ping] = [], beta: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        await harness.startWithMachines(graphQL: onePullRequest, alpha: alpha, beta: beta)
        return harness
    }
}

@Suite("Remote pings")
@MainActor
struct RemotePingsTests {

    @Test("each machine is asked through Herdr: the plugin's list action, then its log record among the newest few; then its notices")
    func asksThroughHerdr() async throws {
        let harness = try await Harness.withMachines(beta: [remotePing("q1", "Deploy?")])
        await harness.poll()
        let invoke: [String] = ["plugin", "action", "invoke", "list"] + plugin
        let logList: [String] = ["plugin", "log", "list"] + plugin + ["--limit", "10"]
        let notices: [String] = ["plugin", "action", "invoke", "notices"] + plugin
        for label in ["alpha-vps", "beta-vps"] {
            #expect(harness.herdr.runs(on: label) == [invoke, logList, notices, logList])
        }
        #expect(harness.herdr.runs.allSatisfy { $0.first == "--machine" })

        for _ in 0..<RemotePingReader.logLimit { await harness.poll() }
        harness.herdr.setPings([remotePing("q2", "Merge it?")], on: "beta-vps")
        await harness.poll()
        #expect(harness.titles("beta-vps") == ["Merge it?"])
    }

    @Test("a record still running is asked for again until it's done")
    func waitsWhileRunning() async throws {
        let harness = try Harness(stored: "gho_stored", config: twoMachines)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        harness.herdr.addMachine("alpha-vps")
        harness.herdr.addMachine("beta-vps", pings: [remotePing("q1", "Deploy?")], runningFor: 2)
        await harness.shipyard.start()
        await harness.poll()
        let pingRuns = harness.herdr.runs(on: "beta-vps").prefix { !$0.starts(with: ["plugin", "action", "invoke", "notices"]) }
        #expect(pingRuns.filter { $0.starts(with: ["plugin", "log", "list"]) }.count == 3)
        #expect(harness.titles("beta-vps") == ["Deploy?"])
    }

    @Test("each machine's pings list under a section named after it, after the projects, needing attention")
    func machineSections() async throws {
        let harness = try await Harness.withMachines(
            alpha: [remotePing("a1", "Tests are red", sender: "codex")],
            beta: [remotePing("q1", "Deploy?", minutes: 1, sender: "claude"), remotePing("q2", "Merge it?", minutes: 9)]
        )
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop"])
        #expect(harness.machineTimer.armed == 0)
        await harness.poll()

        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop", "alpha-vps", "beta-vps"])
        #expect(harness.shipyard.menu.sections.map(\.machine) == [nil, "alpha-vps", "beta-vps"])
        #expect(harness.titles("beta-vps") == ["Deploy?", "Merge it?"])
        #expect(harness.titles("alpha-vps") == ["Tests are red"])
        let rows = harness.shipyard.menu.sections.dropFirst().flatMap(\.rows)
        #expect(rows.allSatisfy { $0.needsAttention })
        #expect(harness.shipyard.menu.attention.pings == 3)
        #expect(harness.section("shop")?.rows.map(\.kind) == [.pullRequest])
    }

    @Test("a remote ping's row names its machine, after its number, and its done button says it only hides the ping")
    func rowNamesMachine() async throws {
        let harness = try await Harness.withMachines(beta: [remotePing("q1", "Deploy?", sender: "claude"), remotePing("q2", "Merge it?", minutes: 9)])
        await harness.poll()
        let rows = try #require(harness.section("beta-vps")?.rows)
        #expect(rows.map(\.machine) == ["beta-vps", "beta-vps"])
        #expect(rows.map { PanelText.rowDetail($0, showingRepository: false) } == ["#2 · beta-vps · claude", "#1 · beta-vps"])
        #expect(rows.map(PanelText.pingMeta) == ["beta-vps · claude", "beta-vps"])
        #expect(PanelText.pingDoneHelp(rows[0]) == "Done: hide this ping until beta-vps stops listing it (⌫)")
    }

    @Test("a remote ping is known as shipyard://ping/<machine>/<id>, so the same id on two machines, and here, stays apart")
    func identity() async throws {
        let harness = try await Harness.withMachines(alpha: [remotePing("q1", "From alpha")], beta: [remotePing("q1", "From beta")])
        harness.cli("ping", "send", "From the Mac", "--project", "shop", "--id", "q1")
        await harness.shipyard.reloadPings()
        await harness.poll()
        #expect(harness.section("alpha-vps")?.rows.map(\.id) == ["shipyard://ping/alpha-vps/q1"])
        #expect(harness.section("beta-vps")?.rows.map(\.id) == ["shipyard://ping/beta-vps/q1"])
        #expect(harness.section("shop")?.rows.filter { $0.kind == .ping }.map(\.id) == ["shipyard://ping/q1"])
        #expect(harness.titles("alpha-vps") == ["From alpha"])
        #expect(harness.titles("beta-vps") == ["From beta"])
    }

    @Test("machines are polled every 30 seconds on their own timer, with no GitHub request")
    func ownTimer() async throws {
        let harness = try await Harness.withMachines(beta: [remotePing("q1", "Deploy?")])
        let requests = harness.graphQLRequests.count
        let refreshArmed = harness.timer.armed
        await harness.poll()
        #expect(harness.machineTimer.armed == Shipyard.machinePollInterval)
        #expect(Shipyard.machinePollInterval == 30)

        harness.herdr.setPings([remotePing("q2", "Now this", minutes: 1)], on: "beta-vps")
        await harness.poll()
        #expect(harness.titles("beta-vps") == ["Now this"])
        #expect(harness.graphQLRequests.count == requests)
        #expect(harness.timer.armed == refreshArmed)
        #expect(harness.machineTimer.armed == 30)
    }

    @Test("a GitHub refresh keeps the remote pings, and doesn't ask the machines")
    func refreshKeepsThem() async throws {
        let harness = try await Harness.withMachines(beta: [remotePing("q1", "Deploy?")])
        await harness.poll()
        let runs = harness.herdr.runs.count
        await harness.timer.fire()
        #expect(harness.titles("beta-vps") == ["Deploy?"])
        #expect(harness.herdr.runs.count == runs)
    }

    @Test("a refresh before a machine's first poll keeps the folds of its section")
    func keepsMachineFolds() async throws {
        let harness = try await Harness.withMachines(beta: [remotePing("q1", "Deploy?")])
        let fold = GroupID(project: "beta-vps", key: .kind(.ping))
        let gone = GroupID(project: "removed-vps", key: .kind(.ping))
        harness.shipyard.appStateStore.update { $0.collapsedGroups = [fold, gone] }
        await harness.timer.fire()
        #expect(harness.shipyard.appStateStore.state.collapsedGroups == [fold])
    }

    @Test("without machines nothing is polled")
    func noMachines() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        #expect(harness.machineTimer.armed == nil)
        #expect(harness.herdr.runs.isEmpty)
        await harness.shipyard.pollMachines()
        #expect(harness.herdr.runs.isEmpty)
    }

    @Test("the pings show signed out too, as local ones do")
    func signedOut() async throws {
        let harness = try Harness(config: twoMachines)
        harness.herdr.addMachine("alpha-vps")
        harness.herdr.addMachine("beta-vps", pings: [remotePing("q1", "Deploy?")])
        await harness.shipyard.start()
        await harness.poll()
        #expect(harness.titles("beta-vps") == ["Deploy?"])
    }

    @Test("a machine that fails keeps its last pings and says why; the other lists as usual")
    func failureKeepsPings() async throws {
        let harness = try await Harness.withMachines(alpha: [remotePing("a1", "Tests are red")], beta: [remotePing("q1", "Deploy?")])
        await harness.poll()
        harness.herdr.setListOutput(#"{"version":2,"shipyardVersion":"9.0.0","pings":[],"truncated":false}"#, on: "beta-vps")
        harness.herdr.setPings([remotePing("a2", "Fixed")], on: "alpha-vps")
        await harness.poll()

        #expect(harness.titles("beta-vps") == ["Deploy?"])
        #expect(harness.titles("alpha-vps") == ["Fixed"])
        #expect(harness.shipyard.remote.machine("beta-vps")?.failure
            == "beta-vps lists pings in version 2 from shipyard 9.0.0, and this shipyard reads version 1: update shipyard on beta-vps")
        #expect(harness.shipyard.remote.machine("alpha-vps")?.failure == nil)
        #expect(harness.shipyard.menu.machineNotices.map(PanelText.machineNotice) == [
            "beta-vps lists pings in version 2 from shipyard 9.0.0, and this shipyard reads version 1: update shipyard on beta-vps. Its last pings stay listed.",
        ])
        #expect(harness.machineTimer.armed == 30)

        harness.herdr.setPings([], on: "beta-vps")
        await harness.poll()
        #expect(harness.section("beta-vps") == nil)
        #expect(harness.shipyard.remote.machine("beta-vps")?.failure == nil)
        #expect(harness.shipyard.menu.machineNotices.isEmpty)
    }

    @Test("an edit adding or removing a machine applies at once; none left stops polling")
    func followsConfiguration() async throws {
        let harness = try await Harness.withMachines("[remote]\nmachines = [\"beta-vps\"]\n\n" + shop, alpha: [remotePing("a1", "Tests are red")], beta: [remotePing("q1", "Deploy?")])
        await harness.poll()
        #expect(harness.herdr.runs(on: "alpha-vps").isEmpty)

        try harness.writeConfig(twoMachines)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.machineTimer.armed == 0)
        await harness.poll()
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop", "alpha-vps", "beta-vps"])

        try harness.writeConfig("[remote]\nmachines = [\"alpha-vps\"]\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop", "alpha-vps"])

        try harness.writeConfig(shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop"])
        #expect(harness.machineTimer.armed == nil)
    }

    @Test("clicking, marking or dismissing a remote ping never touches a local ping with its id")
    func leavesLocalPings() async throws {
        let harness = try await Harness.withMachines(beta: [remotePing("q1", "Remote")])
        harness.cli("ping", "send", "Local", "--project", "shop", "--id", "q1", "--open", "https://example.com")
        await harness.shipyard.reloadPings()
        await harness.poll()
        let row = try #require(harness.section("beta-vps")?.rows.first)

        await harness.shipyard.open(row).value
        harness.shipyard.markSeen(row)
        harness.shipyard.markAllSeen()
        await harness.shipyard.dismiss(row).value
        await harness.shipyard.openNotification(row.url).value

        #expect(harness.actions.opened.isEmpty)
        #expect(harness.actions.ran.isEmpty)
        let local = try #require(harness.pingStore.ping(id: "q1"))
        #expect(local.title == "Local")
        #expect(harness.section("shop")?.rows.filter { $0.kind == .ping }.map(\.title) == ["Local"])
    }
}

@Suite("Remote ping reader")
struct RemotePingReaderTests {
    @Test("a machine that doesn't answer in time fails, and its herdr is stopped")
    func timesOut() async {
        let hanging = HangingShell()
        let reader = RemotePingReader(
            home: URL(fileURLWithPath: "/nonexistent-home"),
            pathEnvironment: nil,
            isExecutable: { $0 == FakeHerdr.path },
            runner: hanging,
            timeout: 0.05
        )
        #expect(await reader.list(machine: "beta-vps") == .failure(.init("beta-vps didn't answer in time")))
        #expect(hanging.cancelled == hanging.started)
    }

    @Test("pings read from a machine carry its label")
    func marksMachine() async throws {
        let herdr = FakeHerdr()
        herdr.addMachine("My VPS", pings: [remotePing("q1", "Deploy?")])
        let list = try await herdr.remote.list(machine: "My VPS").get()
        #expect(list.pings.map(\.machine) == ["My VPS"])
        #expect(list.pings.map(\.item.url) == [URL(string: "shipyard://ping/My%20VPS/q1")!])
        let remote = try #require(Ping.remote(from: list.pings[0].item.url))
        #expect(remote.machine == "My VPS")
        #expect(remote.id == "q1")
        #expect(Ping.id(from: list.pings[0].item.url) == nil)
    }
}
