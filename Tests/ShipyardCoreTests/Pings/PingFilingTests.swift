import Foundation
import ShipyardConfig
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private typealias Listed = RepositoryListResponse.Repository

/// A ping filed by the agent's repository, end to end: the CLI in a fake
/// working folder, the repositories the app resolved, the ping store and
/// the menu.
@Suite("A ping filed by its repository")
@MainActor
struct PingFilingTests {
    @Test("a ping from a repository two projects watch shows in both and counts once per project row")
    func twoProjects() async throws {
        let config = """
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
        let harness = try await Harness.started(
            config: config,
            graphQL: PullRequestsResponse.answer([PullRequestsResponse("yahyabedirhan/shop", []), PullRequestsResponse("yahyabedirhan/blog", [])])
        )

        let result = harness.cli("ping", "Ready for review", origin: "git@github.com:yahyabedirhan/shop.git")
        try #require(result.status == 0, "\(result.error)")
        await harness.shipyard.reloadPings()

        for project in ["shop", "everything"] {
            let section = try #require(harness.section(project))
            #expect(section.rows.filter { $0.kind == .ping }.map(\.title) == ["Ready for review"], "\(project)")
            #expect(section.attentionCount == 1, "\(project)")
        }
        #expect(harness.section("blog")?.rows.isEmpty == true)
        #expect(harness.shipyard.menu.attention == AttentionCounts(pings: 1))
    }

    @Test("a repository a group brings in matches once the app has resolved it, and not before")
    func groupMatchesOnceResolved() async throws {
        let harness = try Harness(stored: "gho_stored", config: """
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
        let origin = "https://github.com/yahyabedirhan/shop.git"

        let before = harness.cli("ping", "Too early", origin: origin)
        #expect(before.status == 1)
        #expect(before.error.contains("no project watches `yahyabedirhan/shop`"))
        #expect(before.error.contains("the projects are `mine`"))

        await harness.shipyard.start()
        let after = harness.cli("ping", "Ready", origin: origin)
        try #require(after.status == 0, "\(after.error)")
        await harness.shipyard.reloadPings()

        #expect(harness.section("mine")?.rows.filter { $0.kind == .ping }.map(\.title) == ["Ready"])
    }

    @Test("--repo overrides the working folder, and outside a git folder without it the ping fails")
    func repoFlag() async throws {
        let harness = try await Harness.started(
            config: """
                [[projects]]
                name = "shop"
                repositories = ["yahyabedirhan/shop"]

                [[projects]]
                name = "blog"
                repositories = ["yahyabedirhan/blog"]

                """,
            graphQL: PullRequestsResponse.answer([PullRequestsResponse("yahyabedirhan/shop", []), PullRequestsResponse("yahyabedirhan/blog", [])])
        )

        let lost = harness.cli("ping", "Lost")
        #expect(lost.status == 1)
        #expect(lost.error.contains("isn't a git repository with a remote `origin`"))

        let result = harness.cli("ping", "Published", "--repo", "yahyabedirhan/blog", origin: "git@github.com:yahyabedirhan/shop.git")
        try #require(result.status == 0, "\(result.error)")
        await harness.shipyard.reloadPings()

        #expect(harness.section("blog")?.rows.map(\.title) == ["Published"])
        #expect(harness.section("shop")?.rows.isEmpty == true)
        #expect(harness.pingStore.all().map(\.title) == ["Published"])
    }

    @Test("grouped by repository, a ping filed by its repository joins that repository's group")
    func groupedByRepository() async throws {
        let harness = try await Harness.started(
            config: """
                [defaults]
                group-by = "repository"

                [[projects]]
                name = "shop"
                repositories = ["yahyabedirhan/shop"]

                """,
            graphQL: PullRequestsResponse.answer([PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)])])
        )
        try #require(harness.cli("ping", "Ready", origin: "git@github.com:YahyaBedirhan/Shop.git").status == 0)
        await harness.shipyard.reloadPings()

        let groups = try #require(harness.section("shop")?.groups)
        #expect(groups.map(\.title) == ["yahyabedirhan/shop"])
        #expect(Set(groups.first?.rows.map(\.kind) ?? []) == [.pullRequest, .ping])
    }
}

/// The repositories the app last resolved, as the CLI reads them.
@Suite("The resolved repositories file")
struct ResolvedRepositoriesStoreTests {
    let store = ResolvedRepositoriesStore(directory: FileManager.default.temporaryDirectory
        .appendingPathComponent("shipyard-repositories-\(UUID().uuidString)", isDirectory: true))

    @Test("what's recorded reads back; with no file there are no lists")
    func roundTrip() throws {
        #expect(store.load().isEmpty)
        try store.record(["shop": ["yahyabedirhan/shop"], "mine": ["o/a", "o/b"]])
        #expect(store.load() == ["shop": ["yahyabedirhan/shop"], "mine": ["o/a", "o/b"]])
    }

    @Test("a file that doesn't read, or that a newer build wrote, reads as no lists")
    func failsSafe() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.url)
        #expect(store.load().isEmpty)

        try Data(#"{"version": 99, "projects": {"shop": ["yahyabedirhan/shop"]}}"#.utf8).write(to: store.url)
        #expect(store.load().isEmpty)

        try store.record(["shop": ["yahyabedirhan/shop"]])
        #expect(store.load() == ["shop": ["yahyabedirhan/shop"]])
    }

    @Test("recording what the file already holds doesn't write it again")
    func unchanged() throws {
        try store.record(["shop": ["yahyabedirhan/shop"]])
        let written = try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as? Date
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: store.url.path)

        try store.record(["shop": ["yahyabedirhan/shop"]])

        #expect(written != nil)
        let after = try FileManager.default.attributesOfItem(atPath: store.url.path)[.modificationDate] as? Date
        #expect(after == Date(timeIntervalSince1970: 0))
    }
}
