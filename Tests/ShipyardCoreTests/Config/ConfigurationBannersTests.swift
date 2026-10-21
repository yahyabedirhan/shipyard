import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

@Suite("Configuration: banners")
struct ConfigurationBannersTests {
    @Test("an hour by default; snooze-duration is read as a duration")
    func read() throws {
        #expect(try #require(decoded("")).configuration.banners == Configuration.BannerSettings(snoozeDuration: 3600))
        for (text, seconds) in [("10s", 10.0), ("30m", 1800)] {
            let result = try #require(decoded("version = 1\n[banners]\nsnooze-duration = \"\(text)\"\n"))
            #expect(result.configuration.banners == Configuration.BannerSettings(snoozeDuration: seconds))
            #expect(result.warnings == [])
        }
    }

    @Test("a snooze-duration of 0, or one that isn't a duration, is rejected at its line")
    func rejected() {
        #expect(rejection("[banners]\nsnooze-duration = \"0\"\n")
            == [ConfigurationIssue(line: 2, message: "`snooze-duration` must be longer than 0, such as \"1h\" or \"10s\"")])
        #expect(rejection("[banners]\nsnooze-duration = \"10sec\"\n").first?.message.hasPrefix("`snooze-duration` must be a whole number and one unit") == true)
    }

    @Test("the schema rejects what validation rejects")
    func schemaRejects() throws {
        let found = try violations("[banners]\nsnooze-duration = \"0\"\nlength = 3\n", schema: try loadSchema())
        #expect(Set(found) == [
            ".banners.snooze-duration: 0 doesn't match ^[1-9][0-9]*[smhd]$",
            ".banners: unknown key length",
        ])
    }
}
