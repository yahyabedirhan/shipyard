import Foundation
@testable import ShipyardCore
import Testing

/// `shop`, two remote machines, and `[herdr] terminal` set to Ghostty.
private let config = """
    [herdr]
    terminal = "Ghostty"

    [remote]
    machines = ["hetzner-vps", "netcup-vps"]

    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

/// A ping as a machine's `shipyard` lists it, with the action `action`.
private func ping(_ id: String, _ title: String, action: PingAction? = nil) -> Ping {
    Ping(id: id, title: title, projects: [], sent: Harness.now.addingTimeInterval(-300), action: action, instance: "i-\(id)")
}

@MainActor
private extension Harness {
    /// A harness signed in with `config`, whose Herdr has saved
    /// `hetzner-vps` and `netcup-vps` listing `hetzner` and `netcup`,
    /// started and polled once.
    static func polled(hetzner: [Ping] = [], netcup: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        harness.herdr.addMachine("hetzner-vps", pings: hetzner)
        harness.herdr.addMachine("netcup-vps", pings: netcup)
        await harness.shipyard.start()
        _ = await harness.machineTimer.fire()
        return harness
    }

    /// The row titled `title` in the section of the machine `machine`.
    func remoteRow(_ title: String, on machine: String = "netcup-vps") throws -> MenuRow {
        try #require(section(machine)?.rows.first { $0.title == title })
    }

    /// Clicks the row titled `title` on `machine` and waits for its action.
    func clickRemote(_ title: String, on machine: String = "netcup-vps") async throws {
        await shipyard.open(try remoteRow(title, on: machine)).value
    }

    /// The runs on `machine` past its polls' plugin runs.
    func focusRuns(on machine: String) -> [[String]] {
        herdr.runs(on: machine).filter { $0.first != "plugin" }
    }
}

/// Clicking a remote ping: a pane or tab is focused on its machine through
/// `herdr --machine`, then `[herdr] terminal` comes forward; a link or an
/// app opens on the Mac. One that works marks the ping seen on the Mac;
/// one that fails says why on its row. End to end across `Shipyard`,
/// `HerdrFocus` and `RemotePingReader` over a fake `herdr` with two saved
/// machines, the recording action port, and the menu model.
@Suite("Clicking a remote ping")
@MainActor
struct RemoteClickTests {
    // MARK: A Herdr action

    @Test("a pane's agent is focused on its machine, then the terminal comes forward, and the ping is seen")
    func focusesAgent() async throws {
        let harness = try await Harness.polled(netcup: [ping("q1", "Deploy?", action: .herdr("w1:p3"))])
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", on: "netcup-vps")
        #expect(harness.shipyard.menu.attention.pings == 1)

        try await harness.clickRemote("Deploy?")

        #expect(harness.focusRuns(on: "netcup-vps") == [["agent", "focus", "w1:p3"]])
        #expect(harness.focusRuns(on: "hetzner-vps").isEmpty)
        // Nothing focuses on the Mac's own Herdr.
        #expect(harness.herdr.runs.allSatisfy { $0.first == "--machine" })
        #expect(harness.actions.ran == [.app("Ghostty")])
        #expect(try !harness.remoteRow("Deploy?").needsAttention)
        #expect(harness.shipyard.menu.attention.pings == 0)
    }

    @Test("a pane no agent occupies is focused by its tab; a tab is focused at once")
    func focusesTab() async throws {
        let harness = try await Harness.polled(netcup: [
            ping("q1", "Shell", action: .herdr("w1:p4")),
            ping("q2", "Tab", action: .herdr("w1:t5")),
        ])
        harness.herdr.open(pane: "w1:p4", tab: "w1:t2", agent: false, on: "netcup-vps")
        harness.herdr.open(pane: "w1:p6", tab: "w1:t5", on: "netcup-vps")

        try await harness.clickRemote("Shell")
        try await harness.clickRemote("Tab")

        #expect(harness.focusRuns(on: "netcup-vps") == [
            ["agent", "focus", "w1:p4"],
            ["pane", "get", "w1:p4"],
            ["tab", "focus", "w1:t2"],
            ["tab", "focus", "w1:t5"],
        ])
        #expect(harness.actions.ran == [.app("Ghostty"), .app("Ghostty")])
        #expect(harness.section("netcup-vps")?.rows.allSatisfy { !$0.needsAttention } == true)
    }

    @Test("the same id on two machines: the click focuses its own machine")
    func ownMachine() async throws {
        let harness = try await Harness.polled(
            hetzner: [ping("q1", "From hetzner", action: .herdr("w1:p3"))],
            netcup: [ping("q1", "From netcup", action: .herdr("w1:p3"))]
        )
        harness.herdr.open(pane: "w1:p3", tab: "w1:t1", on: "hetzner-vps")
        harness.herdr.open(pane: "w1:p3", tab: "w1:t1", on: "netcup-vps")

        try await harness.clickRemote("From netcup")

        #expect(harness.focusRuns(on: "netcup-vps") == [["agent", "focus", "w1:p3"]])
        #expect(harness.focusRuns(on: "hetzner-vps").isEmpty)
    }

    @Test("its notification runs the action as its row does")
    func notification() async throws {
        let harness = try await Harness.polled(netcup: [ping("q1", "Deploy?", action: .herdr("w1:p3"))])
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", on: "netcup-vps")

        await harness.shipyard.openNotification(Ping.url(machine: "netcup-vps", id: "q1")).value

        #expect(harness.focusRuns(on: "netcup-vps") == [["agent", "focus", "w1:p3"]])
        #expect(harness.actions.ran == [.app("Ghostty")])
        #expect(try !harness.remoteRow("Deploy?").needsAttention)
    }

    // MARK: On the Mac

    @Test("a link or an app opens on the Mac, as a local ping's does, nothing runs on the machine, and each is seen; so is one without an action")
    func onTheMac() async throws {
        let link = URL(string: "https://github.com/yahyabedirhan/shop/pull/1")!
        let harness = try await Harness.polled(netcup: [
            ping("l1", "Review this", action: .url(link)),
            ping("a1", "Look at the simulator", action: .app("Simulator")),
            ping("n1", "FYI"),
        ])

        try await harness.clickRemote("Review this")
        try await harness.clickRemote("Look at the simulator")
        try await harness.clickRemote("FYI")

        #expect(harness.actions.ran == [.url(link), .app("Simulator")])
        #expect(harness.focusRuns(on: "netcup-vps").isEmpty)
        #expect(harness.section("netcup-vps")?.rows.allSatisfy { !$0.needsAttention } == true)
    }

    // MARK: Failing

    @Test("a pane that's gone says so on the row and stays unseen, across polls; a later click that works clears it")
    func paneGone() async throws {
        let harness = try await Harness.polled(netcup: [ping("q1", "Deploy?", action: .herdr("w1:p3"))])

        try await harness.clickRemote("Deploy?")

        var row = try harness.remoteRow("Deploy?")
        #expect(row.actionError == "Pane gone")
        #expect(PanelText.rowCard(row, now: harness.clock.now).lines.last == "Herdr pane w1:p3 is gone on netcup-vps")
        #expect(row.needsAttention)
        #expect(harness.actions.ran.isEmpty)
        _ = await harness.machineTimer.fire()
        #expect(try harness.remoteRow("Deploy?").actionError == "Pane gone")

        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", on: "netcup-vps")
        try await harness.clickRemote("Deploy?")

        row = try harness.remoteRow("Deploy?")
        #expect(row.actionError == nil)
        #expect(!row.needsAttention)
    }

    @Test("a machine Herdr can't reach says so on the row, and the ping stays unseen")
    func unreachable() async throws {
        let harness = try await Harness.polled(netcup: [ping("q1", "Deploy?", action: .herdr("w1:p3"))])
        harness.herdr.setReach(.unreachable, on: "netcup-vps")

        try await harness.clickRemote("Deploy?")

        let row = try harness.remoteRow("Deploy?")
        #expect(row.actionError == "Offline")
        #expect(PanelText.rowCard(row, now: harness.clock.now).lines.last == "Couldn't reach netcup-vps through Herdr")
        #expect(row.needsAttention)
        #expect(harness.actions.ran.isEmpty)
    }

    @Test("a ping replaced on its machine loses its old sending's failure")
    func replaced() async throws {
        let harness = try await Harness.polled(netcup: [ping("q1", "Deploy?", action: .herdr("w1:p3"))])
        try await harness.clickRemote("Deploy?")
        #expect(try harness.remoteRow("Deploy?").actionError != nil)

        // The same id and instance, a new title: `shipyard ping --id` again.
        harness.herdr.setPings([ping("q1", "Deploy now?", action: .herdr("w1:p3"))], on: "netcup-vps")
        _ = await harness.machineTimer.fire()

        #expect(try harness.remoteRow("Deploy now?").actionError == nil)
    }
}

/// `HerdrFocus` on a saved machine, on its own: what it makes of Herdr's answers.
@Suite("Focusing on a machine")
struct HerdrMachineFocusTests {
    @Test("a machine that doesn't answer in time fails the focus, and its herdr is stopped")
    func timesOut() async {
        let shell = HangingShell()
        let focus = HerdrFocus(
            home: URL(fileURLWithPath: "/nonexistent-home"),
            pathEnvironment: nil,
            isExecutable: { $0 == FakeHerdr.path },
            runner: shell,
            machineTimeout: 0.01
        )
        #expect(await focus.focus("w1:p3", on: "netcup-vps") == .failed("No answer", detail: "netcup-vps didn't answer in time"))
        #expect(shell.started == 1)
        #expect(shell.cancelled == 1)
    }

    @Test("a label Herdr doesn't know fails with the reason the poll gives")
    func unknownLabel() async {
        let shell = FakeShell(ShellOutput(status: 2, output: "error: unknown machine 'typo-vps'; use `herdr machine list`\n"))
        let focus = HerdrFocus(
            home: URL(fileURLWithPath: "/nonexistent-home"),
            pathEnvironment: nil,
            isExecutable: { $0 == FakeHerdr.path },
            runner: shell
        )
        #expect(await focus.focus("w1:p3", on: "typo-vps") == .failed("No machine", detail: "Herdr has no saved machine named typo-vps"))
        #expect(shell.invocations.map(\.arguments) == [["--machine", "typo-vps", "agent", "focus", "w1:p3"]])
    }
}
