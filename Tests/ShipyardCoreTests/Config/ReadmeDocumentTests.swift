import Foundation
@testable import ShipyardCore
import Testing

// The README is the project's front page. Its examples table puts each
// configuration beside the screenshot it produced; these tests keep every
// configuration decoding cleanly and saying what its screenshot shows.

private func readme() throws -> String {
    try String(contentsOf: repositoryRoot.appendingPathComponent("README.md"), encoding: .utf8)
}

/// The text between each `open` and the next `close` in `text`, in order.
private func spans(in text: String, from open: String, to close: String) -> [String] {
    var found: [String] = []
    var rest = text[...]
    while let start = rest.range(of: open), let end = rest[start.upperBound...].range(of: close) {
        found.append(String(rest[start.upperBound..<end.lowerBound]))
        rest = rest[end.upperBound...]
    }
    return found
}

/// A `<pre>` block's text as TOML: its HTML entities decoded.
private func unescaped(_ html: String) -> String {
    html.replacingOccurrences(of: "&lt;", with: "<")
        .replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"")
        .replacingOccurrences(of: "&amp;", with: "&")
}

/// Every TOML example: the ```toml fences and the examples table's `<pre lang="toml">` blocks.
private func tomlExamples(in text: String) -> [String] {
    spans(in: text, from: "```toml\n", to: "```") + spans(in: text, from: "<pre lang=\"toml\">\n", to: "</pre>").map(unescaped)
}

/// The examples table's rows, as the screenshot's path and the configuration beside it.
private func exampleRows(in text: String) -> [(image: String, toml: String)] {
    spans(in: text, from: "<tr>", to: "</tr>").compactMap { row in
        guard let toml = spans(in: row, from: "<pre lang=\"toml\">\n", to: "</pre>").first,
              let image = spans(in: row, from: "<img src=\"", to: "\"").first
        else { return nil }
        return (image, unescaped(toml))
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
            do throws(ConfigError) {
                let result = try Configuration.decode(example)
                #expect(result.warnings.isEmpty, "warnings in:\n\(example)")
            } catch {
                Issue.record("rejected: \(error)\nin:\n\(example)")
            }
            #expect(try violations(example, schema: schema) == [], "schema violations in:\n\(example)")
        }
    }

    @Test("each example's screenshot is in the repository, linked by a relative path")
    func screenshotsExist() throws {
        let rows = exampleRows(in: try readme())
        #expect(rows.count == 4)
        for row in rows {
            #expect(row.image.hasPrefix("docs/assets/"), "\(row.image) isn't a relative path into docs/assets")
            let path = repositoryRoot.appendingPathComponent(row.image).path
            #expect(FileManager.default.fileExists(atPath: path), "\(row.image) is missing")
        }
    }

    @Test("each example configures what its screenshot shows")
    func examplesMatchScreenshots() throws {
        let rows = exampleRows(in: try readme())
        var configurations: [String: Configuration] = [:]
        for row in rows {
            configurations[(row.image as NSString).lastPathComponent] = try Configuration.decode(row.toml).configuration
        }
        let twoRepositories = ["yahyabedirhan/shipyard", "yahyabedirhan/skills"]

        // The list layout, grouped by repository under subheaders, four rows a group.
        let subsections = try #require(configurations["repo-subsections-showfirst.png"])
        #expect(subsections.menu.layout == .list)
        #expect(subsections.defaults.arrangement == ArrangementSettings(groupBy: .repository, subsections: true, showFirst: 4))
        #expect(subsections.defaults.issues.show)
        #expect(subsections.projects.map(\.name) == ["shipyard"])
        #expect(subsections.projects.first?.repositories.map(\.description) == twoRepositories)

        // The same file in tabs.
        let tabs = try #require(configurations["tabs.png"])
        var listed = tabs
        listed.menu.layout = .list
        #expect(tabs.menu.layout == .tabs)
        #expect(listed == subsections)

        // The same file grouped by date, three rows a group.
        let date = try #require(configurations["date.png"])
        var byRepository = date
        byRepository.defaults.arrangement.groupBy = .repository
        byRepository.defaults.arrangement.showFirst = 4
        #expect(date.defaults.arrangement.groupBy == .date)
        #expect(date.defaults.arrangement.showFirst == 3)
        #expect(byRepository == subsections)

        // Onboarding's presets: a file holding only `version`, no projects.
        let presets = try #require(configurations["presets.png"])
        #expect(presets.projects.isEmpty)
        let presetsText = try #require(rows.first { $0.image.hasSuffix("/presets.png") }?.toml)
        #expect(Configuration.acceptsPreset(presetsText))
    }
}
