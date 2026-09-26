import Foundation
@testable import ShipyardCore
import Testing

// Each preset is a whole configuration file onboarding writes and the skill
// shows. These check its text at the configuration seam: it reads with no
// warnings, passes the schema, and configures what the preset says.

private let picked = [
    NewProject(name: "hello-world", repositories: ["octocat/hello-world"]),
    NewProject(name: "spoon-knife", repositories: ["octocat/Spoon-Knife", "octocat/linguist"]),
]

private func decoded(_ preset: Preset, _ projects: [NewProject] = []) throws -> Configuration {
    try Configuration.decode(preset.text(projects: projects)).configuration
}

@Suite("Presets")
struct PresetTextTests {
    @Test("the three presets are listed in order, by name", arguments: [
        ("my-agents", Preset.Asks.repositories),
        ("incoming-contributions", .ownedOrRepositories),
        ("review-queue", .nothing),
    ])
    func listed(name: String, asks: Preset.Asks) throws {
        let preset = try #require(Preset.named(name))
        #expect(preset.asks == asks)
        #expect(!preset.title.isEmpty && !preset.summary.isEmpty)
        #expect(Preset.all.map(\.name) == ["my-agents", "incoming-contributions", "review-queue"])
        #expect(Preset.named("nothing-by-that-name") == nil)
    }

    @Test("every preset's text reads with no warnings and passes the schema, whatever onboarding picked",
          arguments: Preset.all, [[], [picked[0]], picked])
    func readsCleanly(preset: Preset, projects: [NewProject]) throws {
        let text = preset.text(projects: projects)
        #expect(text.hasPrefix("#:schema \(Configuration.schemaURL)\n"))
        do throws(ConfigError) {
            let result = try Configuration.decode(text)
            #expect(result.warnings.isEmpty, "warnings in:\n\(text)")
            // my-agents is only written once repositories are picked.
            #expect(result.configuration.hasProjects || (preset.asks == .repositories && projects.isEmpty))
        } catch {
            Issue.record("rejected: \(error)\nin:\n\(text)")
        }
        #expect(try violations(text, schema: loadSchema()) == [], "schema violations in:\n\(text)")
        // Its only live key outside tables is version, above every table.
        let firstTable = try #require(text.range(of: "\n["))
        let topLevel = text[..<firstTable.lowerBound].split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        #expect(topLevel == ["version = \(Configuration.supportedVersion)"])
    }

    @Test("my-agents shows issues, groups by kind and makes each picked project")
    func myAgents() throws {
        let config = try decoded(.myAgents, picked)
        #expect(config.defaults.issues.show)
        #expect(config.defaults.arrangement.groupBy == .kind)
        #expect(config.defaults.notifications == Configuration().defaults.notifications)
        #expect(config.projects.map(\.name) == ["hello-world", "spoon-knife"])
        #expect(config.projects.map(\.repositories) == [
            [.repository("octocat/hello-world")],
            [.repository("octocat/Spoon-Knife"), .repository("octocat/linguist")],
        ])
    }

    @Test("incoming-contributions lists others' items by repository, owned unless picked, and review requests anywhere")
    func incomingContributions() throws {
        let config = try decoded(.incomingContributions)
        #expect(config.projects.map(\.name) == ["Incoming", "Review requests"])
        #expect(config.projects.map(\.repositories) == [[.group(.owned)], [.anywhere]])

        let incoming = config.settings(for: config.projects[0])
        #expect(incoming.pullRequests.authors == AuthorFilter(hide: [.me, .bots]))
        #expect(incoming.issues.show)
        #expect(incoming.issues.authors == AuthorFilter(hide: [.me, .bots]))
        #expect(incoming.arrangement.groupBy == .repository)
        #expect(incoming.arrangement.subsections == true)
        #expect(incoming.notifications == [
            NotificationRule(event: .prOpened, authors: [.others]),
            NotificationRule(event: .issueOpened, authors: [.others]),
        ])

        let reviews = config.settings(for: config.projects[1])
        #expect(reviews.usesAnywhere)
        #expect(reviews.pullRequests.reviewRequested)
        #expect(!reviews.issues.show)
        #expect(reviews.arrangement.groupBy == .repository)
        #expect(reviews.notifications == [NotificationRule(event: .prReviewRequested)])

        // Picked repositories take owned's place.
        let chosen = try decoded(.incomingContributions, [NewProject(name: "Incoming", repositories: ["octocat/hello-world"])])
        #expect(chosen.projects.map(\.repositories) == [[.repository("octocat/hello-world")], [.anywhere]])
    }

    @Test("review-queue is one anywhere project of review requests, by repository, notifying each request")
    func reviewQueue() throws {
        // It asks for no repositories, and ignores any it's given.
        #expect(Preset.reviewQueue.text(projects: picked) == Preset.reviewQueue.text())
        let config = try decoded(.reviewQueue)
        #expect(config.projects.map(\.name) == ["Review queue"])
        let queue = config.settings(for: config.projects[0])
        #expect(queue.repositories == [.anywhere])
        #expect(queue.pullRequests.reviewRequested)
        #expect(!queue.issues.show && !queue.workflowRuns.show)
        #expect(queue.arrangement.groupBy == .repository)
        #expect(queue.arrangement.subsections == true)
        #expect(queue.notifications == [NotificationRule(event: .prReviewRequested)])
    }

    @Test("a project name with quotes is written as a TOML string")
    func escapesNames() throws {
        let config = try decoded(.myAgents, [NewProject(name: #"the "main" one"#, repositories: ["octocat/hello-world"])])
        #expect(config.projects.map(\.name) == [#"the "main" one"#])
    }
}
