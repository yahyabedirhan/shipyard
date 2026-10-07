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

/// `shipyard config check` as an agent runs it after an edit: the same
/// verdict as the app's `config-status.json`, for `config.toml` and the
/// command's own `cli.toml`, without the app running.
@Suite("shipyard config check")
@MainActor
struct ConfigurationCheckTests {
    /// `cli.toml` beside the harness's `config.toml`, as the Mac's build finds it.
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

    @Test("an unknown subcommand or flag is a usage error")
    func usage() throws {
        let harness = try Harness(stored: nil, config: nil)

        #expect(harness.cli("config").status == CommandResult.usageStatus)
        #expect(harness.cli("config", "fix").status == CommandResult.usageStatus)
        #expect(harness.cli("config", "check", "--yaml").status == CommandResult.usageStatus)
        #expect(harness.cli("config", "check", "--help").status == 0)
    }
}
