import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

/// `[remote] machines`: the other machines whose pings the menu lists, by
/// their Herdr labels.
@Suite("Configuration: remote machines")
struct ConfigurationRemoteTests {
    @Test("no machines in an empty file; labels are read in order, trimmed")
    func machines() throws {
        #expect(try #require(decoded("")).configuration.remote.machines == [])
        let config = try #require(decoded("[remote]\nmachines = [\"netcup-vps\", \" My VPS \"]\n")).configuration
        #expect(config.remote.machines == ["netcup-vps", "My VPS"])
    }

    @Test("a label starting with -, an empty one, or one listed twice is rejected at its line")
    func badLabels() {
        #expect(rejection("[remote]\nmachines = [\"--help\"]\n") == [
            ConfigurationIssue(line: 2, message: "`--help` isn't a Herdr machine label: a label can't start with `-`"),
        ])
        #expect(rejection("[remote]\nmachines = [\" \"]\n") == [
            ConfigurationIssue(line: 2, message: "a machine in `machines` is named by its Herdr label, which can't be empty"),
        ])
        #expect(rejection("[remote]\nmachines = [\"vps\", \"vps \"]\n") == [
            ConfigurationIssue(line: 2, message: "`vps` is listed twice in `machines`"),
        ])
        #expect(rejection("[remote]\nmachines = \"vps\"\n") == [ConfigurationIssue(line: 2, message: "`remote.machines` must be a list of strings")])
    }

    @Test("a machine can't share a project's slug or title, since its section is named after it")
    func projectName() {
        let issues = rejection("""
            [remote]
            machines = ["shop"]

            [[projects]]
            slug = "shop"
            repositories = ["o/shop"]
            """)
        #expect(issues == [
            ConfigurationIssue(line: 2, message: "`shop` is both a machine in `[remote] machines` and a project's slug or title; rename the project, since a machine's pings list under its label"),
        ])
    }

    @Test("an unknown key under [remote] is only a warning")
    func unknownKey() throws {
        let warnings = try #require(decoded("version = 1\n[remote]\nmachine = [\"vps\"]\n")).warnings
        #expect(warnings == [ConfigurationIssue(line: 3, message: "unknown setting `remote.machine` (ignored; did you mean `machines`?)")])
    }

    @Test("the schema rejects what validation rejects")
    func schemaRejects() throws {
        let found = try violations("[remote]\nmachines = [\" -x\", \"vps\", \"vps\", \" \", \"My VPS\"]\n", schema: try loadSchema())
        #expect(Set(found) == [
            ".remote.machines[0]:  -x doesn't match ^\\s*[^\\s-]",
            ".remote.machines: items not unique",
            ".remote.machines[3]:   doesn't match ^\\s*[^\\s-]",
        ])
    }
}
