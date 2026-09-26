import Foundation
@testable import ShipyardCore
import Testing

// `docs/configuration.md` tells maintainers how configuration works in the
// code and what to touch when a setting is added or changed. These tests
// keep its checklist naming every place a setting lives.

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
            "ConfigurationReader.swift", // the reader
            "Configuration.swift", // the model and its defaults
            "schema/config.schema.json", // the schema
            "Configuration.header", // the new-file header
            "skills/shipyard/SKILL.md", // the skill
            "README.md", // the README
            "ConfigurationTests", // the configuration seam
            "Harness", // the orchestrator seam
            "docs/low-level-design.md", // the design doc
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
