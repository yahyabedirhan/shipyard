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

    """

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

/// A ping store in a fresh temporary directory.
private func temporaryStore() -> PingStore {
    PingStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("shipyard-pings-\(UUID().uuidString)", isDirectory: true))
}

/// A ping as the CLI first writes it.
private func sent(_ id: String = "input", title: String = "Waiting for your input", instance: String = "first") -> Ping {
    Ping(id: id, title: title, projects: ["shop"], sent: Harness.now, action: .app("Claude"), instance: instance)
}

/// `ping` replaced as the CLI does with `--id`: new content, the same sent
/// time and instance, unseen with no failure.
private func replaced(_ ping: Ping, title: String) -> Ping {
    Ping(id: ping.id, title: title, projects: ping.projects, sent: ping.sent, instance: ping.instance)
}

@MainActor
private extension Harness {
    /// The ping rows of `shop`.
    var pingRows: [MenuRow] { section("shop")?.rows.filter { $0.kind == .ping } ?? [] }

    /// The pings' notifications posted so far.
    var pingNotifications: [PostedNotification] { notifier.posted.filter { $0.event == .pingSent } }
}

/// The CLI and the app write the same ping store at once. The app reads a
/// ping, then writes back what the user did to it (seen, a failure, its
/// removal once its window has passed); a withdraw or a replace landing in
/// between must win, never be undone.
@Suite("Pings written by the CLI and the app at once")
@MainActor
struct PingRaceTests {
    // MARK: The store

    @Test("marking seen a ping withdrawn meanwhile doesn't bring it back")
    func seenAfterWithdraw() throws {
        let store = temporaryStore()
        try store.save(sent())
        let read = try #require(store.ping(id: "input"))

        try store.remove(id: "input")
        try store.markSeen(read, at: Harness.now)

        #expect(store.ping(id: "input") == nil)
    }

    @Test("marking seen a ping replaced meanwhile leaves the replacement unseen")
    func seenAfterReplace() throws {
        let store = temporaryStore()
        try store.save(sent())
        let read = try #require(store.ping(id: "input"))

        try store.save(replaced(read, title: "Still waiting"))
        try store.markSeen(read, at: Harness.now)

        let stored = try #require(store.ping(id: "input"))
        #expect(stored.title == "Still waiting")
        #expect(stored.seen == nil)
    }

    @Test("marking seen a ping withdrawn and sent anew under its id leaves the new one unseen")
    func seenAfterSentAnew() throws {
        let store = temporaryStore()
        try store.save(sent())
        let read = try #require(store.ping(id: "input"))

        try store.remove(id: "input")
        try store.save(sent(instance: "second"))
        try store.markSeen(read, at: Harness.now)

        #expect(store.ping(id: "input")?.seen == nil)
        #expect(store.ping(id: "input")?.instance == "second")
    }

    @Test("a failure recorded for a ping replaced or withdrawn meanwhile isn't written")
    func failureAfterReplaceOrWithdraw() throws {
        let store = temporaryStore()
        try store.save(sent())
        let read = try #require(store.ping(id: "input"))

        try store.save(replaced(read, title: "Still waiting"))
        try store.recordFailure(read, reason: "No app named Claude")
        #expect(store.ping(id: "input")?.failure == nil)

        try store.remove(id: "input")
        try store.recordFailure(read, reason: "No app named Claude")
        #expect(store.ping(id: "input") == nil)
    }

    @Test("the same sending, seen or failed since, is still marked seen and gets its failure")
    func sameSending() throws {
        let store = temporaryStore()
        try store.save(sent())
        let read = try #require(store.ping(id: "input"))

        try store.recordFailure(read, reason: "No app named Claude")
        #expect(store.ping(id: "input")?.failure == "No app named Claude")
        try store.markSeen(read, at: Harness.now)
        #expect(store.ping(id: "input")?.seen == Harness.now)
        #expect(store.ping(id: "input")?.failure == nil)
    }

    @Test("a ping past its window is removed only as it was read: replaced or seen again since, it stays")
    func removeIfUnchanged() throws {
        let store = temporaryStore()
        var seen = sent()
        seen.seen = Harness.now
        try store.save(seen)

        // Replaced meanwhile: unseen again.
        try store.save(replaced(seen, title: "Still waiting"))
        #expect(try store.removeIfUnchanged(seen) == false)
        #expect(store.ping(id: "input")?.title == "Still waiting")

        // Replaced and seen again, later: `seen` changed.
        var seenAgain = replaced(seen, title: "Waiting for your input")
        seenAgain.seen = Harness.now.addingTimeInterval(3600)
        try store.save(seenAgain)
        #expect(try store.removeIfUnchanged(seen) == false)
        #expect(store.ping(id: "input") != nil)

        // As it was read: removed.
        #expect(try store.removeIfUnchanged(seenAgain))
        #expect(store.ping(id: "input") == nil)
    }

    // MARK: Numbers

    @Test("pings sent at once each take a number of their own")
    func numbersSentAtOnce() throws {
        let harness = try Harness(config: shop)
        let (configURL, repositories, store) = (harness.configURL, harness.repositoriesStore, harness.pingStore)
        let environment = CommandEnvironment(workingDirectory: harness.workingFolder, variables: [:], git: FakeGitRemote(), platform: .macOS)
        let now = harness.clock.now
        let count = 24

        DispatchQueue.concurrentPerform(iterations: count) { index in
            _ = ShipyardCLI.run(
                ["ping", "Ready", "--project", "shop", "--id", "agent-\(index)"],
                environment: environment,
                configURL: configURL,
                repositories: repositories,
                pingStore: store,
                now: now
            )
        }

        #expect(store.all().compactMap(\.number).sorted() == Array(1...count))
    }

    // MARK: A click whose action is still running

    @Test("a ping replaced while its action runs stays unseen, as the replacement")
    func replacedWhileRunning() async throws {
        let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
        harness.cli("ping", "Waiting for your input", "--project", "shop", "--id", "input", "--app", "Claude")
        await harness.shipyard.reloadPings()
        let store = harness.pingStore
        harness.actions.whileRunning = {
            guard let ping = store.ping(id: "input") else { return }
            try? store.save(replaced(ping, title: "Still waiting"))
        }

        await harness.shipyard.open(try #require(harness.pingRows.first)).value

        let stored = try #require(harness.pingStore.ping(id: "input"))
        #expect(stored.title == "Still waiting")
        #expect(stored.seen == nil)
        #expect(harness.pingRows.first?.needsAttention == true)
    }

    @Test("a ping withdrawn while its action runs stays gone, whether the action works or fails")
    func withdrawnWhileRunning() async throws {
        for failure in [nil, "No app named Claude"] {
            let harness = try await Harness.started(config: shop, graphQL: onePullRequest)
            harness.cli("ping", "Waiting for your input", "--project", "shop", "--id", "input", "--app", "Claude")
            await harness.shipyard.reloadPings()
            let store = harness.pingStore
            harness.actions.failure = failure
            harness.actions.whileRunning = { try? store.remove(id: "input") }

            await harness.shipyard.open(try #require(harness.pingRows.first)).value

            #expect(harness.pingStore.ping(id: "input") == nil)
            #expect(harness.pingStore.all().isEmpty)
            #expect(harness.pingRows.isEmpty)
        }
    }

    // MARK: Signed out

    @Test("a ping sent while the app was closed notifies at start, signed out and without GitHub")
    func notifiesAtStartSignedOut() async throws {
        let harness = try Harness(config: shop)
        harness.cli("ping", "Published", "--project", "shop")

        await harness.shipyard.start()

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.pingNotifications.map(\.title) == ["shop · Published"])
        #expect(harness.graphQLRequests.isEmpty)

        await harness.shipyard.reloadPings()
        await harness.shipyard.refresh()
        #expect(harness.pingNotifications.count == 1)
    }

    @Test("signed out, a seen ping past its window leaves on a refresh, and its banner with it")
    func expiresSignedOut() async throws {
        let harness = try Harness(config: shop)
        await harness.shipyard.start()
        harness.cli("ping", "Ready", "--project", "shop", "--id", "ready")
        await harness.shipyard.reloadPings()
        let banner = try #require(harness.pingNotifications.first)
        try harness.pingStore.markSeen(try #require(harness.pingStore.ping(id: "ready")), at: harness.clock.now)
        await harness.shipyard.reloadPings()

        harness.clock.advance(by: 24 * 3600)
        await harness.shipyard.refresh()

        #expect(harness.shipyard.phase == .signedOut)
        #expect(harness.pingStore.ping(id: "ready") == nil)
        #expect(harness.notifier.removed == [banner.id])
        #expect(harness.shipyard.pings.isEmpty)
    }
}
