import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private typealias Listed = RepositoryListResponse.Repository

/// Signed in with a stored token and, with `config`, that file; otherwise
/// the header `start()` creates. GraphQL answers `fetches` in order, and a
/// group lookup answers `groups`. Started: in `needsProjects`.
@MainActor
private func onboarding(
    config: String? = nil,
    groups: [StubHTTP.Answer] = [],
    fetches: [StubHTTP.Answer] = [PullRequestsResponse.answer([])]
) async throws -> Harness {
    let harness = try Harness(stored: "gho_stored", config: config)
    harness.stub.on(Harness.userURL, Harness.viewerAnswer)
    if !groups.isEmpty {
        harness.stub.on("POST", GitHubClient.graphQLURL, body: RepositoryListResponse.groupQuery, answers: groups)
    }
    harness.graphQL(fetches)
    await harness.shipyard.start()
    return harness
}

private func contents(_ harness: Harness) throws -> String {
    try String(contentsOf: harness.configURL, encoding: .utf8)
}

/// Whether `config-status.json` says the file was accepted.
private func accepted(_ harness: Harness) throws -> Bool? {
    let data = try Data(contentsOf: harness.stateDirectory.appendingPathComponent("config-status.json"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    return json?["accepted"] as? Bool
}

@Suite("Onboarding starts by choosing a preset")
@MainActor
struct PresetOnboardingTests {
    @Test("the header the app creates offers every preset, in onboarding's order")
    func offersPresets() async throws {
        let harness = try await onboarding()
        #expect(harness.shipyard.phase == .needsProjects)
        #expect(try contents(harness) == Configuration.header)
        #expect(harness.shipyard.presets.map(\.name) == ["my-agents", "incoming-contributions", "review-queue"])
    }

    @Test("review-queue needs nothing: the file is written and the menu follows the reload, without a restart")
    func reviewQueue() async throws {
        let harness = try await onboarding()

        let result = try await harness.shipyard.choosePreset(.reviewQueue)

        guard case .changed = result else {
            Issue.record("expected a change, got \(result)")
            return
        }
        #expect(try contents(harness) == Preset.reviewQueue.text())
        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.menu.sections.map(\.name) == ["Review queue"])
        #expect(harness.graphQLRequests.count == 1)
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.configWarnings.isEmpty)
        #expect(try accepted(harness) == true)
        // The file holds the preset now: onboarding won't offer another.
        #expect(harness.shipyard.presets.isEmpty)
    }

    @Test("incoming-contributions with all my repositories watches owned, plus the review requests from anywhere")
    func incomingOwned() async throws {
        let harness = try await onboarding(
            groups: [RepositoryListResponse.page([Listed("yabepa/shop")])],
            fetches: [PullRequestsResponse.answer([PullRequestsResponse("yabepa/shop", [])])]
        )
        var choice = PresetChoice(preset: .incomingContributions)
        let proceeded = choice.proceed()
        #expect(proceeded)

        try await harness.shipyard.choosePreset(.incomingContributions, projects: choice.projects(from: []))

        #expect(harness.shipyard.phase == .ready)
        #expect(harness.shipyard.menu.sections.map(\.name) == ["Incoming", "Review requests"])
        let projects = harness.shipyard.configStore.lastValid.projects
        #expect(projects.map(\.repositories) == [[.group(.owned)], [.anywhere]])
        #expect(harness.stub.requests("POST", GitHubClient.graphQLURL, body: RepositoryListResponse.groupQuery).count == 1)
    }

    @Test("my-agents and incoming-contributions with picking write the picked repositories")
    func pickedRepositories() async throws {
        let picked = [NewProject(name: "shop", repositories: ["yabepa/shop"])]
        let agents = try await onboarding()
        try await agents.shipyard.choosePreset(.myAgents, projects: picked)
        #expect(agents.shipyard.phase == .ready)
        #expect(agents.shipyard.menu.sections.map(\.name) == ["shop"])
        #expect(try contents(agents) == Preset.myAgents.text(projects: picked))

        let incoming = try await onboarding()
        var choice = PresetChoice(preset: .incomingContributions)
        choice.watchesOwned = false
        let proceeded = choice.proceed()
        #expect(!proceeded)
        try await incoming.shipyard.choosePreset(.incomingContributions, projects: choice.projects(from: picked))
        #expect(incoming.shipyard.menu.sections.map(\.name) == ["shop", "Review requests"])
    }

    @Test(
        "a file with any live setting besides version is never overwritten; onboarding shows the plain picker",
        arguments: [
            "[menu-bar]\ncount = \"attention\"\n",
            "version = 1\n[menu]\n",
            "launch-at-login = false\n",
            "version = 1\n[[defaults.notifications]]\nevent = \"pr.opened\"\n",
        ]
    )
    func refusesSettings(config: String) async throws {
        let harness = try await onboarding(config: config)
        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.shipyard.presets.isEmpty)

        await #expect(throws: ConfigError.self) {
            try await harness.shipyard.choosePreset(.reviewQueue)
        }

        #expect(try contents(harness) == config)
        #expect(harness.shipyard.phase == .needsProjects)
        #expect(harness.graphQLRequests.isEmpty)
    }

    @Test("a file that doesn't read is never overwritten")
    func refusesBrokenFile() async throws {
        let broken = "version = \n"
        let harness = try await onboarding(config: broken)
        #expect(harness.shipyard.presets.isEmpty)
        await #expect(throws: ConfigError.self) {
            try await harness.shipyard.choosePreset(.reviewQueue)
        }
        #expect(try contents(harness) == broken)
    }

    @Test("a setting saved after the last reload is still never overwritten, and the presets go")
    func refusesLateEdit() async throws {
        let harness = try await onboarding()
        #expect(!harness.shipyard.presets.isEmpty)
        let edited = Configuration.header + "\n[menu]\nlayout = \"tabs\"\n"
        try harness.writeConfig(edited)

        await #expect(throws: ConfigError.self) {
            try await harness.shipyard.choosePreset(.reviewQueue)
        }

        #expect(try contents(harness) == edited)
        #expect(harness.shipyard.presets.isEmpty)
        #expect(harness.shipyard.phase == .needsProjects)
    }

    @Test("comments, blank lines and version alone still take a preset; so does a missing file")
    func acceptsNothingLive() async throws {
        let harness = try await onboarding(config: "# mine\n\nversion = 1 # the format\n")
        #expect(!harness.shipyard.presets.isEmpty)
        try await harness.shipyard.choosePreset(.reviewQueue)
        #expect(harness.shipyard.phase == .ready)

        let store = ConfigStore(url: FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.toml"))
        store.reload()
        #expect(store.acceptsPreset)
        try store.writePreset(.reviewQueue)
        #expect(store.lastValid.projects.map(\.name) == ["Review queue"])
    }

    @Test("an invalid picked project writes nothing")
    func invalidProject() async throws {
        let harness = try await onboarding()
        await #expect(throws: ConfigError.self) {
            try await harness.shipyard.choosePreset(.myAgents, projects: [NewProject(name: "shop", repositories: ["not a slug"])])
        }
        await #expect(throws: ConfigError.self) {
            try await harness.shipyard.choosePreset(
                .incomingContributions,
                projects: [NewProject(name: "Review requests", repositories: ["yabepa/shop"])]
            )
        }
        #expect(try contents(harness) == Configuration.header)
        #expect(harness.shipyard.phase == .needsProjects)
    }
}
