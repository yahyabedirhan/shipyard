import Foundation
@testable import ShipyardPings
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shop = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private typealias PR = PullRequestsResponse.PullRequest

/// One open pull request in `yahyabedirhan/shop`, by `yabepa`.
private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PR(1)]).answer

private let artifact = URL(string: "https://claude.ai/artifact/42")!

@MainActor
private extension Harness {
    /// Sends a ping to `shop` through the CLI with `flags` and returns its id,
    /// then lets the app see the store change.
    @discardableResult
    func send(_ title: String, _ flags: String...) async throws -> String {
        let result = cli(["ping", title, "--project", "shop"] + flags)
        try #require(result.status == 0, "\(result.error)")
        await shipyard.reloadPings()
        return result.pingID
    }

    /// The ping row titled `title` in `shop`.
    func pingRow(_ title: String) throws -> MenuRow {
        try #require(section("shop")?.rows.first { $0.kind == .ping && $0.title == title })
    }
}

/// `--open`, `--app`, `--body` and `--from` through the CLI, and what
/// clicking the ping (its row or its notification) then does: end to end
/// across the ping command, the store, `Shipyard` and the action port.
@Suite("A ping's action")
@MainActor
struct PingActionTests {
    // MARK: The command

    @Test("--open, --app, --body and --from are stored with the ping")
    func flagsAreStored() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)

        let link = try await harness.send("Published", "--open", artifact.absoluteString, "--body", "The design doc", "--from", "claude")
        let app = try await harness.send("Needs you", "--app", "Claude")
        let note = try await harness.send("Done")

        let linked = try #require(harness.pingStore.ping(id: link))
        #expect(linked.action == .url(artifact))
        #expect(linked.body == "The design doc")
        #expect(linked.sender == "claude")
        #expect(harness.pingStore.ping(id: app)?.action == .app("Claude"))
        #expect(harness.pingStore.ping(id: note)?.action == nil)
        #expect(harness.pingStore.ping(id: note)?.body == nil)
        #expect(harness.pingStore.ping(id: note)?.sender == nil)
    }

    @Test("an app's deep link is a URL too")
    func deepLink() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try await harness.send("Open the thread", "--open", "slack://channel?id=C1")
        #expect(harness.pingStore.ping(id: id)?.action == .url(URL(string: "slack://channel?id=C1")!))
    }

    @Test("an empty --body or --from is none")
    func emptyTexts() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try await harness.send("Done", "--body", " ", "--from", "")
        #expect(harness.pingStore.ping(id: id)?.body == nil)
        #expect(harness.pingStore.ping(id: id)?.sender == nil)
    }

    @Test(
        "more than one action flag, a URL without a scheme or an empty app is a usage error, and nothing is stored",
        arguments: [
            (["--open", "https://example.com", "--app", "Claude"], "shipyard ping: a ping has one action at most; pass one of --open, --app, --herdr"),
            (["--app", "Claude", "--open", "https://example.com"], "shipyard ping: a ping has one action at most; pass one of --open, --app, --herdr"),
            (["--open", "https://a.example", "--open", "https://b.example"], "shipyard ping: a ping has one action at most; pass one of --open, --app, --herdr"),
            (["--open", "example.com"], "shipyard ping: `--open` takes a URL with its scheme, such as https://example.com, not `example.com`"),
            (["--app", " "], "shipyard ping: `--app` takes an app's bundle id or name"),
            (["--open"], "shipyard ping: `--open` needs a value"),
            (["--body"], "shipyard ping: `--body` needs a value"),
        ]
    )
    func actionUsageErrors(flags: [String], message: String) throws {
        let harness = try Harness(config: shop)
        let result = harness.cli(["ping", "Ready", "--project", "shop"] + flags)
        #expect(result.status == 2)
        #expect(result.error == message + "\n")
        #expect(harness.pingStore.all().isEmpty)
    }

    // MARK: Clicking

    @Test("clicking a ping's row runs its action and marks it seen; nothing opens on GitHub")
    func rowClickRunsAction() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let link = try await harness.send("Published", "--open", artifact.absoluteString)
        let app = try await harness.send("Needs you", "--app", "com.anthropic.claudefordesktop")

        await harness.shipyard.open(try harness.pingRow("Published")).value
        await harness.shipyard.open(try harness.pingRow("Needs you")).value

        #expect(harness.actions.ran == [.url(artifact), .app("com.anthropic.claudefordesktop")])
        #expect(harness.actions.opened.isEmpty)
        #expect(harness.pingStore.ping(id: link)?.seen == harness.clock.now)
        #expect(harness.pingStore.ping(id: app)?.seen == harness.clock.now)
        #expect(try harness.pingRow("Published").needsAttention == false)
        #expect(harness.shipyard.menu.attention.pings == 0)
    }

    @Test("clicking a ping's notification runs its action and marks it seen")
    func notificationClickRunsAction() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try await harness.send("Published", "--open", artifact.absoluteString)
        let notification = try #require(harness.pingNotifications.first)

        await harness.shipyard.openNotification(notification.itemURL).value

        #expect(harness.actions.ran == [.url(artifact)])
        #expect(harness.actions.opened.isEmpty)
        #expect(harness.pingStore.ping(id: id)?.seen == harness.clock.now)
        #expect(harness.shipyard.menu.attention.pings == 0)
    }

    @Test("⌥-click marks a ping seen without running its action")
    func optionClick() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try await harness.send("Published", "--open", artifact.absoluteString)

        harness.shipyard.markSeen(try harness.pingRow("Published"))

        #expect(harness.actions.ran.isEmpty)
        #expect(try harness.pingRow("Published").needsAttention == false)
    }

    // MARK: A failed action

    @Test("a failed action keeps the ping unseen and shows its reason on the row, until a click that works")
    func failureShowsUntilNextClick() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try await harness.send("Needs you", "--app", "Claude", "--from", "claude")
        harness.actions.failure = "No app named Claude"

        await harness.shipyard.open(try harness.pingRow("Needs you")).value

        var row = try harness.pingRow("Needs you")
        #expect(row.needsAttention)
        #expect(row.actionError == "No app named Claude")
        #expect(PanelText.rowDetail(row, showingRepository: false) == "#1 · No app named Claude")
        #expect(PanelText.rowCard(row, now: harness.clock.now).lines.contains("No app named Claude"))
        #expect(harness.pingStore.ping(id: id)?.seen == nil)
        #expect(harness.shipyard.menu.attention.pings == 1)

        harness.actions.failure = nil
        await harness.shipyard.open(row).value

        row = try harness.pingRow("Needs you")
        #expect(row.actionError == nil)
        #expect(row.needsAttention == false)
        #expect(PanelText.rowDetail(row, showingRepository: false) == "#1 · claude")
        #expect(harness.actions.ran == [.app("Claude"), .app("Claude")])
    }

    @Test("a failed action from the notification shows on the row too")
    func failureFromNotification() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try await harness.send("Published", "--open", artifact.absoluteString)
        harness.actions.failure = "Couldn't open the link"

        await harness.shipyard.openNotification(try #require(harness.pingNotifications.first).itemURL).value

        #expect(try harness.pingRow("Published").actionError == "Couldn't open the link")
        #expect(try harness.pingRow("Published").needsAttention)
    }

    @Test("⌥-click or Mark all seen clears a failure, and marks the ping seen")
    func optionClickClearsFailure() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try await harness.send("First", "--app", "Claude")
        try await harness.send("Second", "--app", "Claude")
        harness.actions.failure = "No app named Claude"
        await harness.shipyard.open(try harness.pingRow("First")).value
        await harness.shipyard.open(try harness.pingRow("Second")).value

        harness.shipyard.markSeen(try harness.pingRow("First"))
        #expect(try harness.pingRow("First").actionError == nil)
        #expect(try harness.pingRow("First").needsAttention == false)
        #expect(try harness.pingRow("Second").actionError == "No app named Claude")

        harness.shipyard.markAllSeen()
        #expect(try harness.pingRow("Second").actionError == nil)
        #expect(try harness.pingRow("Second").needsAttention == false)
        #expect(harness.actions.ran.count == 2)
    }

    @Test("a failure on a ping already seen leaves it seen, with the reason on its row")
    func failureOnSeenPing() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try await harness.send("Published", "--open", artifact.absoluteString)
        await harness.shipyard.open(try harness.pingRow("Published")).value
        let seen = try #require(harness.pingStore.ping(id: id)?.seen)
        harness.clock.advance(by: 60)
        harness.actions.failure = "Couldn't open the link"

        await harness.shipyard.open(try harness.pingRow("Published")).value

        #expect(harness.pingStore.ping(id: id)?.seen == seen)
        #expect(try harness.pingRow("Published").actionError == "Couldn't open the link")
        #expect(try harness.pingRow("Published").needsAttention == false)
    }

    // MARK: The row

    @Test("a ping's row shows an icon for its action, its sender and its body; its card the body whole and where it goes")
    func row() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try await harness.send("Published", "--open", artifact.absoluteString, "--from", "claude", "--body", "The design doc,\nready to read")
        try await harness.send("Needs you", "--app", "Claude", "--body", "Waiting for input")
        try await harness.send("Done")

        let link = try harness.pingRow("Published")
        #expect(link.pingIcon == .link)
        #expect(link.sender == "claude")
        #expect(link.agent == .claude)
        #expect(PanelText.rowCard(link, now: harness.clock.now).agent == .claude)
        #expect(PanelText.rowDetail(link, showingRepository: false) == "#1 · claude · The design doc, ready to read")
        #expect(PanelText.stateLabel(link) == "ping, opens a link")
        #expect(PanelText.rowCard(link, now: harness.clock.now).lines == [
            "The design doc,\nready to read",
            "Opens \(artifact.absoluteString)",
        ])

        let app = try harness.pingRow("Needs you")
        #expect(app.pingIcon == .app)
        #expect(PanelText.rowDetail(app, showingRepository: false) == "#2 · Waiting for input")
        #expect(PanelText.stateLabel(app) == "ping, opens an app")
        #expect(PanelText.rowCard(app, now: harness.clock.now).lines == ["Waiting for input", "Opens Claude"])

        let note = try harness.pingRow("Done")
        #expect(note.pingIcon == .noAction)
        #expect(note.agent == nil)
        #expect(PanelText.rowCard(note, now: harness.clock.now).agent == nil)
        #expect(PanelText.rowDetail(note, showingRepository: false) == "#3 · ping")
        #expect(PanelText.stateLabel(note) == "ping, click marks it seen")
        #expect(PanelText.rowCard(note, now: harness.clock.now).lines == ["Nothing to open: clicking marks it seen"])
    }

    @Test("a pull request's row has no ping icon")
    func otherRows() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let row = try #require(harness.section("shop")?.rows.first { $0.kind == .pullRequest })
        #expect(row.pingIcon == nil)
        #expect(row.sender == nil)
        #expect(row.agent == nil)
        #expect(PanelText.rowCard(row, now: harness.clock.now).agent == nil)
        #expect(row.actionError == nil)
    }

    @Test(
        "a ping's sender names a known agent, ignoring case, spaces and dashes, and leading words after the agent's name, and is shown in kebab-case",
        arguments: [
            ("claude", KnownAgent.claude, "claude"), ("Claude Code", .claude, "claude-code"), ("claude-code", .claude, "claude-code"),
            ("CLAUDE", .claude, "claude"), ("claude: fix totals", .claude, "claude-fix-totals"), ("codex", .codex, "codex"),
            ("Codex CLI", .codex, "codex-cli"), ("opencode", .opencode, "opencode"), ("OpenCode", .opencode, "opencode"),
            ("cursor", .cursor, "cursor"), ("cursor-agent", .cursor, "cursor-agent"), ("pi", .pi, "pi"), ("gemini", .gemini, "gemini"),
            ("gemini-cli", .gemini, "gemini-cli"), ("copilot", .copilot, "copilot"), ("GitHub Copilot", .copilot, "github-copilot"),
            ("amp", .amp, "amp"), ("droid", .droid, "droid"), ("Factory Droid", .droid, "factory-droid"),
        ] as [(String, KnownAgent?, String)]
    )
    func knownAgent(sender: String, agent: KnownAgent?, shown: String) async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try await harness.send("Ready", "--from", sender)
        let row = try harness.pingRow("Ready")
        #expect(row.agent == agent)
        #expect(PanelText.rowDetail(row, showingRepository: false) == "#1 · \(shown)")
    }

    @Test("a sender that only starts like an agent's name, or names no agent, is none, and is named in words", arguments: ["pipeline", "claudette", "deploy bot", "my claude"])
    func unknownSender(sender: String) async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try await harness.send("Ready", "--from", sender)
        let row = try harness.pingRow("Ready")
        #expect(row.agent == nil)
        #expect(PanelText.rowCard(row, now: harness.clock.now).agent == nil)
        #expect(PanelText.rowDetail(row, showingRepository: false) == "#1 · \(sender.replacingOccurrences(of: " ", with: "-"))")
    }

    // MARK: Grouping

    @Test("group-by = \"author\" groups pings by sender, after the authors; pings without one sit in a Pings group, last")
    func groupedBySender() async throws {
        let harness = try await Harness.started(config: "[defaults]\ngroup-by = \"author\"\n" + shop, graphQL: onePullRequest)
        try await harness.send("Review ready", "--from", "codex")
        try await harness.send("Published", "--from", "claude")
        try await harness.send("Waiting", "--from", "claude")
        try await harness.send("Done")

        let groups = try #require(harness.section("shop")?.groups)
        #expect(groups.map(\.title) == ["@yabepa", "claude", "codex", "Pings"])
        #expect(Set(groups[1].rows.map(\.title)) == ["Published", "Waiting"])
        #expect(groups[2].rows.map(\.title) == ["Review ready"])
        #expect(groups[3].rows.map(\.title) == ["Done"])
        #expect(PanelText.groupHeader(groups[1]) == "claude")
    }

    @Test("a sender's group is remembered by its own key")
    func senderKey() {
        #expect(GroupKey.sender("claude").text == "sender:claude")
        #expect(GroupKey(text: "sender:claude") == .sender("claude"))
        #expect(GroupKey(text: "sender:") == nil)
    }
}
