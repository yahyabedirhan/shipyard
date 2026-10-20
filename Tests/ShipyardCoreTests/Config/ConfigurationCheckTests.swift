import Foundation
import ShipyardCLISettings
import ShipyardCommand
import ShipyardConfig
@testable import ShipyardCore
import Testing

private let projects = """
    [[projects]]
    name = "shop"
    repositories = ["o/r"]

    """

@Suite("shipyard config check")
@MainActor
struct ConfigurationCheckTests {
    func writeCLISettings(_ harness: Harness, _ text: String) throws {
        try Data(text.utf8).write(to: CLISettingsFile.beside(config: harness.configURL).url)
    }

    @Test("an accepted file prints accepted and each warning, and exits 0")
    func accepted() throws {
        let harness = try Harness(stored: nil, config: "refresh-interval-second = 300\n\n" + projects)

        let result = harness.cli("config", "check")

        #expect(result.status == 0)
        #expect(result.error == "")
        #expect(result.output.contains("\(harness.configURL.path): accepted\n"))
        #expect(result.output.contains("  warning: config.toml line 1: unknown setting `refresh-interval-second`"))
    }

    @Test("a file with problems prints each problem with its line, and exits 1")
    func rejected() throws {
        let harness = try Harness(stored: nil, config: "launch-at-login = \"yes\"\nhide-authors = 3\n\n" + projects)

        let result = harness.cli("config", "check")

        #expect(result.status == CommandResult.failedStatus)
        #expect(result.output.contains("\(harness.configURL.path): rejected\n"))
        let problems = result.output.split(separator: "\n").filter { $0.hasPrefix("  problem: ") }
        #expect(problems.count >= 2)
        #expect(problems.first?.hasPrefix("  problem: config.toml line 1: `launch-at-login`") == true)
        #expect(problems.dropFirst().first?.hasPrefix("  problem: config.toml line 2: `hide-authors`") == true)
    }

    @Test("missing files are the defaults, accepted")
    func missing() throws {
        let harness = try Harness(stored: nil, config: nil)
        let cliURL = CLISettingsFile.beside(config: harness.configURL).url

        let result = harness.cli("config", "check")

        #expect(result.status == 0)
        #expect(result.output == """
            \(harness.configURL.path): accepted (no file: the defaults)
            \(cliURL.path): accepted (no file: the defaults)

            """)
    }

    @Test("cli.toml gets a result of its own, and its problems fail the check")
    func cliSettingsProblem() throws {
        let harness = try Harness(stored: nil, config: projects)
        try writeCLISettings(harness, "[notices]\napp-machin = \"my-mac\"\n")
        let cliURL = CLISettingsFile.beside(config: harness.configURL).url

        let result = harness.cli("config", "check")

        #expect(result.status == CommandResult.failedStatus)
        #expect(result.output.contains("\(harness.configURL.path): accepted\n"))
        #expect(result.output.contains("\(cliURL.path): rejected\n  problem: cli.toml: unknown setting `notices.app-machin`"))
    }

    @Test("--json prints config-status.json's fields for each file, so an agent can compare them")
    func json() async throws {
        let harness = try await Harness.started(config: projects, graphQL: Harness.fixture("graphql-pull-requests.json"))
        try harness.writeConfig("launch-at-login = \"yes\"\n\n" + projects)
        await harness.shipyard.reloadConfiguration()
        let recorded = try Data(contentsOf: harness.stateDirectory.appendingPathComponent(ConfigStatusStore.fileName))

        let result = harness.cli("config", "check", "--json")

        #expect(result.status == CommandResult.failedStatus)
        let checked = try #require(try JSONSerialization.jsonObject(with: Data(result.output.utf8)) as? [String: Any])
        let config = try #require(checked["config.toml"] as? NSDictionary)
        let status = try #require(try JSONSerialization.jsonObject(with: recorded) as? NSDictionary)
        #expect(config == status)
        let cli = try #require(checked["cli.toml"] as? [String: Any])
        #expect(cli["accepted"] as? Bool == true)
        #expect(cli["configModified"] is NSNull)
        #expect(cli["config"] as? String == CLISettingsFile.beside(config: harness.configURL).url.path)
    }

    @Test("an unknown theme is a problem on its line, in text and in --json, and exits 1; a built-in one is accepted")
    func theme() throws {
        let harness = try Harness(stored: nil, config: "theme = \"Papr\"\n\n" + projects)

        let text = harness.cli("config", "check")
        #expect(text.status == CommandResult.failedStatus)
        #expect(text.output.contains("""
            \(harness.configURL.path): rejected
              problem: config.toml line 1: unknown theme `Papr` (did you mean `Paper`?)

            """))

        let json = harness.cli("config", "check", "--json")
        #expect(json.status == CommandResult.failedStatus)
        let checked = try #require(try JSONSerialization.jsonObject(with: Data(json.output.utf8)) as? [String: Any])
        let config = try #require(checked["config.toml"] as? [String: Any])
        #expect(config["accepted"] as? Bool == false)
        let problems = try #require(config["problems"] as? [[String: Any]])
        #expect(problems.count == 1)
        #expect(problems.first?["line"] as? Int == 1)
        #expect(problems.first?["message"] as? String == "unknown theme `Papr` (did you mean `Paper`?)")
        #expect(problems.first?["banner"] as? String == "config.toml line 1: unknown theme `Papr` (did you mean `Paper`?)")

        try harness.writeConfig("theme = \"paper\"\n\n" + projects)
        #expect(harness.cli("config", "check").status == 0)
    }

    @Test("an unknown subcommand or flag is a usage error")
    func usage() throws {
        let harness = try Harness(stored: nil, config: nil)

        #expect(harness.cli("config").status == CommandResult.usageStatus)
        #expect(harness.cli("config", "fix").status == CommandResult.usageStatus)
        #expect(harness.cli("config", "check", "--yaml").status == CommandResult.usageStatus)
        #expect(harness.cli("config", "check", "--help").status == 0)
    }
}
