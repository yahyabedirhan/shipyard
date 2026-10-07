import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

/// `config.toml`'s `[notices]`: whether the app listens for notices from
/// the user's other machines, and on which port of 127.0.0.1.
@Suite("Configuration: notices from other machines")
struct ConfigurationNoticesTests {
    @Test("off by default, on the default port; listen and port are read")
    func read() throws {
        #expect(try #require(decoded("")).configuration.notices == Configuration.NoticeSettings(listen: false, port: 47420))
        #expect(try #require(decoded("[notices]\nlisten = true\n")).configuration.notices == Configuration.NoticeSettings(listen: true, port: 47420))
        #expect(try #require(decoded("[notices]\nlisten = true\nport = 50000\n")).configuration.notices
            == Configuration.NoticeSettings(listen: true, port: 50000))
    }

    @Test("a port out of range, or a listen that isn't true or false, is rejected at its line")
    func rejected() {
        #expect(rejection("[notices]\nport = 0\n") == [ConfigurationIssue(line: 2, message: "`port` must be between 1 and 65535 (got 0)")])
        #expect(rejection("[notices]\nport = 65536\n") == [ConfigurationIssue(line: 2, message: "`port` must be between 1 and 65535 (got 65536)")])
        #expect(rejection("[notices]\nlisten = \"yes\"\n") == [ConfigurationIssue(line: 2, message: "`notices.listen` must be true or false")])
    }

    @Test("cli.toml's keys under [notices] are only a warning here, saying where they go")
    func cliKeys() throws {
        let warnings = try #require(decoded("[notices]\napp-machine = \"mac\"\n")).warnings
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.hasPrefix("unknown setting `notices.app-machine`") == true)
    }

    @Test("the schema rejects what validation rejects")
    func schemaRejects() throws {
        let found = try violations("[notices]\nlisten = \"yes\"\nport = 0\napp-machine = \"mac\"\n", schema: try loadSchema())
        #expect(Set(found) == [
            ".notices.listen: expected boolean, got a string",
            ".notices.port: below 1",
            ".notices: unknown key app-machine",
        ])
    }
}
