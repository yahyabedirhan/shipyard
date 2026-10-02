import Foundation
@testable import ShipyardCore
import Testing

private let shop = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

/// `shop` with `[herdr] terminal` set to Ghostty.
private let shopInGhostty = "[herdr]\nterminal = \"Ghostty\"\n\n" + shop

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

@MainActor
private extension Harness {
    /// Sends a ping to `shop` through the CLI with `flags`, from the Herdr
    /// pane `pane`, and returns its id, then lets the app see the store change.
    @discardableResult
    func send(_ title: String, _ flags: String..., pane: String? = nil, variables: [String: String] = [:]) async throws -> String {
        let result = cli(["ping", title, "--project", "shop"] + flags, herdrPane: pane, variables: variables)
        try #require(result.status == 0, "\(result.error)")
        await shipyard.reloadPings()
        return result.output.trimmingCharacters(in: .newlines)
    }

    /// The ping row titled `title` in `shop`.
    func pingRow(_ title: String) throws -> MenuRow {
        try #require(section("shop")?.rows.first { $0.kind == .ping && $0.title == title })
    }

    /// Clicks the ping row titled `title` and waits for its action.
    func click(_ title: String) async throws {
        await shipyard.open(try pingRow(title)).value
    }
}

/// `--herdr` through the CLI, and what clicking the ping then does: focus
/// the Herdr tab or pane, then bring `[herdr] terminal` forward. End to end
/// across the ping command, the store, `Shipyard`, `HerdrFocus` over a fake
/// `herdr`, and the recording action port.
@Suite("A ping's Herdr action")
@MainActor
struct HerdrActionTests {
    // MARK: The command

    @Test("--herdr with no id takes the agent's own pane from HERDR_PANE_ID")
    func ownPane() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try await harness.send("Waiting for you", "--herdr", pane: "w1:p3")
        #expect(harness.pingStore.ping(id: id)?.action == .herdr("w1:p3"))
    }

    @Test("--herdr with no id outside Herdr is a usage error, and nothing is stored")
    func outsideHerdr() throws {
        let harness = try Harness(config: shop)
        let result = harness.cli("ping", "Waiting", "--project", "shop", "--herdr")
        #expect(result.status == 2)
        #expect(result.error == "shipyard ping: `--herdr` without an id focuses your own pane, but HERDR_PANE_ID isn't set (you're not in Herdr); pass a tab or pane id such as w1:t2\n")
        #expect(harness.pingStore.all().isEmpty)
        #expect(harness.cli("ping", "Waiting", "--project", "shop", "--herdr", herdrPane: " ").status == 2)
    }

    @Test("--herdr takes a tab or pane id, wherever the agent runs")
    func givenID() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let tab = try await harness.send("Tab", "--herdr", "w1:t2", pane: "w1:p3")
        let pane = try await harness.send("Pane", "--herdr", "w2:p7")
        #expect(harness.pingStore.ping(id: tab)?.action == .herdr("w1:t2"))
        #expect(harness.pingStore.ping(id: pane)?.action == .herdr("w2:p7"))
    }

    @Test("only an argument shaped like a Herdr id is --herdr's; another is the title, or the next flag")
    func followingArgument() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let result = harness.cli("ping", "--herdr", "Ready: w1", "--project", "shop", herdrPane: "w1:p3")
        try #require(result.status == 0, "\(result.error)")
        let ping = try #require(harness.pingStore.ping(id: result.output.trimmingCharacters(in: .newlines)))
        #expect(ping.title == "Ready: w1")
        #expect(ping.action == .herdr("w1:p3"))
        #expect(PingCommand.isHerdrID("w1:t2"))
        #expect(PingCommand.isHerdrID("wD:p12"))
        #expect(!PingCommand.isHerdrID("w1"))
        #expect(!PingCommand.isHerdrID("w1:x2"))
        #expect(!PingCommand.isHerdrID("a b:t2"))
        #expect(!PingCommand.isHerdrID("--from"))
        // A trailing newline isn't part of an id.
        #expect(!PingCommand.isHerdrID("w1:t2\n"))
        #expect(!PingCommand.isHerdrID("w1:t2\nw1:t3"))
    }

    @Test("--herdr with another action flag is a usage error")
    func oneAction() throws {
        let harness = try Harness(config: shop)
        let result = harness.cli("ping", "Ready", "--project", "shop", "--herdr", "w1:t2", "--app", "Claude")
        #expect(result.status == 2)
        #expect(result.error == "shipyard ping: a ping has one action at most; pass one of --open, --app, --herdr\n")
        #expect(harness.pingStore.all().isEmpty)
    }

    // MARK: The terminal it was sent from

    /// An environment and the terminal app `--herdr` records from it.
    struct Outer: Sendable, CustomTestStringConvertible {
        var variables: [String: String]
        var terminal: String?
        var testDescription: String { "\(variables) -> \(terminal ?? "none")" }
    }

    nonisolated static let outers: [Outer] = [
        Outer(variables: ["TERM_PROGRAM": "ghostty"], terminal: "com.mitchellh.ghostty"),
        Outer(variables: ["TERM_PROGRAM": "iTerm.app"], terminal: "com.googlecode.iterm2"),
        Outer(variables: ["TERM_PROGRAM": "Apple_Terminal"], terminal: "com.apple.Terminal"),
        Outer(variables: ["TERM_PROGRAM": "WezTerm"], terminal: "com.github.wez.wezterm"),
        Outer(variables: ["TERM_PROGRAM": "vscode"], terminal: "com.microsoft.VSCode"),
        Outer(variables: ["TERM_PROGRAM": "WarpTerminal"], terminal: "dev.warp.Warp-Stable"),
        Outer(variables: ["KITTY_WINDOW_ID": "3"], terminal: "net.kovidgoyal.kitty"),
        Outer(variables: ["TERM": "xterm-kitty"], terminal: "net.kovidgoyal.kitty"),
        Outer(variables: ["ALACRITTY_WINDOW_ID": "1"], terminal: "org.alacritty"),
        // Inside Herdr, TERM_PROGRAM is herdr's own; the app that launched
        // the shell's server is named by __CFBundleIdentifier.
        Outer(variables: ["TERM_PROGRAM": "herdr", "__CFBundleIdentifier": "com.mitchellh.ghostty"], terminal: "com.mitchellh.ghostty"),
        Outer(variables: ["TERM_PROGRAM": "ghostty", "__CFBundleIdentifier": "com.apple.Terminal"], terminal: "com.mitchellh.ghostty"),
        Outer(variables: ["TERM_PROGRAM": "herdr"], terminal: nil),
        Outer(variables: ["TERM_PROGRAM": "unheard-of", "__CFBundleIdentifier": " "], terminal: nil),
        Outer(variables: [:], terminal: nil),
    ]

    @Test("--herdr records the terminal app it was run in", arguments: outers)
    func recordsTerminal(_ outer: Outer) async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try await harness.send("Waiting", "--herdr", pane: "w1:p3", variables: outer.variables)
        #expect(harness.pingStore.ping(id: id)?.terminal == outer.terminal)
    }

    @Test("only a --herdr ping records a terminal")
    func otherActionsRecordNone() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let variables = ["TERM_PROGRAM": "ghostty"]
        let app = try await harness.send("App", "--app", "Claude", variables: variables)
        let none = try await harness.send("None", variables: variables)
        #expect(harness.pingStore.ping(id: app)?.terminal == nil)
        #expect(harness.pingStore.ping(id: none)?.terminal == nil)
    }

    // MARK: Clicking

    @Test("clicking a tab's ping focuses the tab and marks it seen; without [herdr] terminal nothing else runs")
    func focusTab() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.herdr.open(tab: "w1:t2")
        let id = try await harness.send("Tab", "--herdr", "w1:t2")

        try await harness.click("Tab")

        #expect(harness.herdr.runs == [["tab", "focus", "w1:t2"]])
        #expect(harness.herdr.focused == ["w1:t2"])
        #expect(harness.actions.ran.isEmpty)
        #expect(harness.actions.opened.isEmpty)
        #expect(harness.pingStore.ping(id: id)?.seen == harness.clock.now)
        #expect(try harness.pingRow("Tab").needsAttention == false)
    }

    @Test("with no [herdr] terminal, the click brings forward the terminal the ping was sent from")
    func recordedTerminal() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.herdr.open(tab: "w1:t2")
        try await harness.send("Tab", "--herdr", "w1:t2", variables: ["TERM_PROGRAM": "herdr", "__CFBundleIdentifier": "com.mitchellh.ghostty"])

        try await harness.click("Tab")

        #expect(harness.herdr.focused == ["w1:t2"])
        #expect(harness.actions.ran == [.app("com.mitchellh.ghostty")])
    }

    @Test("[herdr] terminal wins over the terminal the ping was sent from")
    func configuredTerminalWins() async throws {
        let harness = try await Harness.started(config: shopInGhostty, graphQL: onePullRequest)
        harness.herdr.open(tab: "w1:t2")
        try await harness.send("Tab", "--herdr", "w1:t2", variables: ["TERM_PROGRAM": "iTerm.app"])

        try await harness.click("Tab")

        #expect(harness.actions.ran == [.app("Ghostty")])
    }

    @Test("a ping sent from an unknown terminal brings none forward")
    func noTerminalKnown() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.herdr.open(tab: "w1:t2")
        try await harness.send("Tab", "--herdr", "w1:t2")
        try await harness.click("Tab")
        #expect(harness.actions.ran.isEmpty)
    }

    @Test("clicking a pane's ping focuses the pane's tab, then brings [herdr] terminal forward")
    func focusPaneThenTerminal() async throws {
        let harness = try await Harness.started(config: shopInGhostty, graphQL: onePullRequest)
        harness.herdr.open(tab: "w1:t1", panes: ["w1:p1", "w1:p3"])
        let id = try await harness.send("Waiting for you", "--herdr", pane: "w1:p3")

        try await harness.click("Waiting for you")

        #expect(harness.herdr.runs == [["pane", "get", "w1:p3"], ["tab", "focus", "w1:t1"]])
        #expect(harness.herdr.focused == ["w1:t1"])
        #expect(harness.actions.ran == [.app("Ghostty")])
        #expect(harness.pingStore.ping(id: id)?.seen == harness.clock.now)
    }

    @Test("clicking the ping's notification runs the Herdr action too")
    func fromNotification() async throws {
        let harness = try await Harness.started(config: shopInGhostty, graphQL: onePullRequest)
        harness.herdr.open(tab: "w1:t2")
        try await harness.send("Tab", "--herdr", "w1:t2")
        let notification = try #require(harness.notifier.posted.first { $0.event == .pingSent })

        await harness.shipyard.openNotification(notification.itemURL).value

        #expect(harness.herdr.focused == ["w1:t2"])
        #expect(harness.actions.ran == [.app("Ghostty")])
        #expect(try harness.pingRow("Tab").needsAttention == false)
    }

    @Test("a [herdr] terminal edit applies to the next click, without a restart")
    func terminalEditAppliesLive() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.herdr.open(tab: "w1:t2")
        try await harness.send("Tab", "--herdr", "w1:t2")
        try await harness.click("Tab")
        #expect(harness.actions.ran.isEmpty)

        try harness.writeConfig("[herdr]\nterminal = \"com.mitchellh.ghostty\"\n\n" + shop)
        harness.graphQL([onePullRequest])
        _ = await harness.shipyard.reloadConfiguration()
        try await harness.click("Tab")

        #expect(harness.herdr.focused == ["w1:t2", "w1:t2"])
        #expect(harness.actions.ran == [.app("com.mitchellh.ghostty")])
    }

    // MARK: A failed action

    /// What's wrong on the Herdr side when a ping's action runs.
    enum Breakage: CaseIterable, Sendable {
        case paneGone, tabGone, notInstalled, notRunning

        /// The ping's `--herdr` id.
        var target: String {
            switch self {
            case .paneGone: "w1:p9"
            case .tabGone: "w1:t9"
            case .notInstalled: "w1:t1"
            case .notRunning: "w1:p1"
            }
        }

        /// The reason the row shows, short enough for its meta column.
        var reason: String {
            switch self {
            case .paneGone: "Pane gone"
            case .tabGone: "Tab gone"
            case .notInstalled: "No herdr"
            case .notRunning: "Herdr off"
            }
        }

        /// The reason the hover card shows, whole.
        var detail: String {
            switch self {
            case .paneGone: "Herdr pane w1:p9 is gone"
            case .tabGone: "Herdr tab w1:t9 is gone"
            case .notInstalled: "Couldn't find herdr"
            case .notRunning: "Herdr isn't running"
            }
        }

        func apply(to herdr: FakeHerdr) {
            herdr.open(tab: "w1:t1", panes: ["w1:p1"])
            switch self {
            case .paneGone, .tabGone: break
            case .notInstalled: herdr.installed = false
            case .notRunning: herdr.running = false
            }
        }
    }

    @Test(
        "a gone pane or tab, a missing herdr or a Herdr not running fails the action: the ping stays unseen, a short reason on its row and the whole one on its card, and the terminal stays put",
        arguments: Breakage.allCases
    )
    func failure(_ breakage: Breakage) async throws {
        let harness = try await Harness.started(config: shopInGhostty, graphQL: onePullRequest)
        breakage.apply(to: harness.herdr)
        let id = try await harness.send("Waiting", "--herdr", breakage.target)

        try await harness.click("Waiting")

        let row = try harness.pingRow("Waiting")
        #expect(row.needsAttention)
        #expect(row.actionError == breakage.reason)
        #expect(PanelText.rowDetail(row, showingRepository: false) == breakage.reason)
        #expect(PanelText.rowCard(row, now: harness.clock.now).lines.last == breakage.detail)
        #expect(harness.pingStore.ping(id: id)?.seen == nil)
        #expect(harness.actions.ran.isEmpty)
        #expect(harness.shipyard.menu.attention.pings == 1)
    }

    @Test("a pane that has closed since leaves its tab alone")
    func paneClosed() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.herdr.open(tab: "w1:t1", panes: ["w1:p1"])
        try await harness.send("Waiting", "--herdr", "w1:p2")
        try await harness.click("Waiting")
        #expect(harness.herdr.runs == [["pane", "get", "w1:p2"]])
        #expect(harness.herdr.focused.isEmpty)
    }

    @Test("a terminal that won't come forward fails the action too, after the tab was focused")
    func terminalFails() async throws {
        let harness = try await Harness.started(config: shopInGhostty, graphQL: onePullRequest)
        harness.herdr.open(tab: "w1:t2")
        try await harness.send("Tab", "--herdr", "w1:t2")
        harness.actions.failure = "No app named Ghostty"

        try await harness.click("Tab")

        #expect(harness.herdr.focused == ["w1:t2"])
        #expect(try harness.pingRow("Tab").actionError == "No app named Ghostty")
        #expect(try harness.pingRow("Tab").needsAttention)
    }

    // MARK: The row and the record

    @Test("a Herdr ping's row shows the terminal icon; its card says what it focuses")
    func row() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try await harness.send("Waiting", "--herdr", pane: "w1:p3")
        let row = try harness.pingRow("Waiting")
        #expect(row.pingIcon == .terminal)
        #expect(PanelText.stateLabel(row) == "ping, focuses a Herdr tab")
        #expect(PanelText.rowCard(row, now: harness.clock.now).lines == ["Focuses w1:p3 in Herdr"])
    }

    @Test("a Herdr action reads back from the store as it was written")
    func storedAction() throws {
        let store = PingStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-pings-\(UUID().uuidString)", isDirectory: true))
        let ping = Ping(id: "cccccc", title: "Herdr", projects: ["shop"], sent: Harness.now, action: .herdr("w1:p3"))
        try store.save(ping)
        #expect(store.all() == [ping])
    }

    // MARK: Finding herdr

    @Test("herdr is looked for where its installer and Homebrew put it, then on PATH")
    func locate() {
        let home = URL(fileURLWithPath: "/Users/me")
        func found(_ installed: Set<String>, path: String?) -> String? {
            HerdrFocus(home: home, pathEnvironment: path, isExecutable: { installed.contains($0) }, runner: FakeHerdr()).locate()
        }
        #expect(found(["/Users/me/.local/bin/herdr", "/opt/homebrew/bin/herdr"], path: nil) == "/Users/me/.local/bin/herdr")
        #expect(found(["/opt/homebrew/bin/herdr", "/custom/herdr"], path: "/custom") == "/opt/homebrew/bin/herdr")
        #expect(found(["/custom/bin/herdr"], path: "/usr/bin:/custom/bin/") == "/custom/bin/herdr")
        #expect(found([], path: "/usr/bin") == nil)
    }

    @Test("a herdr that doesn't answer in time is stopped, and the action fails")
    func herdrHangs() async {
        let shell = HangingShell()
        let focus = HerdrFocus(
            home: URL(fileURLWithPath: "/nonexistent-home"),
            pathEnvironment: nil,
            isExecutable: { $0 == FakeHerdr.path },
            runner: shell,
            timeout: 0.01
        )

        #expect(await focus.focus("w1:t2") == .failed("No answer", detail: "Herdr didn't answer"))
        #expect(shell.started == 1)
        #expect(shell.cancelled == 1)
    }

    @Test("an id ending in a tab number is a tab's; any other is a pane's")
    func tabOrPane() {
        #expect(HerdrFocus.isTab("w1:t2"))
        #expect(HerdrFocus.isTab("wD:t10"))
        #expect(!HerdrFocus.isTab("w1:p2"))
        #expect(!HerdrFocus.isTab("pane"))
    }
}
