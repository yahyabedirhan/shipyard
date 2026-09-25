import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

/// The projects `graphql-pull-requests.json` answers for: repo0 and repo1
/// are e-commerce's, repo2 is job-search's.
private let projects = """
    [[projects]]
    name = "e-commerce"
    repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]

    [[projects]]
    name = "job-search"
    repositories = ["yahyabedirhan/job-search"]

    """

/// The projects `graphql-missing-repository.json` answers for: repo0 is
/// job-search, repo1 doesn't exist.
private let withMissingRepository = """
    [[projects]]
    name = "job-search"
    repositories = ["yahyabedirhan/job-search"]

    [[projects]]
    name = "archive"
    repositories = ["yahyabedirhan/job-search", "yahyabedirhan/gone"]

    """

private func pullRequests() throws -> StubHTTP.Answer {
    try Harness.fixture("graphql-pull-requests.json")
}

/// What `/graphql` was sent.
private struct GraphQLBody: Decodable {
    var query: String
    var variables: [String: String]
}

@Suite("Pull requests through the refresh pipeline")
@MainActor
struct RefreshTests {
    // MARK: - The menu model

    @Test("one section per project in configuration order, each with all its repositories' pull requests")
    func sectionsPerProject() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests())

        let menu = harness.shipyard.menu
        #expect(harness.shipyard.phase == .ready)
        #expect(menu.sections.map(\.name) == ["e-commerce", "job-search"])
        // Open by last update, newest first; then closed by close time, newest
        // first. #8 closed 15 days ago, outside the 7-day window.
        #expect(menu.sections[0].rows.map(\.number) == [14, 57, 12, 56, 55, 54, 9])
        #expect(menu.sections[1].rows.map(\.number) == [3])
        #expect(menu.sections.allSatisfy { $0.errors.isEmpty })
        #expect(menu.lastUpdated == Harness.now)
        #expect(menu.fetchError == nil)
    }

    @Test("rows carry number, title, author, age, URL, state and, for open pull requests, a check state")
    func rows() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests())

        let rows = Dictionary(uniqueKeysWithValues: harness.shipyard.menu.sections.flatMap(\.rows).map { ($0.number, $0) })
        let fix = try #require(rows[12])
        #expect(fix.title == "Fix checkout totals")
        #expect(fix.author == "yabepa")
        #expect(fix.authorKind == .me)
        #expect(fix.repository == "yahyabedirhan/e-commerce-frontend")
        #expect(fix.url == URL(string: "https://github.com/yahyabedirhan/e-commerce-frontend/pull/12"))
        #expect(fix.kind == .pullRequest)
        #expect(fix.since == date("2026-09-24T08:00:00Z"))
        #expect(fix.age(at: Harness.now) == 28 * 3600)

        #expect(rows.mapValues(\.state) == [
            14: .draft, 57: .open, 12: .open, 56: .open, 55: .open, 54: .closed, 9: .merged, 3: .open,
        ])
        #expect(rows.mapValues(\.checks) == [
            14: .pending, 57: .failed, 12: .passed, 56: ChecksState.none, 55: .passed, 54: nil, 9: nil, 3: .failed,
        ])
        // A closed row's age counts from when it closed.
        #expect(rows[9]?.since == date("2026-09-23T15:00:00Z"))
        // GraphQL names a Bot without `[bot]`; a deleted account is `ghost`.
        #expect(rows[55]?.author == "dependabot[bot]")
        #expect(rows[55]?.authorKind == .bot)
        #expect(rows[54]?.author == "ghost")
        #expect(rows[56]?.authorKind == .other)
    }

    @Test("closed-window-days sets how far back closed pull requests show")
    func closedWindow() async throws {
        let harness = try await Harness.started(
            config: "[defaults.pull-requests]\nclosed-window-days = 1\n\n" + projects,
            graphQL: pullRequests()
        )

        // #54 closed 18 hours ago; #9 two days ago.
        #expect(harness.section("e-commerce")?.rows.map(\.number) == [14, 57, 12, 56, 55, 54])
    }

    @Test("a closed window of 0 hides closed pull requests, per project")
    func closedWindowZero() async throws {
        let config = """
            [[projects]]
            name = "e-commerce"
            repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]
            pull-requests = { closed-window-days = 0 }

            [[projects]]
            name = "job-search"
            repositories = ["yahyabedirhan/job-search"]

            """
        let harness = try await Harness.started(config: config, graphQL: pullRequests())

        #expect(harness.section("e-commerce")?.rows.map(\.number) == [14, 57, 12, 56, 55])
    }

    @Test("drafts = false hides drafts, and hide-authors hides those authors")
    func draftsAndHiddenAuthors() async throws {
        let harness = try await Harness.started(
            config: "hide-authors = [\"dependabot[bot]\"]\n\n[defaults.pull-requests]\ndrafts = false\n\n" + projects,
            graphQL: pullRequests()
        )

        #expect(harness.section("e-commerce")?.rows.map(\.number) == [57, 12, 56, 54, 9])
    }

    // MARK: - The request

    @Test("one GraphQL request covers every repository, and the rate-limit headers are read")
    func oneRequest() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests())

        let requests = harness.graphQLRequests
        try #require(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer gho_stored")
        let body = try JSONDecoder().decode(GraphQLBody.self, from: try #require(requests[0].httpBody))
        #expect(body.variables == [
            "owner0": "yahyabedirhan", "name0": "e-commerce-frontend",
            "owner1": "yahyabedirhan", "name1": "e-commerce-backend",
            "owner2": "yahyabedirhan", "name2": "job-search",
        ])
        for alias in 0..<3 {
            #expect(body.query.contains("repo\(alias): repository(owner: $owner\(alias), name: $name\(alias))"))
        }
        #expect(!body.query.contains("repo3"))
        #expect(body.query.contains("pullRequests(states: OPEN, first: 50"))
        #expect(body.query.contains("pullRequests(states: [CLOSED, MERGED], first: 20"))
        #expect(body.query.contains("rateLimit { limit remaining used resetAt cost }"))

        // The headers (remaining 4990) win over the body (4993); the cost comes from the body.
        #expect(harness.shipyard.snapshot?.rateLimits.graphql == RateLimit(
            limit: 5000, remaining: 4990, used: 10, resetAt: Harness.rateLimitReset, cost: 3
        ))
    }

    @Test("a repository in two projects is asked for once and shows in both")
    func sharedRepository() async throws {
        let harness = try await Harness.started(
            config: withMissingRepository,
            graphQL: Harness.fixture("graphql-missing-repository.json")
        )

        let body = try JSONDecoder().decode(GraphQLBody.self, from: try #require(harness.graphQLRequests.first?.httpBody))
        #expect(body.variables.count == 4)
        #expect(harness.section("job-search")?.rows.map(\.number) == [3])
        #expect(harness.section("archive")?.rows.map(\.number) == [3])
    }

    // MARK: - Failures

    @Test("a missing repository becomes an error row in its project while the rest load")
    func missingRepository() async throws {
        let harness = try await Harness.started(
            config: withMissingRepository,
            graphQL: Harness.fixture("graphql-missing-repository.json")
        )

        let archive = try #require(harness.section("archive"))
        #expect(archive.rows.map(\.number) == [3])
        #expect(archive.errors.map(\.repository) == ["yahyabedirhan/gone"])
        #expect(archive.errors.first?.kind == .notFound)
        #expect(archive.errors.first?.message == "yahyabedirhan/gone: not found, or no access")
        #expect(harness.section("job-search")?.errors.isEmpty == true)
        #expect(harness.shipyard.menu.fetchError == nil)
    }

    @Test("a network failure keeps the last model and when it was last updated; the next success clears it")
    func networkFailureKeepsModel() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests(), .failure(), pullRequests())
        let before = harness.shipyard.menu

        harness.clock.advance(by: 120)
        await harness.timer.fire()

        let after = harness.shipyard.menu
        #expect(after.sections == before.sections)
        #expect(after.lastUpdated == Harness.now)
        guard case .network = after.fetchError else {
            Issue.record("expected a network error, got \(String(describing: after.fetchError))")
            return
        }
        #expect(harness.shipyard.phase == .ready)

        harness.clock.advance(by: 120)
        await harness.timer.fire()

        #expect(harness.shipyard.menu.fetchError == nil)
        #expect(harness.shipyard.menu.lastUpdated == Harness.now.addingTimeInterval(240))
    }

    @Test("a GitHub server error keeps the last model too")
    func serverErrorKeepsModel() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests(), .status(502))
        let before = harness.shipyard.menu

        await harness.timer.fire()

        #expect(harness.shipyard.menu.sections == before.sections)
        #expect(harness.shipyard.menu.fetchError == .http(502))
        #expect(harness.shipyard.fetchError == .http(502))
    }

    @Test("GraphQL's exhausted limit (a 200 with RATE_LIMITED) keeps the model and records the reset time")
    func rateLimited() async throws {
        let exhausted = try StubHTTP.Answer.fixture(
            "graphql-rate-limited.json",
            headers: Harness.rateLimitHeaders(remaining: 0)
        )
        let harness = try await Harness.started(config: projects, graphQL: pullRequests(), exhausted)
        let before = harness.shipyard.menu

        await harness.timer.fire()

        #expect(harness.shipyard.menu.sections == before.sections)
        #expect(harness.shipyard.fetchError == .rateLimited(resetAt: Harness.rateLimitReset))
    }

    @Test("a 401 during a refresh signs out and stops the timer")
    func unauthorizedDuringRefresh() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests(), Harness.unauthorized)

        await harness.timer.fire()

        #expect(harness.shipyard.phase == .signedOut)
        #expect(try harness.store.token() == nil)
        #expect(harness.timer.armed == nil)
        #expect(harness.shipyard.menu == .empty)
    }

    // MARK: - When refreshes run

    @Test("after each refresh the timer is armed with the configured interval, and firing it refreshes")
    func timer() async throws {
        let harness = try await Harness.started(
            config: "refresh-interval-seconds = 300\n\n" + projects,
            graphQL: pullRequests()
        )
        #expect(harness.graphQLRequests.count == 1)
        #expect(harness.timer.armed == 300)

        await harness.timer.fire()

        #expect(harness.graphQLRequests.count == 2)
        #expect(harness.timer.armed == 300)
    }

    @Test("a refresh on request (panel open, ⌘R, wake) runs at once")
    func onRequest() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests())

        await harness.shipyard.refresh()

        #expect(harness.graphQLRequests.count == 2)
    }

    @Test("requests during a refresh run once, right after it")
    func oneAtATime() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests())
        let shipyard = harness.shipyard
        let inFlight = Locked(0)
        harness.stub.onSend { request in
            guard request.url == GitHubClient.graphQLURL else { return }
            let count = inFlight.withValue { count -> Int in
                count += 1
                return count
            }
            guard count == 1 else { return }
            #expect(await shipyard.isRefreshing)
            // Both return at once: the running refresh takes them up.
            await shipyard.refresh()
            await shipyard.refresh()
            #expect(inFlight.current == 1)
        }

        await shipyard.refresh()

        #expect(inFlight.current == 2)
        #expect(harness.graphQLRequests.count == 3)
        #expect(!shipyard.isRefreshing)
    }

    @Test("a configuration change during a refresh runs right after it, with the new configuration")
    func configurationChangeDuringRefresh() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests())
        let shipyard = harness.shipyard
        let configURL = harness.configURL
        let inFlight = Locked(0)
        harness.stub.onSend { request in
            guard request.url == GitHubClient.graphQLURL else { return }
            let count = inFlight.withValue { count -> Int in
                count += 1
                return count
            }
            guard count == 1 else { return }
            try? Data(("hide-authors = [\"dependabot[bot]\"]\n\n" + projects).utf8).write(to: configURL)
            await shipyard.reloadConfiguration()
        }

        await shipyard.refresh()

        #expect(harness.graphQLRequests.count == 3)
        #expect(harness.section("e-commerce")?.rows.map(\.number) == [14, 57, 12, 56, 54, 9])
    }

    // MARK: - Lifecycle

    @Test("no projects reaches needsProjects and fetches nothing; adding some reaches ready and refreshes")
    func lifecycle() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([try pullRequests()])

        await harness.shipyard.start()
        await harness.shipyard.refresh()

        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.graphQLRequests.isEmpty)
        #expect(harness.timer.armed == nil)

        try harness.writeConfig(projects)
        await harness.shipyard.reloadConfiguration()

        #expect(harness.shipyard.phase == .ready)
        #expect(harness.graphQLRequests.count == 1)
        #expect(harness.shipyard.menu.sections.map(\.name) == ["e-commerce", "job-search"])
        #expect(harness.timer.armed == 120)

        try harness.writeConfig("")
        await harness.shipyard.reloadConfiguration()

        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.timer.armed == nil)
        #expect(harness.graphQLRequests.count == 1)
    }

    @Test("a broken edit keeps the list and doesn't refresh")
    func brokenEdit() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests())
        let before = harness.shipyard.menu

        try harness.writeConfig("refresh-interval-seconds = 5\n\n" + projects)
        let result = await harness.shipyard.reloadConfiguration()

        guard case .invalid = result else {
            Issue.record("expected the edit to be rejected, got \(result)")
            return
        }
        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.menu == before)
        #expect(harness.graphQLRequests.count == 1)
    }

    @Test("a broken edit's error is published for the banner until the file is fixed")
    func brokenEditError() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests())
        #expect(harness.shipyard.configError == nil)

        try harness.writeConfig("refresh-interval-seconds = 5\n\n" + projects)
        await harness.shipyard.reloadConfiguration()

        let error = try #require(harness.shipyard.configError)
        #expect(error.issues.first?.line == 1)

        try harness.writeConfig(projects)
        await harness.shipyard.reloadConfiguration()

        #expect(harness.shipyard.configError == nil)
    }

    @Test("a file broken at launch is published for the banner")
    func brokenAtLaunch() async throws {
        let harness = try await Harness.started(config: "version = \"one\"\n", graphQL: pullRequests())

        #expect(harness.shipyard.configError != nil)
        #expect(harness.shipyard.phase == .needsProjects)
    }

    // MARK: - Opening an item

    @Test("opening a row opens its URL through the URL opener")
    func openRow() async throws {
        let harness = try await Harness.started(config: projects, graphQL: pullRequests())
        let row = try #require(harness.section("job-search")?.rows.first)

        harness.shipyard.open(row)

        #expect(harness.opener.opened == [URL(string: "https://github.com/yahyabedirhan/job-search/pull/3")!])
    }
}

@Suite("Refresh gate")
struct RefreshGateTests {
    @Test("one refresh at a time; requests meanwhile make one more run")
    func gate() {
        var gate = RefreshGate()
        let first = gate.begin()
        let running = gate.isRunning
        let second = gate.begin()
        let third = gate.begin()
        let runAgain = gate.finish()
        let stopped = !gate.isRunning
        let again = gate.begin()
        let nothingQueued = !gate.finish()
        #expect(first && running)
        #expect(!second && !third)
        #expect(runAgain && stopped)
        #expect(again && nothingQueued)
        #expect(!gate.isRunning)
    }
}
