import Foundation
@testable import ShipyardCore
import Testing

private typealias Listed = RepositoryListResponse.Repository

private let shopAndBlog = """
    [remote]
    machines = ["netcup-vps"]

    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    [[projects]]
    name = "everything"
    repositories = ["yahyabedirhan/shop", "yahyabedirhan/blog"]

    [[projects]]
    name = "blog"
    repositories = ["yahyabedirhan/blog"]

    """

private let bothRepositories = PullRequestsResponse.answer([
    PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]),
    PullRequestsResponse("yahyabedirhan/blog", []),
])

/// A ping as a machine without the app lists it: filed under no project
/// yet, with the repository or the `--project` name it was sent with.
private func ping(_ id: String, _ title: String, repository: String? = nil, project: String? = nil, sender: String? = nil) -> Ping {
    Ping(
        id: id,
        title: title,
        projects: project.map { [$0] } ?? [],
        sent: Harness.now.addingTimeInterval(-5 * 60),
        repository: repository,
        sender: sender,
        instance: "i-\(id)"
    )
}

@MainActor
private extension Harness {
    /// A harness signed in with `config`, whose Herdr has saved
    /// `netcup-vps` listing `pings`, started and polled once.
    static func polled(_ config: String = shopAndBlog, graphQL: StubHTTP.Answer = bothRepositories, pings: [Ping]) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([graphQL])
        harness.herdr.addMachine("netcup-vps", pings: pings)
        await harness.shipyard.start()
        let fired = await harness.machineTimer.fire()
        #expect(fired, "the machine timer wasn't armed")
        return harness
    }

    /// The titles of the ping rows in the section `name`.
    func pingTitles(_ name: String) -> [String] {
        section(name)?.rows.filter { $0.kind == .ping }.map(\.title) ?? []
    }
}

/// A remote ping filed on the Mac, as a local ping is when it's sent:
/// under the projects that watch its repository, else the project its
/// `--project` names, else its machine's section. End to end across a
/// fake `herdr`, `Shipyard`, the resolved repositories and the menu.
@Suite("Remote pings filed under projects")
@MainActor
struct RemotePingFilingTests {
    @Test("a remote ping lists under every project that watches its repository, matched ignoring case, and counts once")
    func byRepository() async throws {
        let harness = try await Harness.polled(pings: [ping("q1", "Deploy?", repository: "YahyaBedirhan/SHOP")])

        for project in ["shop", "everything"] {
            #expect(harness.pingTitles(project) == ["Deploy?"], "\(project)")
            // The open pull request, and the ping.
            #expect(harness.section(project)?.attentionCount == 2, "\(project)")
        }
        #expect(harness.pingTitles("blog").isEmpty)
        #expect(harness.pingTitles("netcup-vps").isEmpty)
        #expect(harness.shipyard.menu.attention.pings == 1)
        let row = try #require(harness.section("shop")?.rows.first { $0.kind == .ping })
        #expect(row.machine == "netcup-vps")
    }

    @Test("a repository a group brings in files a remote ping once the app has resolved it")
    func byResolvedRepository() async throws {
        let harness = try Harness(stored: "gho_stored", config: """
            [remote]
            machines = ["netcup-vps"]

            [[projects]]
            name = "mine"
            repositories = ["owned"]

            """)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.stub.on(
            "POST",
            GitHubClient.graphQLURL,
            body: RepositoryListResponse.groupQuery,
            answers: [RepositoryListResponse.page([Listed("yahyabedirhan/shop")])]
        )
        harness.graphQL([PullRequestsResponse.answer([PullRequestsResponse("yahyabedirhan/shop", [])])])
        harness.herdr.addMachine("netcup-vps", pings: [ping("q1", "Ready", repository: "yahyabedirhan/Shop")])
        await harness.shipyard.start()
        await harness.machineTimer.fire()

        #expect(harness.pingTitles("mine") == ["Ready"])
        #expect(harness.pingTitles("netcup-vps").isEmpty)
    }

    @Test("a repository no project watches lists the remote ping under its machine")
    func unwatchedRepository() async throws {
        let harness = try await Harness.polled(pings: [ping("q1", "Elsewhere", repository: "someone/else")])

        #expect(harness.pingTitles("netcup-vps") == ["Elsewhere"])
        for project in ["shop", "everything", "blog"] {
            #expect(harness.pingTitles(project).isEmpty, "\(project)")
        }
    }

    @Test("a --project name the configuration has files the remote ping there; one it doesn't lists it under its machine")
    func byProjectName() async throws {
        let harness = try await Harness.polled(pings: [
            ping("q1", "For the blog", project: "blog"),
            ping("q2", "For a typo", project: "blgo"),
        ])

        #expect(harness.pingTitles("blog") == ["For the blog"])
        #expect(harness.pingTitles("everything").isEmpty)
        #expect(harness.pingTitles("netcup-vps") == ["For a typo"])
    }

    @Test("a project's pings.show = false hides a remote ping filed there, as it does a local one")
    func hidden() async throws {
        let config = shopAndBlog.replacingOccurrences(
            of: "name = \"everything\"\n",
            with: "name = \"everything\"\npings.show = false\n"
        )
        let harness = try await Harness.polled(config, pings: [ping("q1", "Deploy?", repository: "yahyabedirhan/shop")])

        #expect(harness.pingTitles("shop") == ["Deploy?"])
        #expect(harness.pingTitles("everything").isEmpty)
        #expect(harness.pingTitles("netcup-vps").isEmpty)
    }

    @Test("grouped by repository, a remote ping joins its repository's group, spelled as the project knows it")
    func groupedByRepository() async throws {
        let harness = try await Harness.polled(
            "[defaults]\ngroup-by = \"repository\"\n\n" + shopAndBlog,
            pings: [ping("q1", "Deploy?", repository: "YahyaBedirhan/Shop")]
        )

        let groups = try #require(harness.section("shop")?.groups)
        #expect(groups.map(\.title) == ["yahyabedirhan/shop"])
        #expect(Set(groups.first?.rows.map(\.kind) ?? []) == [.pullRequest, .ping])
    }

    @Test("grouped by author, a remote ping joins its sender's group")
    func groupedBySender() async throws {
        let harness = try await Harness.polled(
            "[defaults]\ngroup-by = \"author\"\n\n" + shopAndBlog,
            pings: [ping("q1", "Deploy?", repository: "yahyabedirhan/shop", sender: "claude")]
        )

        let groups = try #require(harness.section("shop")?.groups)
        #expect(groups.map(\.title).contains("claude"))
        let sender = try #require(groups.first { $0.rows.contains { $0.kind == .ping } })
        #expect(sender.rows.map(\.title) == ["Deploy?"])
    }
}
