import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

/// What the picker writes for the projects `graphql-pull-requests.json`
/// answers for (repo0 and repo1 are e-commerce's, repo2 is job-search's).
private let chosen = [
    NewProject(name: "e-commerce", repositories: ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]),
    NewProject(name: "job-search", repositories: ["yahyabedirhan/job-search"]),
]

private let chosenText = """

    [[projects]]
    name = "e-commerce"
    repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]

    [[projects]]
    name = "job-search"
    repositories = ["yahyabedirhan/job-search"]

    """

private func recentRepositories() throws -> StubHTTP.Answer {
    try Harness.fixture("graphql-recent-repositories.json")
}

private func pullRequests() throws -> StubHTTP.Answer {
    try Harness.fixture("graphql-pull-requests.json")
}

/// `GET /repos/{slug}`.
private func repositoryURL(_ slug: String) -> URL {
    GitHubClient.apiURL.appendingPathComponent("repos/\(slug)")
}

/// A REST answer from `Fixtures/` with the `core` rate-limit headers.
private func rest(_ name: String, status: Int = 200) throws -> StubHTTP.Answer {
    try .fixture(name, status: status, headers: Harness.rateLimitHeaders(remaining: 4999, resource: "core"))
}

/// Signed in with a stored token and, with `config`, that file; otherwise
/// no configuration file at all. Started: in `needsProjects` without projects.
@MainActor
private func signedIn(config: String? = nil, graphQL answers: [StubHTTP.Answer] = []) async throws -> Harness {
    let harness = try Harness(stored: "gho_stored", config: config)
    harness.stub.on(Harness.userURL, Harness.viewerAnswer)
    if !answers.isEmpty { harness.graphQL(answers) }
    await harness.shipyard.start()
    return harness
}

@Suite("Project picker")
@MainActor
struct ProjectPickerTests {
    // MARK: - Suggestions

    @Test("suggestions are the viewer's and contributed repositories, by latest push, once each, without archived ones")
    func suggestions() async throws {
        let harness = try await signedIn(graphQL: [recentRepositories()])
        #expect(harness.shipyard.phase == .needsProjects)

        let suggested = try await harness.shipyard.suggestedRepositories()

        #expect(suggested.map(\.slug) == [
            "yahyabedirhan/shipyard",
            "acme/storefront",
            "yahyabedirhan/e-commerce-backend",
            "friend/notes",
            "yahyabedirhan/job-search",
            "yahyabedirhan/empty",
        ])
        #expect(suggested[1] == RepoSummary(
            slug: "acme/storefront",
            description: "Acme's shop",
            isPrivate: true,
            isArchived: false,
            pushedAt: date("2026-09-25T09:30:00Z")
        ))
        #expect(suggested.allSatisfy { !$0.isArchived })
        #expect(harness.shipyard.phase == .needsProjects)
    }

    @Test("the suggestion query asks for both lists by push, archived own repositories filtered by GitHub")
    func suggestionQuery() async throws {
        let harness = try await signedIn(graphQL: [recentRepositories()])

        _ = try await harness.shipyard.suggestedRepositories()

        let request = try #require(harness.graphQLRequests.first)
        let body = try JSONDecoder().decode([String: String].self, from: try #require(request.httpBody))
        let query = try #require(body["query"])
        #expect(query.contains("repositories(first: 25, ownerAffiliations: [OWNER, COLLABORATOR], isArchived: false, orderBy: {field: PUSHED_AT, direction: DESC})"))
        #expect(query.contains("repositoriesContributedTo(first: 25, orderBy: {field: PUSHED_AT, direction: DESC})"))
        #expect(query.contains("nameWithOwner description isPrivate isArchived pushedAt"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gho_stored")
    }

    @Test("a 401 while suggesting signs out")
    func suggestionsUnauthorized() async throws {
        let harness = try await signedIn(graphQL: [Harness.unauthorized])

        await #expect(throws: GitHubError.unauthorized) {
            try await harness.shipyard.suggestedRepositories()
        }
        #expect(harness.shipyard.phase == .signedOut)
    }

    @Test("a spent limit while suggesting says so and holds refreshes back until it resets")
    func suggestionsRateLimited() async throws {
        let harness = try await signedIn(graphQL: [Harness.fixture("graphql-rate-limited.json", remaining: 0)])

        await #expect(throws: GitHubError.rateLimited(resetAt: Harness.rateLimitReset, api: .graphql)) {
            try await harness.shipyard.suggestedRepositories()
        }
        #expect(!harness.shipyard.canRefreshNow)
        #expect(harness.shipyard.phase == .needsProjects)
    }

    // MARK: - Checking a typed repository

    @Test("a typed repository GitHub has is accepted with GitHub's spelling")
    func checkAccepted() async throws {
        let harness = try await signedIn()
        harness.stub.on(repositoryURL("YahyaBedirhan/Shipyard-Notes"), try rest("rest-repository.json"))

        let check = await harness.shipyard.checkRepository("  YahyaBedirhan/Shipyard-Notes \n")

        #expect(check == .accepted(RepoSummary(
            slug: "yahyabedirhan/shipyard-notes",
            description: "Notes for shipyard",
            isPrivate: false,
            isArchived: false,
            pushedAt: date("2026-09-24T15:59:00Z")
        )))
        #expect(harness.stub.unmatched.isEmpty)
    }

    @Test("a github.com link is checked as the repository it names",
          arguments: ["https://github.com/yahyabedirhan/shipyard-notes", "https://github.com/yahyabedirhan/shipyard-notes.git", "github.com/yahyabedirhan/shipyard-notes/"])
    func checkLink(link: String) async throws {
        let harness = try await signedIn()
        harness.stub.on(repositoryURL("yahyabedirhan/shipyard-notes"), try rest("rest-repository.json"))

        let check = await harness.shipyard.checkRepository(link)

        guard case .accepted(let repository) = check else {
            Issue.record("expected the link to be accepted, got \(check)")
            return
        }
        #expect(repository.slug == "yahyabedirhan/shipyard-notes")
    }

    @Test("text that isn't owner/name is rejected without asking GitHub",
          arguments: ["shipyard", "a/b/c", "owner/", "/name", "own er/name", "https://github.com/o/r/pull/3", ""])
    func checkNotASlug(text: String) async throws {
        let harness = try await signedIn()

        let check = await harness.shipyard.checkRepository(text)

        #expect(check == .rejected(.notASlug(text)))
        let lookups = harness.stub.requests.filter { request in request.url?.path.hasPrefix("/repos") ?? false }
        #expect(lookups.isEmpty)
    }

    @Test("a repository GitHub doesn't have, or won't show, is rejected with the reason")
    func checkNotFound() async throws {
        let harness = try await signedIn()
        harness.stub.on(repositoryURL("yahyabedirhan/gone"), try rest("rest-not-found.json", status: 404))

        let check = await harness.shipyard.checkRepository("yahyabedirhan/gone")

        #expect(check == .rejected(.notFound("yahyabedirhan/gone")))
        #expect(RepositoryRejection.notFound("yahyabedirhan/gone").message
            == "GitHub has no repository `yahyabedirhan/gone`, or your account can't see it")
        #expect(harness.shipyard.phase == .needsProjects)
    }

    @Test("an organisation that refuses the token is rejected as forbidden")
    func checkForbidden() async throws {
        let harness = try await signedIn()
        harness.stub.on(repositoryURL("acme/secret"), .json(
            #"{"message":"Resource protected by organization SAML enforcement. You must grant your OAuth token access to this organization.","documentation_url":"https://docs.github.com/articles/authenticating-to-a-github-organization-with-saml-single-sign-on/","status":"403"}"#,
            status: 403,
            headers: Harness.rateLimitHeaders(remaining: 4998, resource: "core")
        ))

        #expect(await harness.shipyard.checkRepository("acme/secret") == .rejected(.forbidden("acme/secret")))
    }

    @Test("when GitHub can't be asked, the check says to try again")
    func checkUnreachable() async throws {
        let harness = try await signedIn()
        harness.stub.on(repositoryURL("yahyabedirhan/shipyard"), .failure())

        let check = await harness.shipyard.checkRepository("yahyabedirhan/shipyard")

        guard case .rejected(let rejection) = check, case .couldNotCheck("yahyabedirhan/shipyard", .network) = rejection else {
            Issue.record("expected couldNotCheck(network), got \(check)")
            return
        }
        #expect(rejection.message == "couldn't check `yahyabedirhan/shipyard` (GitHub can't be reached); try again")
    }

    @Test("a 401 while checking signs out")
    func checkUnauthorized() async throws {
        let harness = try await signedIn()
        harness.stub.on(repositoryURL("yahyabedirhan/shipyard"), Harness.unauthorized)

        let check = await harness.shipyard.checkRepository("yahyabedirhan/shipyard")

        #expect(check == .rejected(.couldNotCheck("yahyabedirhan/shipyard", .unauthorized)))
        #expect(harness.shipyard.phase == .signedOut)
    }

    // MARK: - Confirming

    @Test("confirming writes one block per project and moves to ready without a restart; emptying goes back to the picker")
    func confirmAndEmpty() async throws {
        // The third refresh asks for job-search alone, which this fixture's repo0 is.
        let harness = try await signedIn(graphQL: [
            recentRepositories(), pullRequests(), Harness.fixture("graphql-missing-repository.json"),
        ])
        #expect(harness.shipyard.phase == .needsProjects)
        // Starting without a file created it with the header alone.
        #expect(try String(contentsOf: harness.configURL, encoding: .utf8) == Configuration.header)
        _ = try await harness.shipyard.suggestedRepositories()

        let result = try await harness.shipyard.addProjects(chosen)

        let text = try String(contentsOf: harness.configURL, encoding: .utf8)
        #expect(text == Configuration.header + chosenText)
        #expect(text.hasPrefix("#:schema \(Configuration.schemaURL)\n"))
        guard case .changed(let configuration) = result else {
            Issue.record("expected a change, got \(result)")
            return
        }
        #expect(configuration.projects.map(\.name) == ["e-commerce", "job-search"])
        #expect(harness.shipyard.phase == .ready)
        #expect(harness.graphQLRequests.count == 2)
        #expect(harness.shipyard.menu.sections.map(\.name) == ["e-commerce", "job-search"])
        #expect(harness.section("job-search")?.rows.map(\.number) == [3])
        #expect(harness.timer.armed == 120)
        // First sight of the new projects: nothing announces itself.
        #expect(harness.notifier.posted.isEmpty)

        // The user (or an agent) takes every project out again.
        try harness.writeConfig(Configuration.header)
        await harness.shipyard.reloadConfiguration()

        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.timer.armed == nil)
        #expect(harness.graphQLRequests.count == 2)

        // The picker is back, and picking again reaches ready again.
        try await harness.shipyard.addProjects([chosen[1]])

        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.menu.sections.map(\.name) == ["job-search"])
        #expect(harness.section("job-search")?.rows.map(\.number) == [3])
        #expect(harness.graphQLRequests.count == 3)
    }

    @Test("confirming appends after what the file already holds, comments and settings kept")
    func confirmKeepsFile() async throws {
        let existing = """
            #:schema \(Configuration.schemaURL)
            # my settings, projects come later
            refresh-interval-seconds = 300   # slow is fine

            [attention]
            unseen = false
            """
        let harness = try await signedIn(config: existing, graphQL: [pullRequests()])
        #expect(harness.shipyard.phase == .needsProjects)

        try await harness.shipyard.addProjects(chosen)

        let text = try String(contentsOf: harness.configURL, encoding: .utf8)
        #expect(text == existing + "\n" + chosenText)
        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.configStore.lastValid.refreshIntervalSeconds == 300)
        #expect(harness.timer.armed == 300)
    }

    @Test("a choice the configuration can't take is refused without writing or moving")
    func confirmRejected() async throws {
        let harness = try await signedIn(graphQL: [pullRequests()])

        await #expect(throws: ConfigError([ConfigIssue(line: nil, message: "repository `nope` isn't `owner/name`")])) {
            try await harness.shipyard.addProjects([NewProject(name: "x", repositories: ["nope"])])
        }
        await #expect(throws: ConfigError([ConfigIssue(line: nil, message: "project name `x` is already used")])) {
            try await harness.shipyard.addProjects([
                NewProject(name: "x", repositories: ["o/a"]),
                NewProject(name: "x", repositories: ["o/b"]),
            ])
        }

        #expect(try String(contentsOf: harness.configURL, encoding: .utf8) == Configuration.header)
        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.graphQLRequests.isEmpty)
    }
}
