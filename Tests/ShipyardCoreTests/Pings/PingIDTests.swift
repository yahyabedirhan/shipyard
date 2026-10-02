import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shopAndBlog = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    [[projects]]
    name = "blog"
    repositories = ["yahyabedirhan/blog"]

    """

private typealias PR = PullRequestsResponse.PullRequest

/// One open pull request in `yahyabedirhan/shop`, none in the blog.
private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PR(1)]).answer

@MainActor
private extension Harness {
    /// Runs `shipyard ping` with `arguments`, requires it to work, lets the
    /// app see the store change, and returns the id it printed.
    @discardableResult
    func send(_ arguments: String...) async throws -> String {
        let result = cli(["ping"] + arguments)
        try #require(result.status == 0, "\(result.error)")
        await shipyard.reloadPings()
        return result.output.trimmingCharacters(in: .newlines)
    }

    /// Runs `shipyard ping withdraw id`, requires it to work, and lets the
    /// app see the store change.
    func withdraw(_ id: String) async throws {
        let result = cli("ping", "withdraw", id)
        try #require(result == CommandResult(output: id + "\n"), "\(result.error)")
        await shipyard.reloadPings()
    }

    /// The ping rows in `project`.
    func pingRows(_ project: String = "shop") -> [MenuRow] {
        section(project)?.rows.filter { $0.kind == .ping } ?? []
    }

    /// The pings' notifications posted so far.
    var pingNotifications: [PostedNotification] { notifier.posted.filter { $0.event == .pingSent } }

    /// Refreshes with GitHub answering `onePullRequest` again.
    func refreshAgain() async {
        graphQL([onePullRequest])
        await shipyard.refresh()
    }
}

/// Ids are global: one names one ping wherever it's filed. Sending an id
/// again replaces that ping without a second notification; withdrawing it
/// removes the ping and its notification. End to end from the CLI through
/// the store to the menu and the recording notifier.
@Suite("A ping's id")
@MainActor
struct PingIDTests {
    // MARK: --id

    @Test("--id names the ping, and the id is printed")
    func namedID() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)

        let id = try await harness.send("Waiting for your input", "--project", "shop", "--id", "checkout-input_2")

        #expect(id == "checkout-input_2")
        #expect(harness.pingStore.ping(id: id)?.title == "Waiting for your input")
        #expect(harness.pingRows().first?.url == Ping.url(id: id))
    }

    @Test("an id that isn't 1 to 64 lowercase letters, digits, - and _, starting with a letter or digit, is a usage error", arguments: [
        "Checkout", "-x", "_x", "a b", "a/b", "../x", "a.b", "é", "", String(repeating: "a", count: 65),
        // A newline isn't part of an id, trailing or not.
        "build-42\n", "a\nb",
    ])
    func badID(id: String) throws {
        let harness = try Harness(config: shopAndBlog)

        let result = harness.cli("ping", "Ready", "--project", "shop", "--id", id)

        #expect(result.status == 2)
        #expect(result.error == "shipyard ping: `--id`: an id is 1 to 64 lowercase letters, digits, - and _, starting with a letter or digit, not `\(id)`\n")
        #expect(harness.pingStore.all().isEmpty)
    }

    @Test("--id without a value is a usage error; 64 characters is still an id")
    func idBounds() throws {
        let harness = try Harness(config: shopAndBlog)

        #expect(harness.cli("ping", "Ready", "--project", "shop", "--id").error == "shipyard ping: `--id` needs a value\n")
        let long = String(repeating: "a", count: 64)
        #expect(harness.cli("ping", "Ready", "--project", "shop", "--id", long) == CommandResult(output: long + "\n"))
    }

    @Test("without --id, a generated id is printed and names the ping")
    func generatedIDPrinted() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)

        let id = try await harness.send("Ready", "--project", "shop")

        #expect(PingCommand.isID(id))
        #expect(harness.pingStore.ping(id: id)?.title == "Ready")
    }

    // MARK: Replacing

    @Test("sending an id again replaces content, action and filing, keeps the sent time, and needs attention again")
    func replace() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        let sent = harness.clock.now
        try await harness.send("Waiting for your input", "--project", "shop", "--id", "input", "--body", "Which total?", "--from", "agent", "--open", "https://example.com")
        harness.shipyard.markSeen(try #require(harness.pingRows().first))
        try harness.pingStore.recordFailure(try #require(harness.pingStore.ping(id: "input")), reason: "the app isn't installed")
        #expect(harness.shipyard.menu.attention.pings == 0)

        harness.clock.advance(by: 600)
        try await harness.send("Still waiting, 10 min", "--id", "input", "--project", "blog", "--app", "Claude")

        let ping = try #require(harness.pingStore.ping(id: "input"))
        #expect(harness.pingStore.all().count == 1)
        #expect(ping.title == "Still waiting, 10 min")
        #expect(ping.body == nil)
        #expect(ping.sender == nil)
        #expect(ping.action == .app("Claude"))
        #expect(ping.projects == ["blog"])
        #expect(ping.sent == sent)
        #expect(ping.seen == nil)
        #expect(ping.failure == nil)
        #expect(harness.pingRows("shop").isEmpty)
        #expect(harness.pingRows("blog").map(\.title) == ["Still waiting, 10 min"])
        #expect(harness.pingRows("blog").first?.needsAttention == true)
        #expect(harness.shipyard.menu.attention.pings == 1)
    }

    @Test("a replace posts no second notification, removes none, and a refresh or relaunch doesn't either")
    func replaceDoesNotNotify() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Waiting for your input", "--project", "shop", "--id", "input")
        #expect(harness.pingNotifications.map(\.title) == ["shop · Waiting for your input"])

        harness.clock.advance(by: 600)
        try await harness.send("Still waiting, 10 min", "--project", "shop", "--id", "input")
        await harness.refreshAgain()

        #expect(harness.pingNotifications.count == 1)
        #expect(harness.notifier.removed.isEmpty)

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        await relaunched.shipyard.start()
        #expect(relaunched.pingNotifications.isEmpty)
        #expect(relaunched.notifier.removed.isEmpty)
    }

    // MARK: Withdrawing

    @Test("withdraw removes the ping from the menu, the store and Notification Center, and prints its id")
    func withdraw() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        let id = try await harness.send("Waiting for your input", "--project", "shop")
        try await harness.send("Deployed", "--project", "shop", "--id", "deploy")
        let banner = try #require(harness.pingNotifications.first)

        try await harness.withdraw(id)

        #expect(harness.pingRows().map(\.title) == ["Deployed"])
        #expect(harness.pingStore.ping(id: id) == nil)
        #expect(harness.notifier.removed == [banner.id])
        #expect(harness.shipyard.menu.attention.pings == 1)
    }

    @Test("withdrawing an unknown id fails with one line and exit 1, removing nothing")
    func withdrawUnknown() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Deployed", "--project", "shop", "--id", "deploy")

        let result = harness.cli("ping", "withdraw", "deplyo")

        #expect(result == CommandResult(
            error: "shipyard ping withdraw: no ping has the id `deplyo`; it may have been withdrawn, dismissed or have left already\n",
            status: 1
        ))
        #expect(harness.pingStore.ping(id: "deploy") != nil)
    }

    @Test("withdraw without one id, or with one that isn't an id, is a usage error")
    func withdrawUsage() throws {
        let harness = try Harness(config: shopAndBlog)
        let usage = "shipyard ping withdraw: give the id of one ping: shipyard ping withdraw <id>\n"

        #expect(harness.cli("ping", "withdraw") == CommandResult(error: usage, status: 2))
        #expect(harness.cli("ping", "withdraw", "a", "b") == CommandResult(error: usage, status: 2))
        #expect(harness.cli("ping", "withdraw", "build-42\n").status == 2)
        #expect(harness.cli("ping", "withdraw", "../state") == CommandResult(
            error: "shipyard ping withdraw: an id is 1 to 64 lowercase letters, digits, - and _, starting with a letter or digit, not `../state`\n",
            status: 2
        ))
    }

    @Test("withdraw works while config.toml doesn't read, since it files nothing")
    func withdrawWithBrokenConfiguration() throws {
        let harness = try Harness(config: shopAndBlog)
        try harness.pingStore.save(Ping(id: "deploy", title: "Deployed", projects: ["shop"], sent: harness.clock.now))
        try harness.writeConfig("[[projects]\n")

        #expect(harness.cli("ping", "withdraw", "deploy") == CommandResult(output: "deploy\n"))
        #expect(harness.pingStore.all().isEmpty)
    }

    @Test("a withdrawn id sent again is a new ping: it notifies again")
    func withdrawnThenSentAgain() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Waiting for your input", "--project", "shop", "--id", "input")
        try await harness.withdraw("input")

        harness.clock.advance(by: 60)
        try await harness.send("Waiting again", "--project", "shop", "--id", "input")

        #expect(harness.pingNotifications.map(\.title) == ["shop · Waiting for your input", "shop · Waiting again"])
        #expect(harness.pingStore.ping(id: "input")?.sent == harness.clock.now)
    }

    @Test("withdrawn and sent again in the same second, before the app looks, it's still a new ping: the old banner goes, a new one comes")
    func withdrawnAndSentAgainUnseen() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Waiting for your input", "--project", "shop", "--id", "input")
        let first = try #require(harness.pingNotifications.first)

        #expect(harness.cli("ping", "withdraw", "input").status == 0)
        try await harness.send("Waiting again", "--project", "shop", "--id", "input")

        #expect(harness.notifier.removed == [first.id])
        #expect(harness.pingNotifications.map(\.title) == ["shop · Waiting for your input", "shop · Waiting again"])
    }

    @Test("a ping withdrawn while the app wasn't running loses its banner at the next start")
    func withdrawnWhileQuit() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Waiting for your input", "--project", "shop", "--id", "input")
        let banner = try #require(harness.pingNotifications.first)

        #expect(harness.cli("ping", "withdraw", "input").status == 0)
        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        await relaunched.shipyard.start()

        #expect(relaunched.notifier.removed == [banner.id])
        #expect(relaunched.pingRows().isEmpty)
    }

    @Test("withdrawn and sent again while the app wasn't running, it's a new ping at the next start")
    func withdrawnAndSentAgainWhileQuit() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Waiting for your input", "--project", "shop", "--id", "input")
        let first = try #require(harness.pingNotifications.first)

        #expect(harness.cli("ping", "withdraw", "input").status == 0)
        #expect(harness.cli("ping", "Waiting again", "--project", "shop", "--id", "input").status == 0)
        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        await relaunched.shipyard.start()

        #expect(relaunched.notifier.removed == [first.id])
        #expect(relaunched.pingNotifications.map(\.title) == ["shop · Waiting again"])
    }

    // MARK: Dismissing and leaving

    @Test("dismissing a ping removes its banner, and its id sent again notifies again")
    func dismissRemovesBanner() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Waiting for your input", "--project", "shop", "--id", "input")
        let banner = try #require(harness.pingNotifications.first)

        await harness.shipyard.dismiss(try #require(harness.pingRows().first)).value

        #expect(harness.notifier.removed == [banner.id])
        harness.clock.advance(by: 60)
        try await harness.send("Waiting again", "--project", "shop", "--id", "input")
        #expect(harness.pingNotifications.count == 2)
    }

    @Test("a seen ping that leaves after its seen-window takes its banner too")
    func expiredRemovesBanner() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("Ready", "--project", "shop", "--id", "ready")
        let banner = try #require(harness.pingNotifications.first)
        harness.shipyard.markSeen(try #require(harness.pingRows().first))
        #expect(harness.notifier.removed.isEmpty)

        harness.clock.advance(by: 24 * 3600)
        await harness.refreshAgain()

        #expect(harness.pingRows().isEmpty)
        #expect(harness.notifier.removed == [banner.id])
    }

    // MARK: --

    @Test("after --, everything is the title: withdraw, or a word starting with --")
    func endOfOptions() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)

        try await harness.send("--project", "shop", "--id", "word", "--", "withdraw")
        try await harness.send("--project", "shop", "--id", "flag", "--", "--help")
        try await harness.send("--project", "shop", "--id", "dashes", "--", "--")

        #expect(harness.pingStore.ping(id: "word")?.title == "withdraw")
        #expect(harness.pingStore.ping(id: "flag")?.title == "--help")
        // Only the first -- ends the flags; a second is the title.
        #expect(harness.pingStore.ping(id: "dashes")?.title == "--")
    }

    @Test("a title after -- still needs to be the only one")
    func endOfOptionsOneTitle() throws {
        let harness = try Harness(config: shopAndBlog)

        let result = harness.cli("ping", "--project", "shop", "--", "--", "--id")

        #expect(result.status == 2)
        #expect(result.error == "shipyard ping: one title only; quote it: shipyard ping \"-- --id\"\n")
    }

    @Test("the help shows --id, withdraw and --")
    func help() throws {
        let harness = try Harness(config: shopAndBlog)

        let ping = harness.cli("ping", "--help").output
        #expect(ping.contains("[--id <id>]"))
        #expect(ping.contains("shipyard ping withdraw <id>"))
        #expect(ping.contains("shipyard ping -- withdraw"))
        #expect(harness.cli("--help").output.contains("shipyard ping withdraw <id>"))
    }
}
