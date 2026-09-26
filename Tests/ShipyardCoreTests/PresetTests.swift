import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private typealias PR = PullRequestsResponse.PullRequest

/// An open pull request by `author`, waiting on the viewer's review.
private func waiting(_ number: Int, author: String = "octocat") -> PR {
    var pullRequest = PR(number)
    pullRequest.author = author
    pullRequest.checks = nil
    pullRequest.reviewRequests = ["yabepa"]
    return pullRequest
}

@Suite("A preset's file drives the app")
@MainActor
struct PresetTests {
    @Test("review-queue lists the pull requests waiting on the user's review, by repository, and notifies each new request")
    func reviewQueue() async throws {
        let harness = try await Harness.started(
            config: Preset.reviewQueue.text(),
            graphQL: PullRequestsResponse.answer([], reviewSearch: .pullRequests([("someone/else", waiting(5))], total: nil))
        )
        #expect(harness.shipyard.configError == nil)
        let queue = try #require(harness.section("Review queue"))
        #expect(queue.groups.map(\.title) == ["someone/else"])
        #expect(queue.groups.map(\.showsHeader) == [true])

        harness.graphQL([PullRequestsResponse.answer([], reviewSearch: .pullRequests(
            [("someone/else", waiting(5)), ("another/place", waiting(9, author: "renovate[bot]"))], total: nil
        ))])
        harness.clock.advance(by: 120)
        await harness.shipyard.refresh()

        let refreshed = try #require(harness.section("Review queue"))
        #expect(refreshed.groups.map(\.title) == ["another/place", "someone/else"])
        #expect(harness.notifier.posted.map(\.title) == ["Review queue · Review requested on PR #9"])
    }

    @Test("my-agents makes a project per picked repository, issues shown")
    func myAgents() async throws {
        let harness = try await Harness.started(config: Preset.myAgents.text(projects: [
            NewProject(name: "shop", repositories: ["yabepa/shop"]),
        ]))
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.menu.sections.map(\.name) == ["shop"])
        #expect(harness.shipyard.configStore.lastValid.defaults.issues.show)
    }
}
