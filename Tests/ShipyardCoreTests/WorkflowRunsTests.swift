import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shopRepository = "yahyabedirhan/shop"
private let blogRepository = "yahyabedirhan/blog"

/// Runs on for the shop project, with the default window and branches.
/// `rest-workflow-runs.json` answers for it; pull request #1's head is
/// `change-1` (see `PullRequestsResponse`), the default branch `main`.
private func runsConfig(_ runs: String = "workflow-runs = { show = true }", extra: String = "") -> String {
    """
    \(extra)
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]
    \(runs)

    """
}

private typealias PR = PullRequestsResponse.PullRequest
private typealias Run = WorkflowRunsResponse.Run

private func run(
    _ number: Int,
    _ state: String = "success",
    branch: String = "main",
    name: String = "CI",
    updatedAt: String? = nil
) -> Run {
    var run = Run(number)
    run.name = name
    run.branch = branch
    if state == "running" {
        run.status = "in_progress"
        run.conclusion = nil
    } else {
        run.conclusion = state
    }
    run.updatedAt = updatedAt ?? String(format: "2026-09-25T11:%02d:00Z", number)
    return run
}

/// `Fixtures/rest-workflow-runs.json`, with REST's rate-limit headers.
private func runsFixture() throws -> StubHTTP.Answer {
    try .fixture("rest-workflow-runs.json", headers: Harness.rateLimitHeaders(remaining: 4900, resource: "core"))
}

private func shopGraphQL(_ pullRequests: [PR] = [PR(1)]) -> StubHTTP.Answer {
    PullRequestsResponse(shopRepository, pullRequests).answer
}

private func shopRuns(_ runs: [Run], etag: String? = nil) -> StubHTTP.Answer {
    WorkflowRunsResponse(shopRepository, runs).answer(etag: etag)
}

/// What `/graphql` was sent.
private struct QueryBody: Decodable {
    var query: String
}

@MainActor
private extension Harness {
    /// Signed in with `config`, GraphQL answering `graphQL` and each
    /// repository's runs endpoint its answers, after `start()`.
    static func started(config: String, graphQL: StubHTTP.Answer, runs: [String: [StubHTTP.Answer]]) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.stub.on(userURL, viewerAnswer)
        harness.graphQL([graphQL])
        for (repository, answers) in runs {
            harness.stub.on("GET", WorkflowRunsResponse.url(repository), answers: answers)
        }
        await harness.shipyard.start()
        return harness
    }

    /// Refreshes `after` seconds later, with the runs endpoint of `repository`
    /// answering `runs` (and GraphQL as before, or `graphQL`).
    func refresh(runs: StubHTTP.Answer, of repository: String = shopRepository, graphQL: StubHTTP.Answer? = nil, after: TimeInterval = 120) async {
        stub.on("GET", WorkflowRunsResponse.url(repository), runs)
        if let graphQL { self.graphQL([graphQL]) }
        clock.advance(by: after)
        await shipyard.refresh()
    }

    /// Every runs request sent, in order, to any repository.
    var runsRequests: [URLRequest] {
        stub.requests.filter { $0.url?.path.hasSuffix("/actions/runs") ?? false }
    }

    func lastQuery() throws -> String {
        let body = try #require(graphQLRequests.last?.httpBody)
        return try JSONDecoder().decode(QueryBody.self, from: body).query
    }

    var runRows: [MenuRow] { section("shop")?.rows.filter { $0.kind == .workflowRun } ?? [] }
    var titles: [String] { notifier.posted.map(\.title) }
}

@Suite("Workflow runs through the refresh pipeline")
@MainActor
struct WorkflowRunsTests {
    // MARK: - Showing

    @Test("runs follow issues: running first, then finished within 3 hours, on the default branch and open pull requests' heads")
    func showing() async throws {
        let harness = try await Harness.started(
            config: runsConfig(),
            graphQL: shopGraphQL(),
            runs: [shopRepository: [runsFixture()]]
        )

        let rows = try #require(harness.section("shop")?.rows)
        // #39 ran on `experiment` (no pull request), #38 finished 3.5 hours
        // ago, #37 was cancelled.
        #expect(rows.map(\.kind) == [.pullRequest, .workflowRun, .workflowRun, .workflowRun, .workflowRun])
        let runs = harness.runRows
        #expect(runs.map(\.number) == [43, 42, 41, 40])
        #expect(runs.map(\.title) == ["Lint", "Deploy", "CI", "CI"])
        #expect(runs.map(\.branch) == ["change-1", "main", "change-1", "main"])
        #expect(runs.map(\.state) == [.running, .running, .failed, .succeeded])
        #expect(runs.allSatisfy { $0.checks == nil })
        #expect(runs[1].author == "github-actions[bot]")
        #expect(runs[1].authorKind == .bot)
        #expect(runs[2].authorKind == .me)
        #expect(runs[2].url == URL(string: "https://github.com/yahyabedirhan/shop/actions/runs/9041"))
        // Age: a running run's from when it started, a finished one's from when it finished.
        #expect(runs[1].since == date("2026-09-25T11:55:10Z"))
        #expect(runs[1].age(at: Harness.now) == 290)
        #expect(runs[2].since == date("2026-09-25T11:50:00Z"))
        #expect(rows.first?.branch == nil)

        // One request for the repository's recent runs, with its default
        // branch and pull request heads asked for in the GraphQL request.
        let request = try #require(harness.runsRequests.first)
        #expect(harness.runsRequests.count == 1)
        let url = try #require(request.url?.absoluteString)
        #expect(url.hasPrefix("https://api.github.com/repos/yahyabedirhan/shop/actions/runs?"))
        #expect(url.contains("created=%3E%3D2026-09-25T08:00:00Z"))
        #expect(url.contains("exclude_pull_requests=true"))
        #expect(url.contains("per_page=100"))
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        let query = try harness.lastQuery()
        #expect(query.contains("defaultBranchRef { name }"))
        #expect(query.contains("headRefName"))
    }

    @Test("branches = \"all\" keeps runs on every branch, and asks GraphQL for no branches")
    func allBranches() async throws {
        let harness = try await Harness.started(
            config: runsConfig(#"workflow-runs = { show = true, branches = "all" }"#),
            graphQL: shopGraphQL(),
            runs: [shopRepository: [runsFixture()]]
        )
        #expect(harness.runRows.map(\.number) == [43, 42, 41, 40, 39])
        #expect(harness.runRows.map(\.branch).last == "experiment")
        #expect(try !harness.lastQuery().contains("defaultBranchRef"))
    }

    @Test("a closed pull request's branch drops out; runs shown without pull requests still ask for the heads")
    func branchesFollowPullRequests() async throws {
        var feature = PR(2)
        feature.headRefName = "feature"
        let config = runsConfig("workflow-runs = { show = true }\npull-requests = { show = false }")
        let heads = { (pullRequests: [PR]) in
            var response = PullRequestsResponse(shopRepository, pullRequests)
            response.headsOnly = true
            return response.answer
        }
        let harness = try await Harness.started(
            config: config,
            graphQL: heads([feature]),
            runs: [shopRepository: [shopRuns([run(10, branch: "feature"), run(11, branch: "main"), run(12, branch: "other")])]]
        )
        #expect(harness.section("shop")?.rows.map(\.number) == [11, 10])
        let query = try harness.lastQuery()
        #expect(query.contains("openPullRequestHeads: pullRequests(states: OPEN, first: 50"))
        #expect(!query.contains("...PullRequestFields"))

        feature.state = "CLOSED"
        feature.closedAt = "2026-09-25T12:01:00Z"
        await harness.refresh(
            runs: shopRuns([run(10, branch: "feature"), run(11, branch: "main"), run(12, branch: "other")]),
            graphQL: heads([feature])
        )
        #expect(harness.section("shop")?.rows.map(\.number) == [11])
    }

    @Test("finished runs stay for finished-window-hours; running ones stay however long they run")
    func finishedWindow() async throws {
        let harness = try await Harness.started(
            config: runsConfig("workflow-runs = { show = true, finished-window-hours = 4 }"),
            graphQL: shopGraphQL(),
            runs: [shopRepository: [runsFixture()]]
        )
        // #38 finished at 08:30, inside 4 hours; the request reaches back to 07:00.
        #expect(harness.runRows.map(\.number) == [43, 42, 41, 40, 38])
        #expect(harness.runsRequests.last?.url?.absoluteString.contains("created=%3E%3D2026-09-25T07:00:00Z") == true)

        // At 15:40 #41 (finished 11:50) is still inside the window, #40 (11:30) isn't.
        await harness.refresh(
            runs: shopRuns([run(42, "running", updatedAt: "2026-09-25T11:58:00Z"), run(41, "failure", updatedAt: "2026-09-25T11:50:00Z"), run(40, updatedAt: "2026-09-25T11:30:00Z")]),
            after: 3 * 3600 + 40 * 60
        )
        #expect(harness.runRows.map(\.number) == [42, 41])
        #expect(harness.runsRequests.last?.url?.absoluteString.contains("created=%3E%3D2026-09-25T10:00:00Z") == true)

        // A window of 0 lists only running runs.
        try harness.writeConfig(runsConfig("workflow-runs = { show = true, finished-window-hours = 0 }"))
        harness.stub.on("GET", WorkflowRunsResponse.url(shopRepository), shopRuns([run(42, "running"), run(41, "failure")]))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.runRows.map(\.number) == [42])
    }

    @Test("off by default: no runs requested, no branches asked for")
    func offByDefault() async throws {
        let harness = try await Harness.started(config: runsConfig(""), graphQL: shopGraphQL(), runs: [:])
        #expect(harness.runsRequests.isEmpty)
        #expect(harness.section("shop")?.rows.map(\.kind) == [.pullRequest])
        let query = try harness.lastQuery()
        #expect(!query.contains("defaultBranchRef"))
        #expect(!query.contains("openPullRequestHeads"))
        // No REST limit is reported while runs are off.
        #expect(harness.shipyard.menu.rateIndicator?.apis.map(\.api) == [.graphql])
    }

    @Test("the footer's REST line comes with runs and goes when they're turned off")
    func restLineFollowsRuns() async throws {
        let harness = try await Harness.started(
            config: runsConfig(),
            graphQL: shopGraphQL(),
            runs: [shopRepository: [runsFixture()]]
        )
        #expect(harness.shipyard.menu.rateIndicator?.apis.map(\.api) == [.graphql, .rest])

        try harness.writeConfig(runsConfig(""))
        harness.clock.advance(by: 120)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.runRows.isEmpty)
        #expect(harness.shipyard.menu.rateIndicator?.apis.map(\.api) == [.graphql])
    }

    // MARK: - Conditional requests and the rate limit

    @Test("each refresh asks once per repository, one after another, with If-None-Match; a 304 reuses the runs and costs nothing")
    func notModified() async throws {
        let config = """
            [defaults.workflow-runs]
            show = true
            branches = "all"

            [[projects]]
            name = "shop"
            repositories = ["yahyabedirhan/shop", "yahyabedirhan/blog"]

            """
        let graphQL = PullRequestsResponse.answer([
            PullRequestsResponse(shopRepository, [PR(1)]),
            PullRequestsResponse(blogRepository, [PR(2)]),
        ])
        let harness = try await Harness.started(
            config: config,
            graphQL: graphQL,
            runs: [
                shopRepository: [shopRuns([run(41, "failure"), run(40)], etag: #"W/"shop-1""#)],
                blogRepository: [WorkflowRunsResponse(blogRepository, [run(7)]).answer(etag: #"W/"blog-1""#, remaining: 4899)],
            ]
        )
        let rows = harness.runRows.map { "\($0.repository)#\($0.number)" }
        #expect(rows == ["yahyabedirhan/shop#41", "yahyabedirhan/shop#40", "yahyabedirhan/blog#7"])
        #expect(harness.runsRequests.compactMap(\.url?.path) == [
            "/repos/yahyabedirhan/shop/actions/runs",
            "/repos/yahyabedirhan/blog/actions/runs",
        ])
        // REST's headers reach the budget and the footer, with the two
        // requests that counted.
        #expect(harness.shipyard.budget.costs[.rest] == [2])
        let rest = try #require(harness.shipyard.menu.rateIndicator?.apis.first { $0.api == .rest })
        #expect(rest.remaining == 4899)
        #expect(rest.limit == 5000)
        #expect(rest.resetAt == Harness.rateLimitReset)

        // Nothing changed: both answer 304, and the runs are listed as before.
        harness.stub.on("GET", WorkflowRunsResponse.url(blogRepository), WorkflowRunsResponse.notModified(etag: #"W/"blog-1""#, remaining: 4899))
        await harness.refresh(runs: WorkflowRunsResponse.notModified(etag: #"W/"shop-1""#, remaining: 4899))
        let second = Array(harness.runsRequests.suffix(2))
        #expect(second.map { $0.value(forHTTPHeaderField: "If-None-Match") } == [#"W/"shop-1""#, #"W/"blog-1""#])
        #expect(harness.runRows.map { "\($0.repository)#\($0.number)" } == rows)
        #expect(harness.shipyard.fetchError == nil)
        #expect(harness.shipyard.budget.costs[.rest] == [2, 0])
        #expect(harness.runsRequests.count == 4)

        // A new answer replaces them.
        await harness.refresh(runs: shopRuns([run(42, "running"), run(41, "failure"), run(40)], etag: #"W/"shop-2""#))
        #expect(harness.runRows.map(\.number) == [42, 41, 40, 7])
        #expect(harness.shipyard.budget.costs[.rest] == [2, 0, 1])
    }

    @Test("a repository whose runs can't be read shows an error row and keeps its pull requests")
    func runsError() async throws {
        let harness = try await Harness.started(
            config: runsConfig(),
            graphQL: shopGraphQL(),
            runs: [shopRepository: [.status(500, headers: Harness.rateLimitHeaders(remaining: 4900, resource: "core"))]]
        )
        #expect(harness.section("shop")?.rows.map(\.number) == [1])
        #expect(harness.section("shop")?.errors.map(\.message) == ["yahyabedirhan/shop: workflow runs: HTTP 500"])
        #expect(harness.shipyard.fetchError == nil)
    }

    @Test("a repository's runs error shows only in projects that show its runs")
    func runsErrorOnlyWhereShown() async throws {
        let config = runsConfig() + """
            [[projects]]
            name = "everything"
            repositories = ["yahyabedirhan/shop"]

            """
        let harness = try await Harness.started(
            config: config,
            graphQL: shopGraphQL(),
            runs: [shopRepository: [.status(500, headers: Harness.rateLimitHeaders(remaining: 4900, resource: "core"))]]
        )
        #expect(harness.section("shop")?.errors.map(\.message) == ["yahyabedirhan/shop: workflow runs: HTTP 500"])
        #expect(harness.section("everything")?.rows.map(\.number) == [1])
        #expect(harness.section("everything")?.errors.isEmpty == true)
    }

    @Test("forbidden runs don't hold back a new project's pull request events")
    func forbiddenRunsDontHoldBackPullRequests() async throws {
        let forbidden = StubHTTP.Answer.status(403, headers: Harness.rateLimitHeaders(remaining: 4900, resource: "core"))
        let harness = try await Harness.started(
            config: runsConfig(),
            graphQL: shopGraphQL([PR(1)]),
            runs: [shopRepository: [forbidden]]
        )
        #expect(harness.section("shop")?.errors.map(\.kind) == [.forbidden])
        #expect(harness.notifier.posted.isEmpty)

        await harness.refresh(runs: forbidden, graphQL: shopGraphQL([PR(1), PR(2)]))
        #expect(harness.titles == ["shop · New PR #2"])
    }

    @Test("a spent REST limit keeps the last rows and pauses until its reset")
    func restLimitSpent() async throws {
        let harness = try await Harness.started(
            config: runsConfig(),
            graphQL: shopGraphQL(),
            runs: [shopRepository: [shopRuns([run(40)])]]
        )
        await harness.refresh(runs: .json(
            #"{"message":"API rate limit exceeded for user ID 42."}"#,
            status: 403,
            headers: Harness.rateLimitHeaders(remaining: 0, resource: "core")
        ))
        #expect(harness.shipyard.fetchError == .rateLimited(resetAt: Harness.rateLimitReset, api: .rest))
        #expect(harness.shipyard.menu.refreshDelay == .paused(until: Harness.rateLimitReset, reason: .exhausted(.rest)))
        #expect(harness.runRows.map(\.number) == [40])
        #expect(harness.shipyard.menu.rateIndicator?.apis.first { $0.api == .rest }?.level == .exhausted)
    }

    // MARK: - Attention

    @Test("a failed run needs attention until seen, and again when a re-run fails; running and succeeded runs never do")
    func attention() async throws {
        let harness = try await Harness.started(
            config: runsConfig(extra: "[menu-bar]\ncount = \"per-kind\"\n"),
            graphQL: shopGraphQL(),
            runs: [shopRepository: [runsFixture()]]
        )
        #expect(harness.runRows.filter(\.needsAttention).map(\.number) == [41])
        #expect(harness.shipyard.menu.attention == AttentionCounts(pullRequests: 1, workflowRuns: 1))
        #expect(harness.shipyard.menu.menuBarLabel.text == "1 PR · 1 run")

        let failed = try #require(harness.runRows.first { $0.number == 41 })
        harness.shipyard.open(failed)
        #expect(harness.opener.opened == [failed.url])
        #expect(harness.shipyard.menu.attention == AttentionCounts(pullRequests: 1))

        // Re-run: running (no attention), then failed again (attention again).
        await harness.refresh(runs: shopRuns([run(41, "running", branch: "change-1", updatedAt: "2026-09-25T12:01:00Z")]))
        #expect(harness.runRows.map(\.state) == [.running])
        #expect(harness.shipyard.menu.attention.workflowRuns == 0)
        await harness.refresh(runs: shopRuns([run(41, "failure", branch: "change-1", updatedAt: "2026-09-25T12:03:00Z")]))
        #expect(harness.shipyard.menu.attention.workflowRuns == 1)

        // Mark all seen covers failed runs.
        harness.shipyard.markAllSeen(project: "shop")
        #expect(harness.shipyard.menu.attention.total == 0)
    }

    // MARK: - Notifications

    @Test("run.failed and run.succeeded are notified by rule, after a silent first sight, once each")
    func notifications() async throws {
        let config = runsConfig("""
            workflow-runs = { show = true }
            notifications = [{ event = "run.failed" }, { event = "run.succeeded", authors = ["me"] }]
            """)
        let harness = try await Harness.started(
            config: config,
            graphQL: shopGraphQL(),
            runs: [shopRepository: [shopRuns([run(40), run(39, "failure")])]]
        )
        // The first sight of the runs (a success and a failure) is silent.
        #expect(harness.notifier.posted.isEmpty)

        // A new run failed between two refreshes; another is running.
        await harness.refresh(runs: shopRuns([
            run(42, "running"),
            run(41, "failure", branch: "change-1", updatedAt: "2026-09-25T12:01:00Z"),
            run(40), run(39, "failure"),
        ]))
        let posted = try #require(harness.notifier.posted.first)
        #expect(harness.titles == ["shop · Run #41 failed"])
        #expect(posted.event == .runFailed)
        #expect(posted.body == "CI · change-1")
        #expect(posted.itemURL == URL(string: "https://github.com/yahyabedirhan/shop/actions/runs/9041"))

        // The running one succeeds.
        await harness.refresh(runs: shopRuns([
            run(42, updatedAt: "2026-09-25T12:03:00Z"),
            run(41, "failure", branch: "change-1", updatedAt: "2026-09-25T12:01:00Z"),
            run(40), run(39, "failure"),
        ]))
        #expect(harness.titles.last == "shop · Run #42 succeeded")

        // Nothing new: nothing posted again. A bot's success doesn't match `me`.
        var deploy = run(43, updatedAt: "2026-09-25T12:06:00Z")
        deploy.actor = "github-actions[bot]"
        deploy.actorType = "Bot"
        await harness.refresh(runs: shopRuns([
            deploy,
            run(42, updatedAt: "2026-09-25T12:03:00Z"),
            run(41, "failure", branch: "change-1", updatedAt: "2026-09-25T12:01:00Z"),
            run(40), run(39, "failure"),
        ]))
        #expect(harness.notifier.posted.count == 2)
    }

    @Test("turning runs on for a project lists them without a burst of notifications")
    func defaultRulesAndTurningOn() async throws {
        let harness = try await Harness.started(config: runsConfig(""), graphQL: shopGraphQL(), runs: [:])
        try harness.writeConfig(runsConfig("workflow-runs = { show = true }\nnotifications = [{ event = \"run.failed\" }]"))
        harness.stub.on("GET", WorkflowRunsResponse.url(shopRepository), shopRuns([run(40, "failure")]))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.runRows.map(\.number) == [40])
        #expect(harness.notifier.posted.isEmpty)

        await harness.refresh(runs: shopRuns([run(41, "failure"), run(40, "failure")]))
        #expect(harness.titles == ["shop · Run #41 failed"])
    }
}
