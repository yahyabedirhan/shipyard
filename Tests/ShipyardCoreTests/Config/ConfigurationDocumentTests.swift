import Foundation
@testable import ShipyardCore
import Testing

private func document() throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent("docs/configuration.md"), encoding: .utf8)
}

@Suite("Configuration maintainer document")
struct ConfigurationDocumentTests {
    @Test("the checklist for a setting names every place it lives")
    func checklist() throws {
        let text = try document()
        let start = try #require(text.range(of: "## Adding or changing a setting")).upperBound
        let steps = String(text[start...])
        for place in [
            "ConfigurationReader.swift",
            "Configuration.swift",
            "schema/config.schema.json",
            "Configuration.header",
            "skills/shipyard/SKILL.md",
            "README.md",
            "ConfigurationTests",
            "Harness",
            "docs/low-level-design.md",
        ] {
            #expect(steps.contains("`\(place)`"), "the checklist doesn't name `\(place)`")
        }
    }

    @Test("it links the design and the decision instead of repeating them")
    func links() throws {
        let text = try document()
        #expect(text.contains("](low-level-design.md"))
        #expect(text.contains("](adr/0001-configuration-is-a-toml-file-agents-edit.md)"))
    }
}
