import Foundation
@testable import ShipyardCommand
@testable import ShipyardPings
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shopAndBlog = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop", "yahyabedirhan/shared"]

    [[projects]]
    slug = "blog"
    repositories = ["yahyabedirhan/blog", "yahyabedirhan/shared"]

    """

private let shopOnly = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

private let shopAndMachine = "[remote]\nmachines = [\"beta-vps\"]\n\n" + shopOnly

private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer

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
    func send(_ id: String, _ arguments: String...) async throws {
        let result = cli(["ping", "send"] + arguments + ["--id", id])
        try #require(result == CommandResult(output: id + "\n"), "\(result.error)")
        await shipyard.reloadPings()
    }

    func withdraw(_ id: String) async throws {
        try #require(cli("ping", "withdraw", id).status == 0)
        await shipyard.reloadPings()
    }

    func numbers(_ name: String) -> [String: Int] {
        Dictionary((section(name)?.rows ?? []).filter { $0.kind == .ping }.map { ($0.title, $0.number) }, uniquingKeysWith: { first, _ in first })
    }

    func store(_ id: String, _ title: String, minutes: Double, number: Int) throws {
        let sent = ISO8601DateFormatter().string(from: Harness.now.addingTimeInterval(-minutes * 60))
        try FileManager.default.createDirectory(at: pingStore.directory, withIntermediateDirectories: true)
        try Data(#"{"id":"\#(id)","instance":"i-\#(id)","number":\#(number),"projects":["shop"],"sent":"\#(sent)","title":"\#(title)"}"#.utf8)
            .write(to: pingStore.directory.appendingPathComponent("\(id).json"))
    }
}

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

        await harness.shipyard.dismiss(try #require(harness.section("shop")?.rows.first { $0.title == "Still waiting" })).value
        try await harness.withdraw("review")
        #expect(harness.numbers("shop").isEmpty)

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        await relaunched.shipyard.start()
        try await relaunched.send("input", "Waiting again", "--project", "shop")
        #expect(relaunched.numbers("shop") == ["Waiting again": 4])
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
        harness.herdr.addMachine("beta-vps")
        harness.herdr.setListOutput(listed([
            (id: "q1", title: "Sent two minutes ago", projects: ["shop"], minutes: 2),
            (id: "q2", title: "Sent five minutes ago", projects: ["shop"], minutes: 5),
            (id: "q3", title: "Unfiled", projects: [], minutes: 4),
        ]), on: "beta-vps")

        try harness.writeConfig("[[projects]\n")
        await harness.shipyard.start()
        try harness.writeConfig(shopAndMachine)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.numbers("shop") == ["Sent a minute ago": 0, "Sent three minutes ago": 0])
        await harness.machineTimer.fire()

        #expect(harness.numbers("shop") == [
            "Sent five minutes ago": 1,
            "Sent three minutes ago": 2,
            "Sent two minutes ago": 3,
            "Sent a minute ago": 4,
        ])
        #expect(harness.numbers("beta-vps") == ["Unfiled": 1])
    }

    @Test("a remote ping takes its number at the first poll that lists it, after the pings already numbered; a machine's own section counts on its own; one that leaves never gives its number back, and one sent again is new; one past the end of a list that stopped early keeps its number; a machine taken out of the configuration retires its pings' numbers")
    func remote() async throws {
        let harness = try Harness(stored: "gho_stored", config: shopAndMachine)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        harness.herdr.addMachine("beta-vps")
        await harness.shipyard.start()
        await harness.machineTimer.fire()
        try await harness.send("local", "Local", "--project", "shop")

        harness.herdr.setListOutput(listed([
            (id: "q1", title: "Merge it?", projects: ["shop"], minutes: 30),
            (id: "q2", title: "Deploy?", projects: [], minutes: 30),
        ]), on: "beta-vps")
        await harness.machineTimer.fire()
        #expect(harness.numbers("shop") == ["Local": 1, "Merge it?": 2])
        #expect(harness.numbers("beta-vps") == ["Deploy?": 1])

        await harness.shipyard.dismiss(try #require(harness.section("shop")?.rows.first { $0.title == "Merge it?" })).value
        harness.herdr.setListOutput(listed([
            (id: "q1", title: "Merge it?", projects: ["shop"], minutes: 30),
        ]), on: "beta-vps")
        await harness.machineTimer.fire()
        let latest = listed([
            (id: "q1", title: "Merge it?", projects: ["shop"], minutes: 30),
            (id: "q3", title: "Ship it?", projects: ["shop"], minutes: 1),
            (id: "q2", title: "Deploy?", projects: [], minutes: 1),
        ])
        harness.herdr.setListOutput(latest, on: "beta-vps")
        await harness.machineTimer.fire()
        #expect(harness.numbers("shop") == ["Local": 1, "Ship it?": 3])
        #expect(harness.numbers("beta-vps") == ["Deploy?": 2])

        let relaunched = harness.relaunched()
        relaunched.stub.on(Harness.userURL, Harness.viewerAnswer)
        relaunched.graphQL([onePullRequest])
        relaunched.herdr.addMachine("beta-vps")
        relaunched.herdr.setListOutput(latest, on: "beta-vps")
        await relaunched.shipyard.start()
        await relaunched.machineTimer.fire()
        #expect(relaunched.numbers("shop") == ["Local": 1, "Ship it?": 3])
        #expect(relaunched.numbers("beta-vps") == ["Deploy?": 2])

        relaunched.herdr.setListOutput(listed([
            (id: "q2", title: "Deploy?", projects: [], minutes: 1),
        ], truncated: true), on: "beta-vps")
        await relaunched.machineTimer.fire()
        #expect(relaunched.shipyard.remote.machine("beta-vps")?.truncated == true)
        #expect(relaunched.numbers("shop") == ["Local": 1])
        relaunched.herdr.setListOutput(latest, on: "beta-vps")
        await relaunched.machineTimer.fire()
        #expect(relaunched.numbers("shop") == ["Local": 1, "Ship it?": 3])

        try relaunched.writeConfig(shopOnly)
        await relaunched.shipyard.reloadConfiguration()
        #expect(relaunched.numbers("shop") == ["Local": 1])
        try relaunched.writeConfig(shopAndMachine)
        await relaunched.shipyard.reloadConfiguration()
        await relaunched.machineTimer.fire()
        #expect(relaunched.numbers("shop") == ["Local": 1, "Merge it?": 4, "Ship it?": 5])
        #expect(relaunched.numbers("beta-vps") == ["Deploy?": 3])
    }
}
