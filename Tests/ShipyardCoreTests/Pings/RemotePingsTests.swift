import Foundation
@testable import ShipyardCore
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
private func ping(_ id: String, _ title: String, minutes: Double = 5, projects: [String] = [], sender: String? = nil) -> Ping {
    Ping(id: id, title: title, projects: projects, sent: Harness.now.addingTimeInterval(-minutes * 60), sender: sender, instance: "i-\(id)")
}

private let plugin = ["--plugin", "yahyabedirhan.herdr-shipyard"]

@MainActor
private extension Harness {
    /// A harness signed in with `config`, whose Herdr has saved
    /// `hetzner-vps` and `netcup-vps` listing `hetzner` and `netcup`, started.
    static func withMachines(_ config: String = twoMachines, hetzner: [Ping] = [], netcup: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        harness.herdr.addMachine("hetzner-vps", pings: hetzner)
        harness.herdr.addMachine("netcup-vps", pings: netcup)
        await harness.shipyard.start()
        return harness
    }

    /// The titles of the rows in the section `name`.
    func titles(_ name: String) -> [String] {
        section(name)?.rows.map(\.title) ?? []
    }

    /// Fires the machine timer, which must be armed, and waits for the poll.
    func poll(sourceLocation: SourceLocation = #_sourceLocation) async {
        let fired = await machineTimer.fire()
        #expect(fired, "the machine timer wasn't armed", sourceLocation: sourceLocation)
    }
}

/// The remote machines in `[remote] machines`: their pings asked for
/// through `herdr --machine`, on a timer of their own, and listed in the
/// menu. End to end across the configuration, `Shipyard`,
/// `RemotePingReader` over a fake `herdr` with two saved machines, and the
/// menu model.
@Suite("Remote pings")
@MainActor
struct RemotePingsTests {
    // MARK: Asking a machine

    @Test("each machine is asked through Herdr: the plugin's list action, then its log record")
    func asksThroughHerdr() async throws {
        let harness = try await Harness.withMachines(netcup: [ping("q1", "Deploy?")])
        await harness.poll()
        for label in ["hetzner-vps", "netcup-vps"] {
            #expect(harness.herdr.runs(on: label) == [
                ["plugin", "action", "invoke", "list"] + plugin,
                ["plugin", "log", "list"] + plugin,
            ])
        }
        // Nothing but `--machine` runs: no ssh, no shell.
        #expect(harness.herdr.runs.allSatisfy { $0.first == "--machine" })
    }

    @Test("a record still running is asked for again until it's done")
    func waitsWhileRunning() async throws {
        let harness = try Harness(stored: "gho_stored", config: twoMachines)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        harness.herdr.addMachine("hetzner-vps")
        harness.herdr.addMachine("netcup-vps", pings: [ping("q1", "Deploy?")], runningFor: 2)
        await harness.shipyard.start()
        await harness.poll()
        #expect(harness.herdr.runs(on: "netcup-vps").filter { $0.starts(with: ["plugin", "log", "list"]) }.count == 3)
        #expect(harness.titles("netcup-vps") == ["Deploy?"])
    }

    // MARK: The menu

    @Test("each machine's pings list under a section named after it, after the projects, needing attention")
    func machineSections() async throws {
        let harness = try await Harness.withMachines(
            hetzner: [ping("a1", "Tests are red", sender: "codex")],
            netcup: [ping("q1", "Deploy?", minutes: 1, sender: "claude"), ping("q2", "Merge it?", minutes: 9)]
        )
        // Before the first poll, only the projects.
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop"])
        #expect(harness.machineTimer.armed == 0)
        await harness.poll()

        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop", "hetzner-vps", "netcup-vps"])
        #expect(harness.shipyard.menu.sections.map(\.machine) == [nil, "hetzner-vps", "netcup-vps"])
        #expect(harness.titles("netcup-vps") == ["Deploy?", "Merge it?"])
        #expect(harness.titles("hetzner-vps") == ["Tests are red"])
        let rows = harness.shipyard.menu.sections.dropFirst().flatMap(\.rows)
        #expect(rows.allSatisfy { $0.needsAttention })
        #expect(harness.shipyard.menu.attention.pings == 3)
        #expect(harness.section("shop")?.rows.map(\.kind) == [.pullRequest])
    }

    @Test("a remote ping's row names its machine")
    func rowNamesMachine() async throws {
        let harness = try await Harness.withMachines(netcup: [ping("q1", "Deploy?", sender: "claude"), ping("q2", "Merge it?", minutes: 9)])
        await harness.poll()
        let rows = try #require(harness.section("netcup-vps")?.rows)
        #expect(rows.map(\.machine) == ["netcup-vps", "netcup-vps"])
        #expect(rows.map { PanelText.rowDetail($0, showingRepository: false) } == ["netcup-vps · claude", "netcup-vps"])
        #expect(rows.map(PanelText.pingMeta) == ["netcup-vps · claude", "netcup-vps"])
    }

    @Test("a remote ping is known as shipyard://ping/<machine>/<id>, so the same id on two machines, and here, stays apart")
    func identity() async throws {
        let harness = try await Harness.withMachines(hetzner: [ping("q1", "From hetzner")], netcup: [ping("q1", "From netcup")])
        harness.cli("ping", "From the Mac", "--project", "shop", "--id", "q1")
        await harness.shipyard.reloadPings()
        await harness.poll()
        #expect(harness.section("hetzner-vps")?.rows.map(\.id) == ["shipyard://ping/hetzner-vps/q1"])
        #expect(harness.section("netcup-vps")?.rows.map(\.id) == ["shipyard://ping/netcup-vps/q1"])
        #expect(harness.section("shop")?.rows.filter { $0.kind == .ping }.map(\.id) == ["shipyard://ping/q1"])
        #expect(harness.titles("hetzner-vps") == ["From hetzner"])
        #expect(harness.titles("netcup-vps") == ["From netcup"])
    }

    // MARK: Polling

    @Test("machines are polled every 30 seconds on their own timer, with no GitHub request")
    func ownTimer() async throws {
        let harness = try await Harness.withMachines(netcup: [ping("q1", "Deploy?")])
        let requests = harness.graphQLRequests.count
        let refreshArmed = harness.timer.armed
        await harness.poll()
        #expect(harness.machineTimer.armed == Shipyard.machinePollInterval)
        #expect(Shipyard.machinePollInterval == 30)

        harness.herdr.setPings([ping("q2", "Now this", minutes: 1)], on: "netcup-vps")
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Now this"])
        #expect(harness.graphQLRequests.count == requests)
        #expect(harness.timer.armed == refreshArmed)
        #expect(harness.machineTimer.armed == 30)
    }

    @Test("a GitHub refresh keeps the remote pings, and doesn't ask the machines")
    func refreshKeepsThem() async throws {
        let harness = try await Harness.withMachines(netcup: [ping("q1", "Deploy?")])
        await harness.poll()
        let runs = harness.herdr.runs.count
        await harness.timer.fire()
        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        #expect(harness.herdr.runs.count == runs)
    }

    @Test("a refresh before a machine's first poll keeps the folds of its section")
    func keepsMachineFolds() async throws {
        let harness = try await Harness.withMachines(netcup: [ping("q1", "Deploy?")])
        let fold = GroupID(project: "netcup-vps", key: .kind(.ping))
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
        harness.herdr.addMachine("hetzner-vps")
        harness.herdr.addMachine("netcup-vps", pings: [ping("q1", "Deploy?")])
        await harness.shipyard.start()
        await harness.poll()
        #expect(harness.titles("netcup-vps") == ["Deploy?"])
    }

    @Test("a machine that fails keeps its last pings and says why; the other lists as usual")
    func failureKeepsPings() async throws {
        let harness = try await Harness.withMachines(hetzner: [ping("a1", "Tests are red")], netcup: [ping("q1", "Deploy?")])
        await harness.poll()
        harness.herdr.setListOutput(#"{"version":2,"shipyardVersion":"9.0.0","pings":[],"truncated":false}"#, on: "netcup-vps")
        harness.herdr.setPings([ping("a2", "Fixed")], on: "hetzner-vps")
        await harness.poll()

        #expect(harness.titles("netcup-vps") == ["Deploy?"])
        #expect(harness.titles("hetzner-vps") == ["Fixed"])
        #expect(harness.shipyard.remote.machine("netcup-vps")?.failure
            == "netcup-vps lists pings in version 2 from shipyard 9.0.0, and this shipyard reads version 1: update shipyard on netcup-vps")
        #expect(harness.shipyard.remote.machine("hetzner-vps")?.failure == nil)
        #expect(harness.shipyard.menu.machineNotices.map(PanelText.machineNotice) == [
            "netcup-vps lists pings in version 2 from shipyard 9.0.0, and this shipyard reads version 1: update shipyard on netcup-vps. Its last pings stay listed.",
        ])
        #expect(harness.machineTimer.armed == 30)

        harness.herdr.setPings([], on: "netcup-vps")
        await harness.poll()
        #expect(harness.section("netcup-vps") == nil)
        #expect(harness.shipyard.remote.machine("netcup-vps")?.failure == nil)
        #expect(harness.shipyard.menu.machineNotices.isEmpty)
    }



    @Test("an edit adding or removing a machine applies at once; none left stops polling")
    func followsConfiguration() async throws {
        let harness = try await Harness.withMachines("[remote]\nmachines = [\"netcup-vps\"]\n\n" + shop, hetzner: [ping("a1", "Tests are red")], netcup: [ping("q1", "Deploy?")])
        await harness.poll()
        #expect(harness.herdr.runs(on: "hetzner-vps").isEmpty)

        try harness.writeConfig(twoMachines)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.machineTimer.armed == 0)
        await harness.poll()
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop", "hetzner-vps", "netcup-vps"])

        try harness.writeConfig("[remote]\nmachines = [\"hetzner-vps\"]\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop", "hetzner-vps"])

        try harness.writeConfig(shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop"])
        #expect(harness.machineTimer.armed == nil)
    }

    // MARK: Not the ping store's

    @Test("clicking, marking or dismissing a remote ping never touches a local ping with its id")
    func leavesLocalPings() async throws {
        let harness = try await Harness.withMachines(netcup: [ping("q1", "Remote")])
        harness.cli("ping", "Local", "--project", "shop", "--id", "q1", "--open", "https://example.com")
        await harness.shipyard.reloadPings()
        await harness.poll()
        let row = try #require(harness.section("netcup-vps")?.rows.first)

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

/// `RemotePingReader` on its own: what it makes of Herdr's answers.
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
        #expect(await reader.list(machine: "netcup-vps") == .failure(.init("netcup-vps didn't answer in time")))
        #expect(hanging.cancelled == hanging.started)
    }


    @Test("pings read from a machine carry its label")
    func marksMachine() async throws {
        let herdr = FakeHerdr()
        herdr.addMachine("My VPS", pings: [ping("q1", "Deploy?")])
        let list = try await herdr.remote.list(machine: "My VPS").get()
        #expect(list.pings.map(\.machine) == ["My VPS"])
        #expect(list.pings.map(\.item.url) == [URL(string: "shipyard://ping/My%20VPS/q1")!])
        let remote = try #require(Ping.remote(from: list.pings[0].item.url))
        #expect(remote.machine == "My VPS")
        #expect(remote.id == "q1")
        #expect(Ping.id(from: list.pings[0].item.url) == nil)
    }
}
