import Foundation
@testable import ShipyardCore
import Testing

private let projects = """
    [[projects]]
    name = "shop"
    repositories = ["o/r"]

    """

/// `config-status.json` as an agent reads it: plain JSON, no Swift types.
private struct Record {
    let json: [String: Any]

    init(_ harness: Harness) throws {
        let data = try Data(contentsOf: harness.stateDirectory.appendingPathComponent("config-status.json"))
        json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    var accepted: Bool? { json["accepted"] as? Bool }
    var checked: String? { json["checked"] as? String }
    var configModified: Any? { json["configModified"] }
    var config: String? { json["config"] as? String }
    var problems: [[String: Any]] { json["problems"] as? [[String: Any]] ?? [] }
    var warnings: [[String: Any]] { json["warnings"] as? [[String: Any]] ?? [] }
}

/// Sets the configuration file's modification time, as a save would.
private func touch(_ harness: Harness, at modified: Date) throws {
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: harness.configURL.path)
}

@Suite("Configuration status record")
@MainActor
struct ConfigStatusTests {
    @Test("an accepted file is recorded with when it was checked and the modification time it read")
    func acceptedAtStart() async throws {
        let harness = try Harness(stored: "gho_stored", config: projects)
        try touch(harness, at: date("2026-09-25T11:59:58Z").addingTimeInterval(0.75))
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([try Harness.fixture("graphql-pull-requests.json")])

        await harness.shipyard.start()

        let record = try Record(harness)
        #expect(record.json["version"] as? Int == 1)
        #expect(record.accepted == true)
        #expect(record.checked == "2026-09-25T12:00:00Z")
        // Whole seconds, as `date -u -r config.toml +%Y-%m-%dT%H:%M:%SZ` prints it.
        #expect(record.configModified as? String == "2026-09-25T11:59:58Z")
        #expect(record.config == harness.configURL.path)
        #expect(record.problems.isEmpty)
        #expect(record.warnings.isEmpty)
    }

    @Test("a rejected edit is recorded with each problem's line and the banner's text, until the file is fixed")
    func rejectedThenFixed() async throws {
        let harness = try await Harness.started(config: projects, graphQL: Harness.fixture("graphql-pull-requests.json"))

        try harness.writeConfig("refresh-interval-seconds = 5\n\n" + projects + "[[projects]]\nname = \"shop\"\nrepositories = [\"o/s\"]\n")
        try touch(harness, at: date("2026-09-25T12:05:00Z"))
        harness.clock.set(date("2026-09-25T12:05:01Z"))
        await harness.shipyard.reloadConfiguration()

        let rejected = try Record(harness)
        let error = try #require(harness.shipyard.configError)
        #expect(rejected.accepted == false)
        #expect(rejected.checked == "2026-09-25T12:05:01Z")
        #expect(rejected.configModified as? String == "2026-09-25T12:05:00Z")
        #expect(rejected.problems.count == error.issues.count)
        #expect(rejected.problems.count >= 2)
        let bannerLines = PanelText.configError(error).components(separatedBy: "\n").dropLast()
        for (problem, (issue, banner)) in zip(rejected.problems, zip(error.issues, bannerLines)) {
            #expect(problem["line"] as? Int == issue.line)
            #expect(problem["message"] as? String == issue.message)
            #expect(problem["banner"] as? String == banner)
        }
        #expect(rejected.problems.first?["line"] as? Int == 1)

        try harness.writeConfig(projects)
        try touch(harness, at: date("2026-09-25T12:06:00Z"))
        harness.clock.set(date("2026-09-25T12:06:01Z"))
        await harness.shipyard.reloadConfiguration()

        let fixed = try Record(harness)
        #expect(fixed.accepted == true)
        #expect(fixed.configModified as? String == "2026-09-25T12:06:00Z")
        #expect(fixed.problems.isEmpty)
    }

    @Test("a save that changes nothing the app uses is still recorded")
    func unchangedIsRecorded() async throws {
        let harness = try await Harness.started(config: projects, graphQL: Harness.fixture("graphql-pull-requests.json"))

        try harness.writeConfig("# a comment\n" + projects)
        try touch(harness, at: date("2026-09-25T12:10:00Z"))
        let result = await harness.shipyard.reloadConfiguration()

        #expect(result == .unchanged)
        let record = try Record(harness)
        #expect(record.accepted == true)
        #expect(record.configModified as? String == "2026-09-25T12:10:00Z")
    }

    @Test("an unknown setting is accepted and recorded as a warning with its line")
    func warningRecorded() async throws {
        let harness = try await Harness.started(config: projects, graphQL: Harness.fixture("graphql-pull-requests.json"))

        try harness.writeConfig("refresh-interval-second = 300\n\n" + projects)
        await harness.shipyard.reloadConfiguration()

        let record = try Record(harness)
        #expect(record.accepted == true)
        #expect(record.problems.isEmpty)
        let warning = try #require(record.warnings.first)
        #expect(warning["line"] as? Int == 1)
        #expect(warning["banner"] as? String == PanelText.configWarnings(harness.shipyard.configWarnings))
    }

    @Test("a file deleted while running is accepted as the defaults, with no modification time")
    func missingFile() async throws {
        let harness = try Harness(stored: nil, config: nil)
        await harness.shipyard.start()

        // Start creates a missing file, so delete it afterwards.
        try FileManager.default.removeItem(at: harness.configURL)
        await harness.shipyard.reloadConfiguration()

        let record = try Record(harness)
        #expect(record.accepted == true)
        #expect(record.configModified is NSNull)
        #expect(record.problems.isEmpty)
    }

    @Test("adding projects from the picker records the reload that follows")
    func addProjectsRecorded() async throws {
        let harness = try Harness(stored: "gho_stored", config: nil)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        await harness.shipyard.start()
        harness.graphQL([try Harness.fixture("graphql-pull-requests.json")])

        try await harness.shipyard.addProjects([NewProject(name: "shop", repositories: ["o/r"])])

        let record = try Record(harness)
        #expect(record.accepted == true)
        #expect(record.configModified is String)
    }

    @Test("a problem without a line records its line as null")
    func problemWithoutLine() throws {
        let status = ConfigStatus(
            checked: date("2026-09-25T12:00:00Z"),
            config: URL(fileURLWithPath: "/tmp/config.toml"),
            configModified: nil,
            error: ConfigError([ConfigIssue(line: nil, message: "the file isn't UTF-8 text")]),
            warnings: []
        )
        let json = try #require(try JSONSerialization.jsonObject(with: ConfigStatusStore.encode(status)) as? [String: Any])
        let problem = try #require((json["problems"] as? [[String: Any]])?.first)
        #expect(problem["line"] is NSNull)
        #expect(problem["banner"] as? String == "config.toml: the file isn't UTF-8 text")
        #expect(json["accepted"] as? Bool == false)
    }
}
