import Foundation
@testable import ShipyardCore
import Testing

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

/// `HERDR_PLUGIN_EVENT_JSON` as Herdr 0.9.3 sets it for
/// `pane.agent_status_changed`: the event envelope, its fields under `data`.
private func statusChanged(_ status: String, pane: String = "w1:p3", agent: String? = "claude") -> String {
    let agentField = agent.map { #","agent":"\#($0)""# } ?? ""
    return #"{"event":"pane_agent_status_changed","data":{"type":"pane_agent_status_changed","pane_id":"\#(pane)","workspace_id":"w1","agent_status":"\#(status)"\#(agentField)}}"#
}

/// `HERDR_PLUGIN_EVENT_JSON` for `pane.closed`.
private func paneClosed(_ pane: String = "w1:p3") -> String {
    #"{"event":"pane_closed","data":{"type":"pane_closed","pane_id":"\#(pane)","workspace_id":"w1"}}"#
}

/// `HERDR_PLUGIN_EVENT_JSON` for `tab.closed`, which names the tab, not its panes.
private func tabClosed(_ tab: String = "w1:t2") -> String {
    #"{"event":"tab_closed","data":{"type":"tab_closed","tab_id":"\#(tab)","workspace_id":"w1"}}"#
}

/// `HERDR_PLUGIN_EVENT_JSON` for `workspace.closed`.
private func workspaceClosed(_ workspace: String = "w1") -> String {
    #"{"event":"workspace_closed","data":{"type":"workspace_closed","workspace_id":"\#(workspace)"}}"#
}

/// The folder the blocked agent works in, in Herdr.
private let agentFolder = URL(fileURLWithPath: "/work/shop", isDirectory: true)

@MainActor
private extension Harness {
    /// Runs `shipyard herdr-event` as the herdr-shipyard plugin's hook does:
    /// with `HERDR_PLUGIN_EVENT` `event` and `HERDR_PLUGIN_EVENT_JSON` `json`
    /// (each `nil`: not set), Herdr's own `herdr` the fake one, and
    /// `agentFolder`'s `origin` `origin`, on `platform`, with the focused
    /// pane `focusedPane` (`HERDR_PANE_ID` in a hook is the focused pane).
    @discardableResult
    func herdrEvent(
        _ event: String?,
        _ json: String?,
        origin: String? = "git@github.com:yahyabedirhan/shop.git",
        platform: CommandPlatform = .macOS,
        focusedPane: String? = nil
    ) -> CommandResult {
        var variables = ["HERDR_BIN_PATH": FakeHerdr.path, "HERDR_ENV": "1"]
        variables["HERDR_PANE_ID"] = focusedPane
        variables["HERDR_PLUGIN_EVENT"] = event
        variables["HERDR_PLUGIN_EVENT_JSON"] = json
        return ShipyardCLI.run(
            ["herdr-event"],
            environment: CommandEnvironment(
                workingDirectory: URL(fileURLWithPath: "/plugins/herdr-shipyard", isDirectory: true),
                variables: variables,
                git: FakeGitRemote(origin.map { [agentFolder: $0] } ?? [:]),
                platform: platform,
                run: herdr.command,
                isExecutable: herdr.isExecutable
            ),
            configURL: configURL,
            repositories: repositoriesStore,
            pingStore: pingStore,
            now: clock.now
        )
    }

    /// `herdrEvent` for `pane.agent_status_changed` to `status`.
    @discardableResult
    func agent(_ status: String, pane: String = "w1:p3", agent: String? = "claude") -> CommandResult {
        herdrEvent("pane.agent_status_changed", statusChanged(status, pane: pane, agent: agent))
    }
}

/// `shipyard herdr-event`, run by the herdr-shipyard plugin's hooks: a
/// blocked agent pings by itself, and the ping goes when the agent goes on
/// or its pane closes. Through `ShipyardCLI.run` with recorded event JSON,
/// a fake `herdr` answering `pane get` and `tab get`, and the app reading
/// the store.
@Suite("Herdr events")
@MainActor
struct HerdrEventTests {
    // MARK: Blocked

    @Test("a blocked agent sends herdr-<pane>, from the agent, focusing its pane, naming its tab, filed by its folder")
    func blockedSends() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "CC · checkout", folder: agentFolder)

        let result = harness.agent("blocked")

        #expect(result == CommandResult(output: "herdr-w1-p3\n"))
        #expect(harness.herdr.runs == [["pane", "get", "w1:p3"], ["tab", "get", "w1:t2"]])
        let ping = try #require(harness.pingStore.ping(id: "herdr-w1-p3"))
        #expect(ping.title == "Claude is waiting in CC · checkout")
        #expect(ping.sender == "claude")
        #expect(ping.action == .herdr("w1:p3"))
        #expect(ping.projects == ["shop"])
        #expect(ping.repository == "yahyabedirhan/shop")
        #expect(ping.sent == harness.clock.now)

        await harness.shipyard.reloadPings()
        let row = try #require(harness.section("shop")?.rows.first { $0.kind == .ping })
        #expect(row.title == "Claude is waiting in CC · checkout")
        #expect(harness.notifier.posted.filter { $0.event == .pingSent }.count == 1)
    }

    @Test("on Linux a blocked agent's ping isn't filed, reads no config.toml, focuses the event's pane rather than the focused one, and expires a day later")
    func blockedOnLinux() throws {
        let harness = try Harness(config: shop)
        try harness.writeConfig("[[projects]\nname = ")
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout", folder: agentFolder)

        let result = harness.herdrEvent("pane.agent_status_changed", statusChanged("blocked"), platform: .linux, focusedPane: "w1:p9")

        #expect(result == CommandResult(output: "herdr-w1-p3\n"))
        let ping = try #require(harness.pingStore.ping(id: "herdr-w1-p3"))
        #expect(ping.action == .herdr("w1:p3"))
        #expect(ping.projects == [])
        #expect(ping.repository == "yahyabedirhan/shop")
        #expect(ping.expires == harness.clock.now.addingTimeInterval(PingCommand.lifetimeWithoutTheApp))
    }

    @Test("Herdr's display name for the agent, when it gives one, is the sender")
    func displayAgent() throws {
        let harness = try Harness(config: shop)
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout")
        let json = #"{"event":"pane_agent_status_changed","data":{"pane_id":"w1:p3","workspace_id":"w1","agent_status":"blocked","agent":"claude","display_agent":"Claude Code"}}"#

        #expect(harness.herdrEvent("pane.agent_status_changed", json).status == 0)

        let ping = try #require(harness.pingStore.ping(id: "herdr-w1-p3"))
        #expect(ping.title == "Claude Code is waiting in checkout")
        #expect(ping.sender == "Claude Code")
    }

    @Test("a tab without a label, a pane Herdr doesn't know, or no herdr at all: the title names the pane, and the ping is still sent")
    func noLabel() throws {
        let unlabelled = try Harness(config: shop)
        unlabelled.herdr.open(pane: "w1:p3", tab: "w1:t2")
        #expect(unlabelled.agent("blocked").status == 0)
        #expect(unlabelled.pingStore.ping(id: "herdr-w1-p3")?.title == "Claude is waiting in w1:p3")

        let unknown = try Harness(config: shop)
        #expect(unknown.agent("blocked").status == 0)
        #expect(unknown.herdr.runs == [["pane", "get", "w1:p3"]])
        #expect(unknown.pingStore.ping(id: "herdr-w1-p3")?.title == "Claude is waiting in w1:p3")

        let missing = try Harness(config: shop)
        missing.herdr.installed = false
        #expect(missing.agent("blocked") == CommandResult(output: "herdr-w1-p3\n"))
        #expect(missing.herdr.runs.isEmpty)
        #expect(missing.pingStore.ping(id: "herdr-w1-p3")?.title == "Claude is waiting in w1:p3")
    }

    @Test("without an agent's name, the title says an agent and there's no sender")
    func noAgent() throws {
        let harness = try Harness(config: shop)
        #expect(harness.agent("blocked", agent: nil).status == 0)
        let ping = try #require(harness.pingStore.ping(id: "herdr-w1-p3"))
        #expect(ping.title == "An agent is waiting in w1:p3")
        #expect(ping.sender == nil)
    }

    @Test("a pane whose repository no project watches, or with no configuration at all, still gets its ping, under no project")
    func unfiled() throws {
        let unwatched = try Harness(config: shop)
        unwatched.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "blog", folder: agentFolder)
        let result = unwatched.herdrEvent("pane.agent_status_changed", statusChanged("blocked"), origin: "git@github.com:yahyabedirhan/blog.git")
        #expect(result == CommandResult(output: "herdr-w1-p3\n"))
        let ping = try #require(unwatched.pingStore.ping(id: "herdr-w1-p3"))
        #expect(ping.projects == [])
        #expect(ping.repository == "yahyabedirhan/blog")

        let unconfigured = try Harness()
        unconfigured.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout")
        #expect(unconfigured.agent("blocked") == CommandResult(output: "herdr-w1-p3\n"))
        #expect(unconfigured.pingStore.ping(id: "herdr-w1-p3")?.projects == [])
        #expect(unconfigured.pingStore.ping(id: "herdr-w1-p3")?.repository == nil)
    }

    @Test("blocking again replaces the pane's ping: one ping, its new title, unseen again, and no second notification")
    func blockingAgainReplaces() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout", folder: agentFolder)
        harness.agent("blocked")
        await harness.shipyard.reloadPings()
        let first = try #require(harness.pingStore.ping(id: "herdr-w1-p3"))
        try harness.pingStore.markSeen(first, at: harness.clock.now)

        harness.clock.advance(by: 60)
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout, again", folder: agentFolder)
        #expect(harness.agent("blocked") == CommandResult(output: "herdr-w1-p3\n"))
        await harness.shipyard.reloadPings()

        #expect(harness.pingStore.all().count == 1)
        let again = try #require(harness.pingStore.ping(id: "herdr-w1-p3"))
        #expect(again.title == "Claude is waiting in checkout, again")
        #expect(again.seen == nil)
        #expect(again.sent == first.sent)
        #expect(again.instance == first.instance)
        #expect(harness.notifier.posted.filter { $0.event == .pingSent }.count == 1)
    }

    @Test("a blocked event for an agent Herdr already says went on sends nothing, and withdraws the pane's ping")
    func wentOnMeanwhile() throws {
        let harness = try Harness(config: shop)
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout", status: "blocked")
        harness.agent("blocked")
        #expect(harness.pingStore.ping(id: "herdr-w1-p3") != nil)

        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout", status: "working")
        #expect(harness.agent("blocked") == CommandResult(output: "herdr-w1-p3\n"))
        #expect(harness.pingStore.all().isEmpty)
        #expect(harness.agent("blocked") == CommandResult())
        #expect(harness.pingStore.all().isEmpty)
    }

    // MARK: Going on

    @Test("an agent that goes on withdraws its pane's ping, and its notification leaves", arguments: ["working", "idle", "done", "unknown"])
    func goingOnWithdraws(status: String) async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout", folder: agentFolder)
        harness.agent("blocked")
        await harness.shipyard.reloadPings()

        #expect(harness.agent(status) == CommandResult(output: "herdr-w1-p3\n"))
        await harness.shipyard.reloadPings()

        #expect(harness.pingStore.all().isEmpty)
        #expect(harness.section("shop")?.rows.contains { $0.kind == .ping } == false)
        #expect(harness.notifier.removed.count == 1)
    }

    @Test("a closed pane withdraws its ping")
    func closedPaneWithdraws() throws {
        let harness = try Harness(config: shop)
        harness.agent("blocked")
        harness.agent("blocked", pane: "w1:p4")

        #expect(harness.herdrEvent("pane.closed", paneClosed()) == CommandResult(output: "herdr-w1-p3\n"))

        #expect(harness.pingStore.all().map(\.id) == ["herdr-w1-p4"])
    }

    @Test("a closed tab, which Herdr sends no pane.closed for, withdraws the pings of the panes that went with it, and only those")
    func closedTabWithdraws() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout", folder: agentFolder)
        harness.herdr.open(pane: "w1:p4", tab: "w1:t2", label: "checkout", folder: agentFolder)
        harness.herdr.open(pane: "w1:p5", tab: "w1:t3", label: "cart", folder: agentFolder)
        harness.agent("blocked")
        harness.agent("blocked", pane: "w1:p4")
        harness.agent("blocked", pane: "w1:p5")
        // A ping an agent sent itself, focusing a pane in the tab: not herdr-event's to take back.
        try harness.pingStore.save(Ping(id: "mine", title: "Look at this", projects: ["shop"], sent: harness.clock.now, action: .herdr("w1:p3")))
        await harness.shipyard.reloadPings()

        harness.herdr.close(tab: "w1:t2")
        let result = harness.herdrEvent("tab.closed", tabClosed())
        await harness.shipyard.reloadPings()

        #expect(result == CommandResult(output: "herdr-w1-p3\nherdr-w1-p4\n"))
        #expect(harness.herdr.runs.last == ["pane", "list"])
        #expect(Set(harness.pingStore.all().map(\.id)) == ["herdr-w1-p5", "mine"])
        #expect(harness.notifier.removed.count == 2)
    }

    @Test("a closed workspace withdraws the pings of every pane that was in it")
    func closedWorkspaceWithdraws() throws {
        let harness = try Harness(config: shop)
        harness.herdr.open(pane: "w1:p3", tab: "w1:t2", label: "checkout")
        harness.herdr.open(pane: "w1:p7", tab: "w1:t4", label: "cart")
        harness.herdr.open(pane: "w2:p1", tab: "w2:t1", label: "blog")
        harness.agent("blocked")
        harness.agent("blocked", pane: "w1:p7")
        harness.agent("blocked", pane: "w2:p1")

        harness.herdr.close(workspace: "w1")
        #expect(harness.herdrEvent("workspace.closed", workspaceClosed()) == CommandResult(output: "herdr-w1-p3\nherdr-w1-p7\n"))
        #expect(harness.pingStore.all().map(\.id) == ["herdr-w2-p1"])

        #expect(harness.herdrEvent("workspace.closed", workspaceClosed()) == CommandResult())
        #expect(harness.pingStore.all().map(\.id) == ["herdr-w2-p1"])
    }

    @Test("when Herdr can't list its panes, a closed tab or workspace withdraws nothing, and says so on standard error, exit 1", arguments: ["tab.closed", "workspace.closed"])
    func closedWithoutHerdr(event: String) throws {
        let harness = try Harness(config: shop)
        harness.agent("blocked")

        harness.herdr.running = false
        let stopped = harness.herdrEvent(event, tabClosed())
        #expect(stopped == CommandResult(error: "shipyard herdr-event: \(event): herdr pane list didn't answer, so no ping was withdrawn\n", status: 1))
        harness.herdr.installed = false
        #expect(harness.herdrEvent(event, tabClosed()).status == 1)

        #expect(harness.pingStore.all().map(\.id) == ["herdr-w1-p3"])
    }

    @Test("a closed tab or workspace with no herdr-event ping stored runs no herdr, needs no configuration, and exits 0 quietly", arguments: ["tab.closed", "workspace.closed"])
    func closedWithNothingToWithdraw(event: String) throws {
        let harness = try Harness(config: shop)
        try harness.writeConfig("[[projects]\n")
        #expect(harness.herdrEvent(event, tabClosed()) == CommandResult())
        #expect(harness.herdr.runs.isEmpty)
    }

    @Test("withdrawing with no ping for the pane does nothing, and exits 0 quietly", arguments: ["working", "idle", "done", "unknown"])
    func nothingToWithdraw(status: String) throws {
        let harness = try Harness(config: shop)
        #expect(harness.agent(status) == CommandResult())
        #expect(harness.herdrEvent("pane.closed", paneClosed()) == CommandResult())
        #expect(harness.herdr.runs.isEmpty)
    }

    @Test("a withdraw needs no configuration: a config.toml that doesn't read stops a blocked ping, not a withdraw")
    func brokenConfiguration() throws {
        let harness = try Harness(config: shop)
        harness.agent("blocked")
        try harness.writeConfig("[[projects]\n")

        let blocked = harness.agent("blocked", pane: "w1:p4")
        #expect(blocked.status == 1)
        #expect(blocked.error.hasPrefix("shipyard: config.toml doesn't read"))
        #expect(harness.agent("working") == CommandResult(output: "herdr-w1-p3\n"))
        #expect(harness.pingStore.all().isEmpty)
    }

    // MARK: Nothing to do, and errors

    @Test("another event or status needs nothing, and exits 0")
    func otherEvents() throws {
        let harness = try Harness(config: shop)
        #expect(harness.herdrEvent("startup", nil) == CommandResult())
        #expect(harness.herdrEvent("pane.focused", #"{"event":"pane_focused","data":{"pane_id":"w1:p3"}}"#) == CommandResult())
        #expect(harness.agent("thinking") == CommandResult())
        #expect(harness.pingStore.all().isEmpty)
    }

    @Test("a payload that's missing or doesn't read is an error on standard error, exit 1")
    func badPayload() throws {
        let harness = try Harness(config: shop)
        let missing = harness.herdrEvent("pane.agent_status_changed", nil)
        #expect(missing == CommandResult(error: "shipyard herdr-event: pane.agent_status_changed: HERDR_PLUGIN_EVENT_JSON isn't set\n", status: 1))
        let notJSON = harness.herdrEvent("pane.closed", "pane w1:p3")
        #expect(notJSON == CommandResult(error: "shipyard herdr-event: pane.closed: HERDR_PLUGIN_EVENT_JSON isn't a JSON object\n", status: 1))
        let noPane = harness.herdrEvent("pane.agent_status_changed", #"{"data":{"agent_status":"blocked"}}"#)
        #expect(noPane == CommandResult(error: "shipyard herdr-event: pane.agent_status_changed: HERDR_PLUGIN_EVENT_JSON names no pane_id\n", status: 1))
        let noStatus = harness.herdrEvent("pane.agent_status_changed", #"{"data":{"pane_id":"w1:p3"}}"#)
        #expect(noStatus.status == 1)
        #expect(noStatus.error == "shipyard herdr-event: pane.agent_status_changed: HERDR_PLUGIN_EVENT_JSON doesn't say the agent's status\n")
        #expect(harness.pingStore.all().isEmpty)
    }

    @Test("outside a Herdr hook (no HERDR_PLUGIN_EVENT), or with arguments, it's a usage error, exit 2")
    func usage() throws {
        let harness = try Harness(config: shop)
        let outside = harness.herdrEvent(nil, statusChanged("blocked"))
        #expect(outside.status == 2)
        #expect(outside.error == "shipyard herdr-event: HERDR_PLUGIN_EVENT isn't set; Herdr's plugin event hooks run this command\n")
        let extra = harness.cli("herdr-event", "blocked")
        #expect(extra.status == 2)
        #expect(harness.pingStore.all().isEmpty)
    }

    @Test("the fields read from the payload's top level too")
    func topLevelPayload() throws {
        let harness = try Harness(config: shop)
        let json = #"{"pane_id":"w1:p3","workspace_id":"w1","agent_status":"Blocked","agent":"codex"}"#
        #expect(harness.herdrEvent("pane.agent_status_changed", json) == CommandResult(output: "herdr-w1-p3\n"))
        #expect(harness.pingStore.ping(id: "herdr-w1-p3")?.sender == "codex")
    }

    @Test("the ping's id is herdr- and the pane's id lowercased, each character outside the id alphabet a -", arguments: [
        ("w1:p3", "herdr-w1-p3"),
        ("wA:p1", "herdr-wa-p1"),
        ("wB:p1", "herdr-wb-p1"),
        ("ws_2:p10", "herdr-ws_2-p10"),
        (String(repeating: "a", count: 80), "herdr-" + String(repeating: "a", count: 58)),
    ])
    func pingIDs(pane: String, id: String) {
        #expect(HerdrEvent.pingID(pane: pane) == id)
        #expect(PingCommand.isID(HerdrEvent.pingID(pane: pane)))
    }
}
