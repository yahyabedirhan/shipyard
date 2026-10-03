import Foundation
@testable import ShipyardCommand
@testable import ShipyardPings
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

/// `shop` and `blog`, each watching its own repository and a shared one.
private let shopAndBlog = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop", "yahyabedirhan/shared"]

    [[projects]]
    name = "blog"
    repositories = ["yahyabedirhan/blog", "yahyabedirhan/shared"]

    """

/// `shop` alone.
private let shopOnly = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

/// `shop`, and one remote machine.
private let shopAndMachine = "[remote]\nmachines = [\"netcup-vps\"]\n\n" + shopOnly

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

/// A machine's `shipyard ping list --json` holding `pings`, each given as
/// (id, title, projects, minutes before the harness's now) and listed with
/// the `number` its own store gave it, which the Mac ignores; `truncated`
/// when the list stopped early.
private func listed(_ pings: [(id: String, title: String, projects: [String], minutes: Double)], truncated: Bool = false) -> String {
    let formatter = ISO8601DateFormatter()
    let entries = pings.enumerated().map { index, ping in
        let projects = ping.projects.map { "\"\($0)\"" }.joined(separator: ",")
        let sent = formatter.string(from: Harness.now.addingTimeInterval(-ping.minutes * 60))
        return #"{"id":"\#(ping.id)","instance":"i-\#(ping.id)","number":\#(index + 7),"projects":[\#(projects)],"sent":"\#(sent)","title":"\#(ping.title)"}"#
    }
    return #"{"pings":[\#(entries.joined(separator: ","))],"shipyardVersion":"0.0.6","truncated":\#(truncated),"version":1}"#
}

@MainActor
private extension Harness {
    /// Runs `shipyard ping` with `arguments`, requires it to print only the
    /// id `id`, and lets the app see the store change.
    func send(_ id: String, _ arguments: String...) async throws {
        let result = cli(["ping"] + arguments + ["--id", id])
        try #require(result == CommandResult(output: id + "\n"), "\(result.error)")
        await shipyard.reloadPings()
    }

    /// Withdraws ping `id` and lets the app see the store change.
    func withdraw(_ id: String) async throws {
        try #require(cli("ping", "withdraw", id).status == 0)
        await shipyard.reloadPings()
    }

    /// Each ping row's title and number in the section `name`, by title.
    func numbers(_ name: String) -> [String: Int] {
        Dictionary((section(name)?.rows ?? []).filter { $0.kind == .ping }.map { ($0.title, $0.number) }, uniquingKeysWith: { first, _ in first })
    }

    /// Writes a ping into the store as an older `shipyard` did: with the
    /// number its store gave it, sent `minutes` before the harness's now.
    func store(_ id: String, _ title: String, minutes: Double, number: Int) throws {
        let sent = ISO8601DateFormatter().string(from: Harness.now.addingTimeInterval(-minutes * 60))
        try FileManager.default.createDirectory(at: pingStore.directory, withIntermediateDirectories: true)
        try Data(#"{"id":"\#(id)","instance":"i-\#(id)","number":\#(number),"projects":["shop"],"sent":"\#(sent)","title":"\#(title)"}"#.utf8)
            .write(to: pingStore.directory.appendingPathComponent("\(id).json"))
    }
}

/// The Mac numbers pings, one sequence per section (a project, or a
/// machine's own section of unfiled pings), in the order it first sees
/// them, like issues in a repository. End to end across the CLI, the
/// ping store, a fake `herdr`, `Shipyard`, the app state and the menu.
@Suite("Ping numbers")
@MainActor
struct PingNumberTests {
    @Test("each project numbers its pings from 1 as they arrive; a ping filed under two projects takes each one's own number; the CLI prints only the id")
    func perProject() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)

        try await harness.send("first", "In the shop", "--project", "shop")
        try await harness.send("second", "In the blog", "--project", "blog")
        try await harness.send("third", "In the blog too", "--project", "blog")
        try await harness.send("shared", "In both", "--repo", "yahyabedirhan/shared")

        #expect(harness.numbers("shop") == ["In the shop": 1, "In both": 2])
        #expect(harness.numbers("blog") == ["In the blog": 1, "In the blog too": 2, "In both": 3])
        let row = try #require(harness.section("shop")?.rows.first { $0.title == "In both" })
        #expect(PanelText.rowDetail(row, showingRepository: false).hasPrefix("#2 · "))
        // The store keeps no number: only the Mac gives them.
        let stored = try String(contentsOf: harness.pingStore.directory.appendingPathComponent("shared.json"), encoding: .utf8)
        #expect(!stored.contains("number"))
        #expect(!FileManager.default.fileExists(atPath: harness.pingStore.directory.appendingPathComponent("last-number").path))
    }

    @Test("a replace keeps its number; a number is never given again once its ping leaves, even after a restart")
    func neverReused() async throws {
        let harness = try await Harness.started(config: shopAndBlog, graphQL: onePullRequest)
        try await harness.send("input", "Waiting for your input", "--project", "shop")
        try await harness.send("deploy", "Deployed", "--project", "shop")
        try await harness.send("input", "Still waiting", "--project", "shop")
        #expect(harness.numbers("shop") == ["Still waiting": 1, "Deployed": 2])

        try await harness.withdraw("deploy")
        try await harness.send("review", "Review it", "--project", "shop")
        #expect(harness.numbers("shop") == ["Still waiting": 1, "Review it": 3])

        // Dismissed, it leaves too.
        await harness.shipyard.dismiss(try #require(harness.section("shop")?.rows.first { $0.title == "Still waiting" })).value
        try await harness.withdraw("review")
        #expect(harness.numbers("shop").isEmpty)

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        await relaunched.shipyard.start()
        try await relaunched.send("input", "Waiting again", "--project", "shop")
        #expect(relaunched.numbers("shop") == ["Waiting again": 4])
        // Another project counts on its own.
        try await relaunched.send("post", "Posted", "--project", "blog")
        #expect(relaunched.numbers("blog") == ["Posted": 1])
    }

    @Test("pings already there when the Mac first numbers are numbered per project, oldest sent first, local and remote alike, even after a launch with the file broken; a number a machine or an older store gave is ignored")
    func firstLaunch() async throws {
        let harness = try Harness(stored: "gho_stored", config: shopAndMachine)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        try harness.store("newer", "Sent a minute ago", minutes: 1, number: 2)
        try harness.store("older", "Sent three minutes ago", minutes: 3, number: 1)
        harness.herdr.addMachine("netcup-vps")
        harness.herdr.setListOutput(listed([
            (id: "q1", title: "Sent two minutes ago", projects: ["shop"], minutes: 2),
            (id: "q2", title: "Sent five minutes ago", projects: ["shop"], minutes: 5),
            (id: "q3", title: "Unfiled", projects: [], minutes: 4),
        ]), on: "netcup-vps")

        // Launched with the file broken, the defaults stand in: they don't say which machines to wait for, so nothing is numbered.
        try harness.writeConfig("[[projects]\n")
        await harness.shipyard.start()
        try harness.writeConfig(shopAndMachine)
        await harness.shipyard.reloadConfiguration()
        // Before the machine answers, nothing is numbered yet: its pings may be older.
        #expect(harness.numbers("shop") == ["Sent a minute ago": 0, "Sent three minutes ago": 0])
        await harness.machineTimer.fire()

        #expect(harness.numbers("shop") == [
            "Sent five minutes ago": 1,
            "Sent three minutes ago": 2,
            "Sent two minutes ago": 3,
            "Sent a minute ago": 4,
        ])
        #expect(harness.numbers("netcup-vps") == ["Unfiled": 1])
    }

    @Test("a remote ping takes its number at the first poll that lists it, after the pings already numbered; a machine's own section counts on its own; one that leaves never gives its number back, and one sent again is new; one past the end of a list that stopped early keeps its number; a machine taken out of the configuration retires its pings' numbers")
    func remote() async throws {
        let harness = try Harness(stored: "gho_stored", config: shopAndMachine)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        harness.herdr.addMachine("netcup-vps")
        await harness.shipyard.start()
        await harness.machineTimer.fire()
        try await harness.send("local", "Local", "--project", "shop")

        // Sent before the local ping, but first seen after it.
        harness.herdr.setListOutput(listed([
            (id: "q1", title: "Merge it?", projects: ["shop"], minutes: 30),
            (id: "q2", title: "Deploy?", projects: [], minutes: 30),
        ]), on: "netcup-vps")
        await harness.machineTimer.fire()
        #expect(harness.numbers("shop") == ["Local": 1, "Merge it?": 2])
        #expect(harness.numbers("netcup-vps") == ["Deploy?": 1])

        // Dismissed, and withdrawn on its machine: both numbers are retired.
        await harness.shipyard.dismiss(try #require(harness.section("shop")?.rows.first { $0.title == "Merge it?" })).value
        harness.herdr.setListOutput(listed([
            (id: "q1", title: "Merge it?", projects: ["shop"], minutes: 30),
        ]), on: "netcup-vps")
        await harness.machineTimer.fire()
        // Sent again under its id, it's a new ping.
        let latest = listed([
            (id: "q1", title: "Merge it?", projects: ["shop"], minutes: 30),
            (id: "q3", title: "Ship it?", projects: ["shop"], minutes: 1),
            (id: "q2", title: "Deploy?", projects: [], minutes: 1),
        ])
        harness.herdr.setListOutput(latest, on: "netcup-vps")
        await harness.machineTimer.fire()
        #expect(harness.numbers("shop") == ["Local": 1, "Ship it?": 3])
        #expect(harness.numbers("netcup-vps") == ["Deploy?": 2])

        // After a restart, a remote ping keeps its number while its machine hasn't answered yet, and after.
        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        relaunched.herdr.addMachine("netcup-vps")
        relaunched.herdr.setListOutput(latest, on: "netcup-vps")
        await relaunched.shipyard.start()
        await relaunched.machineTimer.fire()
        #expect(relaunched.numbers("shop") == ["Local": 1, "Ship it?": 3])
        #expect(relaunched.numbers("netcup-vps") == ["Deploy?": 2])

        // The list stops early, before "Ship it?": its number waits, and shows again when the whole list comes back.
        relaunched.herdr.setListOutput(listed([
            (id: "q2", title: "Deploy?", projects: [], minutes: 1),
        ], truncated: true), on: "netcup-vps")
        await relaunched.machineTimer.fire()
        #expect(relaunched.shipyard.remote.machine("netcup-vps")?.truncated == true)
        #expect(relaunched.numbers("shop") == ["Local": 1])
        relaunched.herdr.setListOutput(latest, on: "netcup-vps")
        await relaunched.machineTimer.fire()
        #expect(relaunched.numbers("shop") == ["Local": 1, "Ship it?": 3])

        // Taken out of `[remote] machines`, the machine's pings give up their numbers: added back, they're new,
        // "Merge it?" too, since its dismissal went with the machine.
        try relaunched.writeConfig(shopOnly)
        await relaunched.shipyard.reloadConfiguration()
        #expect(relaunched.numbers("shop") == ["Local": 1])
        try relaunched.writeConfig(shopAndMachine)
        await relaunched.shipyard.reloadConfiguration()
        await relaunched.machineTimer.fire()
        #expect(relaunched.numbers("shop") == ["Local": 1, "Merge it?": 4, "Ship it?": 5])
        #expect(relaunched.numbers("netcup-vps") == ["Deploy?": 3])
    }
}
