import Foundation
@testable import ShipyardCommand
@testable import ShipyardCore
@testable import ShipyardPings
import Testing

private let config = """
    [herdr]
    terminal = "Ghostty"

    [remote]
    machines = ["alpha-vps", "beta-vps"]

    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

@MainActor
private extension Harness {
    static func polled(alpha: [Ping] = [], beta: [Ping] = []) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        await harness.startWithMachines(graphQL: onePullRequest, alpha: alpha, beta: beta, polled: true)
        return harness
    }

    func remoteRow(_ title: String, on machine: String = "beta-vps") throws -> MenuRow {
        try #require(section(machine)?.rows.first { $0.title == title })
    }

    func clickRemote(_ title: String, on machine: String = "beta-vps") async throws {
        await shipyard.open(try remoteRow(title, on: machine)).value
    }

    func focusRuns(on machine: String) -> [[String]] {
        herdr.runs(on: machine).filter { $0.first != "plugin" }
    }
}

@Suite("Clicking a remote ping")
@MainActor
struct RemoteClickTests {

    @Test("a pane's agent is focused on its machine, then the terminal comes forward, and the ping is seen")
    func focusesAgent() async throws {
        let harness = try await Harness.polled(beta: [remotePing("q1", "Deploy?", action: .herdr("w1:p3"))])
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", on: "beta-vps")
        #expect(harness.shipyard.menu.attention.pings == 1)

        try await harness.clickRemote("Deploy?")

        #expect(harness.focusRuns(on: "beta-vps") == [["agent", "focus", "w1:p3"]])
        #expect(harness.focusRuns(on: "alpha-vps").isEmpty)
        #expect(harness.herdr.runs.allSatisfy { $0.first == "--machine" })
        #expect(harness.actions.ran == [.app("Ghostty")])
        #expect(try !harness.remoteRow("Deploy?").needsAttention)
        #expect(harness.shipyard.menu.attention.pings == 0)
    }

    @Test("a pane no agent occupies is focused by its tab; a tab is focused at once")
    func focusesTab() async throws {
        let harness = try await Harness.polled(beta: [
            remotePing("q1", "Shell", action: .herdr("w1:p4")),
            remotePing("q2", "Tab", action: .herdr("w1:t5")),
        ])
        harness.herdr.open(pane: "w1:p4", tab: "w1:t2", agent: false, on: "beta-vps")
        harness.herdr.open(pane: "w1:p6", tab: "w1:t5", on: "beta-vps")

        try await harness.clickRemote("Shell")
        try await harness.clickRemote("Tab")

        #expect(harness.focusRuns(on: "beta-vps") == [
            ["agent", "focus", "w1:p4"],
            ["pane", "get", "w1:p4"],
            ["tab", "focus", "w1:t2"],
            ["tab", "focus", "w1:t5"],
        ])
        #expect(harness.actions.ran == [.app("Ghostty"), .app("Ghostty")])
        #expect(harness.section("beta-vps")?.rows.allSatisfy { !$0.needsAttention } == true)
    }

    @Test("the same id on two machines: the click focuses its own machine")
    func ownMachine() async throws {
        let harness = try await Harness.polled(
            alpha: [remotePing("q1", "From alpha", action: .herdr("w1:p3"))],
            beta: [remotePing("q1", "From beta", action: .herdr("w1:p3"))]
        )
        harness.herdr.open(pane: "w1:p3", tab: "w1:t1", on: "alpha-vps")
        harness.herdr.open(pane: "w1:p3", tab: "w1:t1", on: "beta-vps")

        try await harness.clickRemote("From beta")

        #expect(harness.focusRuns(on: "beta-vps") == [["agent", "focus", "w1:p3"]])
        #expect(harness.focusRuns(on: "alpha-vps").isEmpty)
    }

    @Test("its notification runs the action as its row does")
    func notification() async throws {
        let harness = try await Harness.polled(beta: [remotePing("q1", "Deploy?", action: .herdr("w1:p3"))])
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", on: "beta-vps")

        await harness.shipyard.openNotification(Ping.url(machine: "beta-vps", id: "q1")).value

        #expect(harness.focusRuns(on: "beta-vps") == [["agent", "focus", "w1:p3"]])
        #expect(harness.actions.ran == [.app("Ghostty")])
        #expect(try !harness.remoteRow("Deploy?").needsAttention)
    }

    @Test("a link or an app opens on the Mac, as a local ping's does, nothing runs on the machine, and each is seen; so is one without an action")
    func onTheMac() async throws {
        let link = URL(string: "https://github.com/yahyabedirhan/shop/pull/1")!
        let harness = try await Harness.polled(beta: [
            remotePing("l1", "Review this", action: .url(link)),
            remotePing("a1", "Look at the simulator", action: .app("Simulator")),
            remotePing("n1", "FYI"),
        ])

        try await harness.clickRemote("Review this")
        try await harness.clickRemote("Look at the simulator")
        try await harness.clickRemote("FYI")

        #expect(harness.actions.ran == [.url(link), .app("Simulator")])
        #expect(harness.focusRuns(on: "beta-vps").isEmpty)
        #expect(harness.section("beta-vps")?.rows.allSatisfy { !$0.needsAttention } == true)
    }

    @Test("a pane that's gone says so on the row and stays unseen, across polls; a later click that works clears it")
    func paneGone() async throws {
        let harness = try await Harness.polled(beta: [remotePing("q1", "Deploy?", action: .herdr("w1:p3"))])

        try await harness.clickRemote("Deploy?")

        var row = try harness.remoteRow("Deploy?")
        #expect(row.actionError == "Pane gone")
        #expect(PanelText.rowCard(row, now: harness.clock.now).lines.last == "Herdr pane w1:p3 is gone on beta-vps")
        #expect(row.needsAttention)
        #expect(harness.actions.ran.isEmpty)
        _ = await harness.machineTimer.fire()
        #expect(try harness.remoteRow("Deploy?").actionError == "Pane gone")

        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", on: "beta-vps")
        try await harness.clickRemote("Deploy?")

        row = try harness.remoteRow("Deploy?")
        #expect(row.actionError == nil)
        #expect(!row.needsAttention)
    }

    @Test("a machine Herdr can't reach says so on the row, and the ping stays unseen")
    func unreachable() async throws {
        let harness = try await Harness.polled(beta: [remotePing("q1", "Deploy?", action: .herdr("w1:p3"))])
        harness.herdr.setReach(.unreachable, on: "beta-vps")

        try await harness.clickRemote("Deploy?")

        let row = try harness.remoteRow("Deploy?")
        #expect(row.actionError == "Offline")
        #expect(PanelText.rowCard(row, now: harness.clock.now).lines.last == "Couldn't reach beta-vps through Herdr")
        #expect(row.needsAttention)
        #expect(harness.actions.ran.isEmpty)
    }

    @Test("a ping replaced on its machine loses its old sending's failure")
    func replaced() async throws {
        let harness = try await Harness.polled(beta: [remotePing("q1", "Deploy?", action: .herdr("w1:p3"))])
        try await harness.clickRemote("Deploy?")
        #expect(try harness.remoteRow("Deploy?").actionError != nil)

        harness.herdr.setPings([remotePing("q1", "Deploy now?", action: .herdr("w1:p3"))], on: "beta-vps")
        _ = await harness.machineTimer.fire()

        #expect(try harness.remoteRow("Deploy now?").actionError == nil)
    }
}

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
        #expect(await focus.focus("w1:p3", on: "beta-vps") == .failed("No answer", detail: "beta-vps didn't answer in time"))
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
