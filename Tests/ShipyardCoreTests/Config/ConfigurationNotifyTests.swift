import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

/// `config.toml`'s `[notify]`: whether the app listens for notices from
/// the user's other machines, and on which port of 127.0.0.1.
@Suite("Configuration: notices from other machines")
struct ConfigurationNotifyTests {
    @Test("off by default, on the default port; listen and port are read")
    func read() throws {
        #expect(try #require(decoded("")).configuration.notify == Configuration.NotifySettings(listen: false, port: 47420))
        #expect(try #require(decoded("[notify]\nlisten = true\n")).configuration.notify == Configuration.NotifySettings(listen: true, port: 47420))
        #expect(try #require(decoded("[notify]\nlisten = true\nport = 50000\n")).configuration.notify
            == Configuration.NotifySettings(listen: true, port: 50000))
    }

    @Test("a port out of range, or a listen that isn't true or false, is rejected at its line")
    func rejected() {
        #expect(rejection("[notify]\nport = 0\n") == [ConfigIssue(line: 2, message: "`port` must be between 1 and 65535 (got 0)")])
        #expect(rejection("[notify]\nport = 65536\n") == [ConfigIssue(line: 2, message: "`port` must be between 1 and 65535 (got 65536)")])
        #expect(rejection("[notify]\nlisten = \"yes\"\n") == [ConfigIssue(line: 2, message: "`notify.listen` must be true or false")])
    }

    @Test("cli.toml's keys under [notify] are only a warning here, saying where they go")
    func cliKeys() throws {
        let warnings = try #require(decoded("[notify]\napp-machine = \"mac\"\n")).warnings
        #expect(warnings.count == 1)
        #expect(warnings.first?.message.hasPrefix("unknown setting `notify.app-machine`") == true)
    }

    @Test("the schema rejects what validation rejects")
    func schemaRejects() throws {
        let found = try violations("[notify]\nlisten = \"yes\"\nport = 0\napp-machine = \"mac\"\n", schema: try loadSchema())
        #expect(Set(found) == [
            ".notify.listen: expected boolean, got a string",
            ".notify.port: below 1",
            ".notify: unknown key app-machine",
        ])
    }
}
