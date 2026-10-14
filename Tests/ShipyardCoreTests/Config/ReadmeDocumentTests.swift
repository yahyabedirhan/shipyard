import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

private func readme() throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent("README.md"), encoding: .utf8)
}

private func spans(in text: String, from open: String, to close: String) -> [String] {
    var found: [String] = []
    var rest = text[...]
    while let start = rest.range(of: open), let end = rest[start.upperBound...].range(of: close) {
        found.append(String(rest[start.upperBound..<end.lowerBound]))
        rest = rest[end.upperBound...]
    }
    return found
}

private func tomlExamples(in text: String) -> [String] {
    spans(in: text, from: "```toml\n", to: "```")
}

private func examples(in text: String) throws -> [(image: String, toml: String)] {
    let start = try #require(text.range(of: "\n## Examples\n")).upperBound
    let end = text[start...].range(of: "\n## ")?.lowerBound ?? text.endIndex
    return text[start..<end].components(separatedBy: "```toml\n").dropFirst().compactMap { example in
        guard let fence = example.range(of: "```"),
              let image = spans(in: String(example[fence.upperBound...]), from: "<img src=\"", to: "\"").first
        else { return nil }
        return (image, String(example[..<fence.lowerBound]))
    }
}

@Suite("README")
struct ReadmeDocumentTests {
    @Test("every TOML example decodes cleanly and validates against the schema")
    func examplesDecode() throws {
        let examples = tomlExamples(in: try readme())
        #expect(examples.count >= 4)
        let schema = try loadSchema()
        for example in examples {
            do throws(ConfigurationError) {
                let result = try Configuration.decode(asFile(example))
                #expect(result.warnings.isEmpty, "warnings in:\n\(example)")
            } catch {
                Issue.record("rejected: \(error)\nin:\n\(example)")
            }
            #expect(try violations(example, schema: schema) == [], "schema violations in:\n\(example)")
        }
    }

    @Test("each example's screenshot is in the repository, linked by a relative path")
    func screenshotsExist() throws {
        let rows = try examples(in: try readme())
        #expect(rows.count == 4)
        for row in rows {
            #expect(row.image.hasPrefix("assets/screenshots/"), "\(row.image) isn't a relative path into assets/screenshots")
            let path = repositoryRoot.appendingPathComponent(row.image).path
            #expect(FileManager.default.fileExists(atPath: path), "\(row.image) is missing")
        }
    }

    @Test("each example configures what its screenshot shows")
    func examplesMatchScreenshots() throws {
        let rows = try examples(in: try readme())
        var configurations: [String: Configuration] = [:]
        for row in rows {
            configurations[(row.image as NSString).lastPathComponent] = try Configuration.decode(row.toml).configuration
        }
        let twoRepositories = ["yahyabedirhan/shipyard", "yahyabedirhan/skills"]

        let subsections = try #require(configurations["repo-subsections-showfirst.png"])
        #expect(subsections.menu.layout == .list)
        #expect(subsections.defaults.arrangement == ArrangementSettings(groupBy: .repository, subsections: true, showFirst: 4))
        #expect(subsections.defaults.issues.show)
        #expect(subsections.projects.map(\.slug) == ["shipyard"])
        #expect(subsections.projects.first?.repositories.map(\.description) == twoRepositories)

        let tabs = try #require(configurations["tabs.png"])
        var listed = tabs
        listed.menu.layout = .list
        #expect(tabs.menu.layout == .tabs)
        #expect(listed == subsections)

        let date = try #require(configurations["date.png"])
        var byRepository = date
        byRepository.defaults.arrangement.groupBy = .repository
        byRepository.defaults.arrangement.showFirst = 4
        #expect(date.defaults.arrangement.groupBy == .date)
        #expect(date.defaults.arrangement.showFirst == 3)
        #expect(byRepository == subsections)

        let presets = try #require(configurations["presets.png"])
        #expect(presets.projects.isEmpty)
        let presetsText = try #require(rows.first { $0.image.hasSuffix("/presets.png") }?.toml)
        #expect(Configuration.acceptsPreset(presetsText))
    }
}
