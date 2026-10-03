import Foundation
@testable import ShipyardCore
@testable import ShipyardPings
import Testing

/// `shop`, which watches `yahyabedirhan/shop`, and two remote machines.
private let twoMachines = """
    [remote]
    machines = ["hetzner-vps", "netcup-vps"]

    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

/// As `twoMachines`, but `shop`'s own rules don't select `ping.sent`.
private let quietShop = """
    [remote]
    machines = ["hetzner-vps", "netcup-vps"]

    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]
    notifications = []

    """

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

/// A ping as a machine's `shipyard` lists it, sent `minutes` before the
/// harness's now; `instance` names its sending.
private func ping(
    _ id: String,
    _ title: String,
    minutes: Double = 5,
    repository: String? = nil,
    instance: String? = nil
) -> Ping {
    Ping(
        id: id,
        title: title,
        projects: [],
        sent: Harness.now.addingTimeInterval(-minutes * 60),
        repository: repository,
        instance: instance ?? "i-\(id)"
    )
}

@MainActor
private extension Harness {
    /// A harness signed in with `config`, whose Herdr has saved
    /// `hetzner-vps` and `netcup-vps` listing `hetzner` and `netcup`, started.
    static func notifying(_ config: String = twoMachines, hetzner: [Ping] = [], netcup: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        try await harness.startWithMachines(hetzner: hetzner, netcup: netcup)
        return harness
    }

    /// Saves the two machines in this harness's Herdr and starts it.
    func startWithMachines(hetzner: [Ping] = [], netcup: [Ping] = []) async throws {
        stub.on(Harness.userURL, Harness.viewerAnswer)
        graphQL([onePullRequest])
        herdr.addMachine("hetzner-vps", pings: hetzner)
        herdr.addMachine("netcup-vps", pings: netcup)
        await shipyard.start()
    }

    /// Fires the machine timer, which must be armed, and waits for the poll.
    func poll(sourceLocation: SourceLocation = #_sourceLocation) async {
        let fired = await machineTimer.fire()
        #expect(fired, "the machine timer wasn't armed", sourceLocation: sourceLocation)
    }

    /// The pings' notifications posted so far.
    var pingNotifications: [PostedNotification] { notifier.posted.filter { $0.event == .pingSent } }
}

/// The notification id a remote ping's `ping.sent` posts under.
private func notificationID(_ machine: String, _ id: String, instance: String) -> String {
    "ping.sent \(Ping.url(machine: machine, id: id).absoluteString) \(instance)"
}

/// A remote ping notifies under the same `ping.sent` rule as a local one,
/// once per sending, and its notification leaves when the ping leaves its
/// machine: end to end from two fake machines' `list` answers to what the
/// recording notifier was asked to post and remove.
@Suite("A remote ping's notification")
@MainActor
struct RemotePingNotificationTests {
    @Test("a new remote ping posts one notification, in the project that files it or under its machine's name")
    func postsOne() async throws {
        let harness = try await Harness.notifying(
            hetzner: [ping("a1", "Tests are red", repository: "yahyabedirhan/shop")],
            netcup: [ping("q1", "Deploy?")]
        )
        #expect(harness.pingNotifications.isEmpty)
        await harness.poll()

        let posted = harness.pingNotifications.sorted { $0.title < $1.title }
        #expect(posted.map(\.title) == ["netcup-vps · Deploy?", "shop · Tests are red"])
        #expect(posted.map(\.itemURL) == [Ping.url(machine: "netcup-vps", id: "q1"), Ping.url(machine: "hetzner-vps", id: "a1")])
        #expect(posted.map(\.id) == [
            notificationID("netcup-vps", "q1", instance: "i-q1"),
            notificationID("hetzner-vps", "a1", instance: "i-a1"),
        ])
    }

    @Test("a project whose rules leave ping.sent out doesn't notify its remote pings; a machine's section uses the defaults")
    func followsRules() async throws {
        let harness = try await Harness.notifying(
            quietShop,
            hetzner: [ping("a1", "Tests are red", repository: "yahyabedirhan/shop")],
            netcup: [ping("q1", "Deploy?")]
        )
        await harness.poll()
        #expect(harness.section("shop")?.rows.filter { $0.kind == .ping }.map(\.title) == ["Tests are red"])
        #expect(harness.pingNotifications.map(\.title) == ["netcup-vps · Deploy?"])
    }

    @Test("once per sending: a replace, a poll or a refresh stays silent; sent anew takes the old banner and notifies; withdrawn takes its banner")
    func oncePerSending() async throws {
        let harness = try await Harness.notifying(netcup: [ping("q1", "Deploy?")])
        await harness.poll()
        #expect(harness.pingNotifications.count == 1)

        harness.herdr.setPings([ping("q1", "Deploy now?", minutes: 1)], on: "netcup-vps")
        await harness.poll()
        harness.graphQL([onePullRequest])
        harness.clock.advance(by: 120)
        await harness.shipyard.refresh()
        await harness.poll()
        #expect(harness.section("netcup-vps")?.rows.map(\.title) == ["Deploy now?"])
        #expect(harness.pingNotifications.count == 1)
        #expect(harness.notifier.removed.isEmpty)

        harness.herdr.setPings([ping("q1", "Deploy again?", minutes: 0, instance: "i-q1-2")], on: "netcup-vps")
        await harness.poll()
        #expect(harness.notifier.removed == [notificationID("netcup-vps", "q1", instance: "i-q1")])
        #expect(harness.pingNotifications.map(\.id) == [
            notificationID("netcup-vps", "q1", instance: "i-q1"),
            notificationID("netcup-vps", "q1", instance: "i-q1-2"),
        ])

        harness.herdr.setPings([], on: "netcup-vps")
        await harness.poll()
        #expect(harness.notifier.removed.last == notificationID("netcup-vps", "q1", instance: "i-q1-2"))
    }

    @Test("the same id on two machines notifies twice, and only the one that leaves takes its banner away")
    func sameIDOnTwoMachines() async throws {
        let harness = try await Harness.notifying(hetzner: [ping("q1", "From hetzner")], netcup: [ping("q1", "From netcup")])
        await harness.poll()
        #expect(Set(harness.pingNotifications.map(\.title)) == ["hetzner-vps · From hetzner", "netcup-vps · From netcup"])

        harness.herdr.setPings([], on: "hetzner-vps")
        await harness.poll()
        await harness.poll()
        #expect(harness.notifier.removed == [notificationID("hetzner-vps", "q1", instance: "i-q1")])
        #expect(harness.pingNotifications.count == 2)
    }

    @Test("a machine that fails, or whose list stops early, keeps its pings' notifications, and doesn't notify them again when they're back")
    func failingMachine() async throws {
        let harness = try await Harness.notifying(netcup: [ping("q1", "Deploy?")])
        await harness.poll()
        harness.herdr.setListOutput("not json", on: "netcup-vps")
        await harness.poll()
        #expect(harness.notifier.removed.isEmpty)
        #expect(harness.section("netcup-vps")?.rows.map(\.title) == ["Deploy?"])

        harness.herdr.setPings([ping("q1", "Deploy?")], on: "netcup-vps")
        await harness.poll()
        #expect(harness.pingNotifications.count == 1)
        #expect(harness.notifier.removed.isEmpty)

        // A list that stops early, before q1.
        let newer = (0..<PingList.maxPings).map { ping("n\($0)", "Newer \($0)", minutes: Double($0) / 1000) }
        harness.herdr.setPings(newer + [ping("q1", "Deploy?")], on: "netcup-vps")
        await harness.poll()
        #expect(harness.shipyard.remote.machine("netcup-vps")?.truncated == true)
        #expect(!harness.notifier.removed.contains(notificationID("netcup-vps", "q1", instance: "i-q1")))
        harness.herdr.setPings([ping("q1", "Deploy?")], on: "netcup-vps")
        await harness.poll()
        #expect(harness.pingNotifications.filter { $0.title == "netcup-vps · Deploy?" }.count == 1)
        #expect(!harness.notifier.removed.contains(notificationID("netcup-vps", "q1", instance: "i-q1")))
    }

    @Test("pings sent while the app wasn't running notify at its first poll; one notified before doesn't again; ones withdrawn meanwhile take their banners, even when that first answer is empty")
    func sentWhileAway() async throws {
        let first = try await Harness.notifying(netcup: [ping("q1", "Deploy?")])
        await first.poll()
        #expect(first.pingNotifications.count == 1)

        // Quit; meanwhile netcup's agent sends another.
        let next = first.relaunched()
        try await next.startWithMachines(netcup: [ping("q2", "Merge it?", minutes: 1), ping("q1", "Deploy?")])
        // Before the first poll answers, nothing leaves Notification Center.
        #expect(next.notifier.removed.isEmpty)
        await next.poll()
        #expect(next.pingNotifications.map(\.title) == ["netcup-vps · Merge it?"])
        #expect(next.notifier.removed.isEmpty)

        // Quit; meanwhile both are withdrawn.
        let last = next.relaunched()
        try await last.startWithMachines()
        await last.poll()
        #expect(last.notifier.removed.sorted() == [
            notificationID("netcup-vps", "q1", instance: "i-q1"),
            notificationID("netcup-vps", "q2", instance: "i-q2"),
        ])
    }

    @Test("a machine taken out of the configuration takes its pings' notifications away, with no projects to refresh, or while the app wasn't running")
    func machineRemoved() async throws {
        let harness = try await Harness.notifying(hetzner: [ping("a1", "Tests are red")], netcup: [ping("q1", "Deploy?")])
        await harness.poll()
        // Its projects go too, so no refresh runs after.
        try harness.writeConfig("[remote]\nmachines = [\"netcup-vps\"]\n")
        await harness.shipyard.reloadConfiguration()
        #expect(harness.notifier.removed == [notificationID("hetzner-vps", "a1", instance: "i-a1")])

        // Quit; meanwhile netcup is taken out too.
        try harness.writeConfig("")
        let next = harness.relaunched()
        try await next.startWithMachines(netcup: [ping("q1", "Deploy?")])
        #expect(next.notifier.removed == [notificationID("netcup-vps", "q1", instance: "i-q1")])
    }
}
