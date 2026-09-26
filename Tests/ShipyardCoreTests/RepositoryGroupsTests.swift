import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private typealias Listed = RepositoryListResponse.Repository

/// A GraphQL answer giving each of `repositories`, in order, one open pull
/// request numbered from `first`.
private func pullRequests(_ repositories: [String], first: Int = 1) -> StubHTTP.Answer {
    PullRequestsResponse.answer(repositories.enumerated().map { offset, repository in
        PullRequestsResponse(repository, [PullRequestsResponse.PullRequest(first + offset)])
    })
}

/// The repositories a fetch request asked about, in alias order.
private func fetched(_ request: URLRequest) -> [String] {
    guard let body = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any],
          let variables = body["variables"] as? [String: Any]
    else { return [] }
    return (0..<variables.count).compactMap { index in
        guard let owner = variables["owner\(index)"] as? String, let name = variables["name\(index)"] as? String else { return nil }
        return "\(owner)/\(name)"
    }
}

/// The variables a lookup request sent.
private func variables(_ request: URLRequest) -> [String: String] {
    let body = try? JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any]
    return body?["variables"] as? [String: String] ?? [:]
}

@MainActor
private extension Harness {
    /// A signed-in harness over `config`, with the group and owner lookups
    /// and the fetches answering in order, not started yet.
    static func withLookups(
        _ config: String,
        groups: [StubHTTP.Answer] = [],
        owners: [StubHTTP.Answer] = [],
        fetches: [StubHTTP.Answer]
    ) throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        if !groups.isEmpty {
            harness.stub.on("POST", GitHubClient.graphQLURL, body: RepositoryListResponse.groupQuery, answers: groups)
        }
        if !owners.isEmpty {
            harness.stub.on("POST", GitHubClient.graphQLURL, body: RepositoryListResponse.ownerQuery, answers: owners)
        }
        harness.graphQL(fetches)
        return harness
    }

    var groupLookups: [URLRequest] {
        stub.requests("POST", GitHubClient.graphQLURL, body: RepositoryListResponse.groupQuery)
    }

    var ownerLookups: [URLRequest] {
        stub.requests("POST", GitHubClient.graphQLURL, body: RepositoryListResponse.ownerQuery)
    }

    /// Every GraphQL request that fetched items (not a lookup).
    var fetches: [URLRequest] {
        graphQLRequests.filter { !$0.bodyText.contains("ShipyardGroupRepositories") && !$0.bodyText.contains("ShipyardOwnerRepositories") }
    }
}

@Suite("A project watches repository groups and owner wildcards")
@MainActor
struct RepositoryGroupsTests {
    @Test(
        "each group lists the viewer's repositories through its own affiliation, page after page, archived ones left out",
        arguments: [(RepositoryGroup.owned, "OWNER"), (.organizations, "ORGANIZATION_MEMBER"), (.collaborator, "COLLABORATOR")]
    )
    func groupResolves(group: RepositoryGroup, affiliation: String) async throws {
        let harness = try Harness.withLookups(
            """
            [[projects]]
            name = "mine"
            repositories = ["\(group.rawValue)"]
            """,
            groups: [
                RepositoryListResponse.page([Listed("o/a"), Listed("o/old", archived: true)], next: "cursor-1"),
                RepositoryListResponse.page([Listed("o/fork", fork: true)]),
            ],
            fetches: [pullRequests(["o/a", "o/fork"])]
        )
        await harness.shipyard.start()

        let lookups = harness.groupLookups
        #expect(lookups.count == 2)
        #expect(lookups[0].bodyText.contains("repositories(first: 100, after: $after, affiliations: [\(affiliation)], ownerAffiliations: [\(affiliation)]"))
        #expect(lookups[0].bodyText.contains("isArchived isFork"))
        #expect(variables(lookups[0]) == [:])
        #expect(variables(lookups[1]) == ["after": "cursor-1"])
        // Forks are kept by default; archived repositories are left out.
        #expect(harness.fetches.map(fetched) == [["o/a", "o/fork"]])
        let section = try #require(harness.section("mine"))
        #expect(section.rows.map(\.repository) == ["o/a", "o/fork"])
        #expect(section.repositories == ["o/a", "o/fork"])
        #expect(section.showsRepository)
        #expect(section.errors.isEmpty)
        // A project's first sight is quiet, whatever brought its repositories in.
        #expect(harness.notifier.posted.isEmpty)
    }

    @Test("owner/* lists what the owner owns; archived = true brings in archived ones, forks = false leaves forks out")
    func ownerWildcard() async throws {
        let harness = try Harness.withLookups(
            """
            [[projects]]
            name = "org"
            repositories = ["Some-Org/*"]
            archived = true
            forks = false
            """,
            owners: [RepositoryListResponse.page(
                [Listed("some-org/app"), Listed("some-org/legacy", archived: true), Listed("some-org/upstream", fork: true)],
                owner: true
            )],
            fetches: [pullRequests(["some-org/app", "some-org/legacy"])]
        )
        await harness.shipyard.start()

        let lookup = try #require(harness.ownerLookups.first)
        #expect(harness.ownerLookups.count == 1)
        #expect(lookup.bodyText.contains("repositoryOwner(login: $login)"))
        #expect(lookup.bodyText.contains("ownerAffiliations: [OWNER]"))
        #expect(variables(lookup) == ["login": "some-org"])
        #expect(harness.groupLookups.isEmpty)
        #expect(harness.section("org")?.rows.map(\.repository) == ["some-org/app", "some-org/legacy"])
    }

    @Test("mixed selectors list each repository once; one named on its own is listed even when archived")
    func mixedSelectors() async throws {
        let harness = try Harness.withLookups(
            """
            [[projects]]
            name = "everything"
            repositories = ["owned", "yahyabedirhan/*", "yahyabedirhan/retired", "YahyaBedirhan/A"]

            [[projects]]
            name = "also-mine"
            repositories = ["owned"]
            """,
            groups: [RepositoryListResponse.page([Listed("yahyabedirhan/a"), Listed("yahyabedirhan/b")])],
            owners: [RepositoryListResponse.page(
                [Listed("yahyabedirhan/A"), Listed("yahyabedirhan/b"), Listed("yahyabedirhan/retired", archived: true)],
                owner: true
            )],
            fetches: [pullRequests(["yahyabedirhan/a", "yahyabedirhan/b", "yahyabedirhan/retired"])]
        )
        await harness.shipyard.start()

        // `owned` is looked up once for both projects.
        #expect(harness.groupLookups.count == 1)
        #expect(harness.ownerLookups.count == 1)
        #expect(harness.fetches.map(fetched) == [["yahyabedirhan/a", "yahyabedirhan/b", "yahyabedirhan/retired"]])
        #expect(harness.section("everything")?.rows.map(\.repository) == ["yahyabedirhan/a", "yahyabedirhan/b", "yahyabedirhan/retired"])
        #expect(harness.section("also-mine")?.rows.map(\.repository) == ["yahyabedirhan/a", "yahyabedirhan/b"])
        // A pull request in two projects counts once.
        #expect(harness.shipyard.menu.attention.total == 3)
    }

    @Test("an owner that doesn't exist is an error row while the rest lists; an empty group shows Nothing open")
    func missingOwnerAndEmptyGroup() async throws {
        let harness = try Harness.withLookups(
            """
            [[projects]]
            name = "typo"
            repositories = ["ghost-org/*", "o/r"]

            [[projects]]
            name = "helping"
            repositories = ["collaborator"]
            """,
            groups: [RepositoryListResponse.page([])],
            owners: [RepositoryListResponse.missingOwner],
            fetches: [pullRequests(["o/r"])]
        )
        await harness.shipyard.start()

        let typo = try #require(harness.section("typo"))
        #expect(typo.errors.map(\.message) == ["ghost-org/*: not found, or no access"])
        #expect(typo.rows.map(\.repository) == ["o/r"])
        let helping = try #require(harness.section("helping"))
        #expect(helping.errors.isEmpty)
        #expect(helping.rows.isEmpty)
        #expect(PanelText.emptySection(helping) == "Nothing open")
        #expect(harness.shipyard.fetchError == nil)

        // An owner that can't be seen is an answer: it's asked again within
        // the hour only when forced.
        harness.clock.advance(by: 120)
        await harness.timer.fire()
        #expect(harness.ownerLookups.count == 1)
        #expect(harness.section("typo")?.errors.count == 1)
    }

    @Test("a failed lookup keeps the last list; with none to keep, the selector shows an error row")
    func failedLookup() async throws {
        let harness = try Harness.withLookups(
            """
            [[projects]]
            name = "mine"
            repositories = ["owned"]
            """,
            groups: [RepositoryListResponse.page([Listed("o/a")]), .failure()],
            fetches: [pullRequests(["o/a"])]
        )
        await harness.shipyard.start()
        #expect(harness.section("mine")?.rows.map(\.repository) == ["o/a"])

        // ⌘R looks it up again, which fails: the last list is fetched.
        await harness.shipyard.refreshNow()
        #expect(harness.groupLookups.count == 2)
        #expect(harness.fetches.map(fetched) == [["o/a"], ["o/a"]])
        #expect(harness.section("mine")?.rows.map(\.repository) == ["o/a"])
        #expect(harness.section("mine")?.errors.isEmpty == true)

        // A failed lookup is tried again at the next refresh, not an hour later.
        harness.clock.advance(by: 120)
        await harness.timer.fire()
        #expect(harness.groupLookups.count == 3)

        let fresh = try Harness.withLookups(
            """
            [[projects]]
            name = "mine"
            repositories = ["owned", "o/r"]
            """,
            groups: [.failure()],
            fetches: [pullRequests(["o/r"])]
        )
        await fresh.shipyard.start()
        let section = try #require(fresh.section("mine"))
        #expect(section.errors.map(\.message) == ["owned: couldn't list its repositories (GitHub can't be reached)"])
        #expect(section.rows.map(\.repository) == ["o/r"])
    }

    @Test("a repository created later appears at the next hourly look, quietly, and its new items notify after")
    func newRepositoryHourly() async throws {
        let created = RepositoryListResponse.page([Listed("o/a"), Listed("o/new")])
        var laterPR = PullRequestsResponse.PullRequest(8)
        laterPR.author = "someone"
        let harness = try Harness.withLookups(
            """
            [[projects]]
            name = "mine"
            repositories = ["owned"]
            """,
            groups: [RepositoryListResponse.page([Listed("o/a")]), created],
            fetches: [
                pullRequests(["o/a"]),
                pullRequests(["o/a"]),
                pullRequests(["o/a", "o/new"], first: 1),
                PullRequestsResponse.answer([
                    PullRequestsResponse("o/a", [PullRequestsResponse.PullRequest(1)]),
                    PullRequestsResponse("o/new", [PullRequestsResponse.PullRequest(2), laterPR]),
                ]),
            ]
        )
        await harness.shipyard.start()

        // Two minutes on: the list is fresh, so nothing is looked up.
        harness.clock.advance(by: 120)
        await harness.timer.fire()
        #expect(harness.groupLookups.count == 1)
        #expect(harness.section("mine")?.rows.map(\.repository) == ["o/a"])

        // An hour on: looked up again, and the new repository's open pull
        // request is listed without a notification.
        harness.clock.advance(by: RepositoryResolver.interval)
        await harness.timer.fire()
        #expect(harness.groupLookups.count == 2)
        #expect(harness.section("mine")?.rows.map(\.repository).sorted() == ["o/a", "o/new"])
        #expect(harness.notifier.posted.isEmpty)

        // What happens there afterwards notifies as anywhere else.
        harness.clock.advance(by: 120)
        await harness.timer.fire()
        #expect(harness.notifier.posted.map(\.headline) == ["New PR #8"])
    }

    @Test("⌘R and a configuration change look groups up at once")
    func forcedLookups() async throws {
        let harness = try Harness.withLookups(
            """
            [[projects]]
            name = "mine"
            repositories = ["owned"]
            """,
            groups: [
                RepositoryListResponse.page([Listed("o/a")]),
                RepositoryListResponse.page([Listed("o/a"), Listed("o/new")]),
            ],
            fetches: [pullRequests(["o/a"]), pullRequests(["o/a", "o/new"])]
        )
        await harness.shipyard.start()

        await harness.shipyard.refreshNow()
        #expect(harness.groupLookups.count == 2)
        #expect(harness.section("mine")?.rows.map(\.repository) == ["o/a", "o/new"])
        #expect(harness.notifier.posted.isEmpty)

        // `forks = false` changes what the group brings in: looked up again at once.
        try harness.writeConfig("""
            [[projects]]
            name = "mine"
            repositories = ["owned"]
            forks = false
            """)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.groupLookups.count == 3)
    }
}
