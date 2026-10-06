import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

/// `config.toml`'s `[banners]`: how long a dismissed panel banner stays
/// hidden.
@Suite("Configuration: banners")
struct ConfigurationBannersTests {
    @Test("an hour by default; snooze is read as a window")
    func read() throws {
        #expect(try #require(decoded("")).configuration.banners == Configuration.BannerSettings(snooze: 3600))
        #expect(try #require(decoded("[banners]\nsnooze = \"10s\"\n")).configuration.banners == Configuration.BannerSettings(snooze: 10))
        #expect(try #require(decoded("[banners]\nsnooze = \"30m\"\n")).configuration.banners == Configuration.BannerSettings(snooze: 1800))
    }

    @Test("a snooze of 0, or one that isn't a window, is rejected at its line")
    func rejected() {
        #expect(rejection("[banners]\nsnooze = \"0\"\n") == [ConfigIssue(line: 2, message: "`snooze` must be longer than 0, such as \"1h\" or \"10s\"")])
        #expect(rejection("[banners]\nsnooze = \"10sec\"\n").first?.message.hasPrefix("`snooze` must be a whole number and one unit") == true)
    }

    @Test("the schema rejects what validation rejects")
    func schemaRejects() throws {
        let found = try violations("[banners]\nsnooze = \"0\"\nlength = 3\n", schema: try loadSchema())
        #expect(Set(found) == [
            ".banners.snooze: 0 doesn't match ^[1-9][0-9]*[smhd]$",
            ".banners: unknown key length",
        ])
    }
}
