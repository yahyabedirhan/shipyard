import Foundation
import ShipyardCLISettings
import ShipyardCommand
import Testing

// The published `cli.toml` schema (`schema/cli.schema.json`) is the contract
// agents validate a machine's file against with `taplo check`, as
// `config.schema.json` is for `config.toml`.

private func loadCLISchema() throws -> [String: Any] {
    let data = try Data(contentsOf: repositoryRoot.appendingPathComponent("schema/cli.schema.json"))
    return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

/// The example `cli.toml` in a document: its ```toml block that names the
/// app machine.
private func cliExample(in path: String) throws -> String {
    let text = try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    return try #require(tomlBlocks(in: text).first { $0.contains("app-machine = ") }, "\(path) has no cli.toml example")
}

private let documents = ["skills/shipyard/references/notices.md", "docs/configuration.md"]

/// Every key `cli.toml` has, each set away from its default.
private let everyCLIKey = """
    #:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/cli.schema.json
    version = 1

    [notices]
    app-machine = "my-mac.tail1234.ts.net"
    app-scheme = "https"
    app-port = 443
    """

@Suite("cli.toml schema")
struct CLISettingsSchemaTests {
    @Test("the schema's $id, the code's URL and each document's #:schema line are one URL, and each example starts with it and version 1")
    func schemaLine() throws {
        let schema = try loadCLISchema()
        #expect(schema["$id"] as? String == CLISettings.schemaURL)
        for path in documents {
            let example = try cliExample(in: path)
            #expect(example.hasPrefix("#:schema \(CLISettings.schemaURL)\nversion = \(CLISettings.supportedVersion)\n"), "\(path)'s example: \(example)")
        }
    }

    @Test("the documents' examples and a file setting every key read and validate")
    func examplesValidate() throws {
        let schema = try loadCLISchema()
        for text in try documents.map(cliExample(in:)) + [everyCLIKey] {
            #expect(throws: Never.self) { try CLISettings.decode(text) }
            #expect(try violations(text, schema: schema) == [], "\(text)")
        }
    }

    @Test("the schema declares exactly the keys shipyard reads, with its choices and limits")
    func describesEveryKey() throws {
        let schema = try loadCLISchema()
        #expect(declaredPaths(schema, root: schema) == ["version", "notices", "notices.app-machine", "notices.app-scheme", "notices.app-port"])
        let properties = try #require(schema["properties"] as? [String: Any])
        #expect((properties["version"] as? [String: Any])?["enum"] as? [Int] == [CLISettings.supportedVersion])
        let notices = try #require((properties["notices"] as? [String: Any])?["properties"] as? [String: Any])
        #expect((notices["app-scheme"] as? [String: Any])?["enum"] as? [String] == NoticeSettings.Scheme.allCases.map(\.rawValue))
        let port = try #require(notices["app-port"] as? [String: Any])
        #expect(port["minimum"] as? Int == NoticePort.range.lowerBound)
        #expect(port["maximum"] as? Int == NoticePort.range.upperBound)
        #expect(port["default"] as? Int == NoticePort.default)
    }

    @Test("the schema rejects an unknown key, an unsupported version and a bad choice, as the reader does")
    func schemaRejects() throws {
        let bad = """
            version = 2
            colour = "red"
            [notices]
            app-machin = "mac"
            app-scheme = "ftp"
            app-port = 70000
            """
        #expect(throws: CLISettingsError.self) { try CLISettings.decode(bad) }
        #expect(Set(try violations(bad, schema: try loadCLISchema())) == [
            ".version: 2 not in enum",
            ": unknown key colour",
            ".notices: unknown key app-machin",
            ".notices.app-scheme: ftp not in enum",
            ".notices.app-port: above 65535",
        ])
    }
}
