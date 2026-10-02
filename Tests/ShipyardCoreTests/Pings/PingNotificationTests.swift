import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shop = """
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
    /// Sends a ping through the CLI and returns its id.
    @discardableResult
    func ping(_ title: String, project: String = "shop") throws -> String {
        let result = cli("ping", title, "--project", project)
        try #require(result.status == 0, "\(result.error)")
        return result.pingID
    }

    /// The ping rows of `project`.
    func pingRows(_ project: String = "shop") -> [MenuRow] {
        section(project)?.rows.filter { $0.kind == .ping } ?? []
    }

    /// The pings' notifications posted so far.
    var pingNotifications: [PostedNotification] { notifier.posted.filter { $0.event == .pingSent } }

    /// Refreshes, two minutes later, with GitHub answering as before.
    func refreshLater() async {
        graphQL([onePullRequest])
        clock.advance(by: 120)
        await shipyard.refresh()
    }
}

/// A new ping posts a notification through the notification rules, as the
/// event `ping.sent`: end to end from the CLI or the store to what the
/// recording notifier was asked to post.
@Suite("A ping's notification")
@MainActor
struct PingNotificationTests {
    @Test("ping.sent is in the default rules")
    func defaultRules() {
        #expect(Configuration().defaults.notifications.contains(NotificationRule(event: .pingSent)))
        #expect(EventKind(rawValue: "ping.sent") == .pingSent)
    }

    @Test("a new ping posts one notification, titled with its project and title, with its body and sender")
    func postsOne() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try harness.pingStore.save(Ping(
            id: "k7qm2x",
            title: "Ready for review",
            projects: ["shop"],
            sent: harness.clock.now,
            body: "The checkout fix is up as #12.",
            sender: "checkout agent"
        ))

        await harness.shipyard.reloadPings()

        let posted = harness.pingNotifications
        #expect(posted.count == 1)
        #expect(posted.first?.title == "shop · Ready for review")
        #expect(posted.first?.body == "The checkout fix is up as #12.\nfrom checkout agent")
        #expect(posted.first?.itemURL == Ping.url(id: "k7qm2x"))
    }

    @Test("a ping with no body or sender posts its title alone")
    func titleOnly() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try harness.ping("Waiting for your input")

        await harness.shipyard.reloadPings()

        #expect(harness.pingNotifications.map(\.title) == ["shop · Waiting for your input"])
        #expect(harness.pingNotifications.first?.body == "")
    }

    @Test("a ping sent while the app isn't running notifies when it starts")
    func sentBeforeStart() async throws {
        let harness = try Harness(stored: "gho_stored", config: shop)
        try harness.ping("Published")
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])

        await harness.shipyard.start()

        #expect(harness.pingNotifications.map(\.title) == ["shop · Published"])
    }

    @Test("a ping is notified at most once: not again on a refresh, another ping, a replace or a relaunch")
    func atMostOnce() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try harness.ping("Waiting for your input")
        await harness.shipyard.reloadPings()
        #expect(harness.pingNotifications.count == 1)

        await harness.refreshLater()
        try harness.ping("Another one", project: "blog")
        await harness.shipyard.reloadPings()
        #expect(harness.pingNotifications.map(\.title) == ["shop · Waiting for your input", "blog · Another one"])

        // The same id with new content (a replace) posts no second banner.
        var replaced = try #require(harness.pingStore.ping(id: id))
        replaced.title = "Still waiting, 10 min"
        try harness.pingStore.save(replaced)
        await harness.shipyard.reloadPings()
        await harness.refreshLater()
        #expect(harness.pingNotifications.count == 2)

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        await relaunched.shipyard.start()
        #expect(relaunched.pingNotifications.isEmpty)
    }

    @Test("a ping filed under two projects posts once, in the first that lists it")
    func twoProjects() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        try harness.pingStore.save(Ping(id: "k7qm2x", title: "Deployed", projects: ["blog", "shop"], sent: harness.clock.now))

        await harness.shipyard.reloadPings()

        #expect(harness.pingNotifications.map(\.title) == ["shop · Deployed"])
    }

    @Test("rules that leave out ping.sent don't notify, and a project's own rules can")
    func rulesLeaveItOut() async throws {
        let config = """
            [[defaults.notifications]]
            event = "pr.opened"

            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop"]

            [[projects]]
            name = "blog"
            repositories = ["yahyabedirhan/blog"]
            notifications = [{ event = "ping.sent" }]

            """
        let harness = try await Harness.started(config: config, graphQL: onePullRequest)
        try harness.ping("Silent")
        try harness.ping("Heard", project: "blog")

        await harness.shipyard.reloadPings()

        #expect(harness.pingNotifications.map(\.title) == ["blog · Heard"])
        // Not notified isn't the same as seen: the silent one still needs attention.
        #expect(harness.pingRows().first?.needsAttention == true)
    }

    @Test("a rule with authors never selects a ping", arguments: [#"["me"]"#, #"["others"]"#, #"["bots"]"#, #"["@yabepa"]"#])
    func authorsNeverSelect(authors: String) async throws {
        let config = """
            [[defaults.notifications]]
            event = "ping.sent"
            authors = \(authors)

            """ + shop
        let harness = try await Harness.started(config: config, graphQL: onePullRequest)
        try harness.ping("Ready for review")

        await harness.shipyard.reloadPings()

        #expect(harness.pingNotifications.isEmpty)
    }

    @Test("a ping the project doesn't list isn't notified")
    func hiddenNotNotified() async throws {
        let harness = try await Harness.started(config: "[defaults.pings]\nshow = false\n" + shop, graphQL: onePullRequest)
        try harness.ping("Hidden")

        await harness.shipyard.reloadPings()
        await harness.refreshLater()

        #expect(harness.pingNotifications.isEmpty)
    }

    @Test("clicking a ping's notification marks the ping seen and opens nothing")
    func clickMarksSeen() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        let id = try harness.ping("Ready for review")
        await harness.shipyard.reloadPings()
        let notification = try #require(harness.pingNotifications.first)

        harness.shipyard.openNotification(notification.itemURL)

        #expect(harness.actions.opened.isEmpty)
        #expect(harness.pingStore.ping(id: id)?.seen == harness.clock.now)
        #expect(harness.pingRows().first?.needsAttention == false)
        #expect(harness.shipyard.menu.attention.pings == 0)
    }

    @Test("a ping's URL gives back its id, and no other URL does")
    func idFromURL() {
        #expect(Ping.id(from: Ping.url(id: "k7qm2x")) == "k7qm2x")
        #expect(Ping.id(from: URL(string: "https://github.com/o/r/pull/1")!) == nil)
        #expect(Ping.id(from: URL(string: "shipyard://ping/")!) == nil)
    }
}
