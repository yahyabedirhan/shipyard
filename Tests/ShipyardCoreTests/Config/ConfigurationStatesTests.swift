import Foundation
@testable import ShipyardCore
import Testing

@Suite("Configuration: states")
struct ConfigurationStatesTests {
    @Test("each kind lists every one of its states by default")
    func everyStateByDefault() {
        let defaults = Configuration().defaults
        #expect(defaults.pullRequests.states == [.open, .merged, .closed])
        #expect(defaults.issues.states == [.open, .closed])
        #expect(defaults.workflowRuns.states == [.inProgress, .failed, .succeeded])
    }

    @Test("a project's states replace the defaults' for that kind, and leave the other kinds' alone")
    func projectReplacesDefaults() throws {
        let config = try #require(decoded("""
            [defaults.pull-requests]
            states = ["open", "merged"]

            [defaults.workflow-runs]
            states = ["failed"]

            [[projects]]
            name = "a"
            repositories = ["o/a"]
            pull-requests = { states = ["open"] }
            issues = { states = ["open"] }

            [[projects]]
            name = "b"
            repositories = ["o/b"]
            """)).configuration
        let a = config.settings(for: config.projects[0])
        let b = config.settings(for: config.projects[1])
        #expect(a.pullRequests.states == [.open])
        #expect(a.issues.states == [.open])
        #expect(a.workflowRuns.states == [.failed])
        #expect(b.pullRequests.states == [.open, .merged])
        #expect(b.issues.states == [.open, .closed])
        #expect(b.states(of: .workflowRun) == [.failed])
    }

    @Test("an unknown state is rejected on its line, with the nearest one the kind takes")
    func unknownState() {
        #expect(rejection("""
            [defaults.pull-requests]
            states = ["open", "merge"]
            """) == [ConfigIssue(line: 2, message: "unknown pull request state `merge` (did you mean `merged`?)")])
        #expect(rejection("""
            [[projects]]
            name = "a"
            repositories = ["o/a"]
            workflow-runs = { states = [
              "failed",
              "in_progress",
            ] }
            """) == [ConfigIssue(line: 6, message: "unknown workflow run state `in_progress` (did you mean `in-progress`?)")])
    }

    @Test("another kind's state is rejected, with the ones this kind takes")
    func anotherKindsState() {
        #expect(rejection("""
            [defaults.issues]
            states = ["merged"]

            [defaults.workflow-runs]
            states = ["open"]
            """) == [
                ConfigIssue(line: 2, message: "unknown issue state `merged` (expected `open`, `closed`)"),
                ConfigIssue(line: 5, message: "unknown workflow run state `open` (expected `in-progress`, `failed`, `succeeded`)"),
            ])
    }

    @Test("states is a list of strings")
    func statesShape() {
        #expect(rejection("[defaults.issues]\nstates = \"open\"\n")
            == [ConfigIssue(line: 2, message: "`defaults.issues.states` must be a list of strings")])
    }

    @Test("an empty list lists none of that kind's items")
    func emptyList() throws {
        let config = try #require(decoded("[defaults.issues]\nstates = []\n")).configuration
        #expect(config.defaults.issues.states.isEmpty)
    }
}
