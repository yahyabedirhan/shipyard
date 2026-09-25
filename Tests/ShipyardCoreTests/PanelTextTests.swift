import Foundation
@testable import ShipyardCore
import Testing

@Suite("Panel text")
struct PanelTextTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    @Test("a row's age is short: now, minutes, hours, days", arguments: [
        (0.0, "now"),
        (59, "now"),
        (60, "1m"),
        (59 * 60 + 59, "59m"),
        (3600, "1h"),
        (23 * 3600 + 3599, "23h"),
        (86_400, "1d"),
        (40 * 86_400, "40d"),
    ] as [(TimeInterval, String)])
    func age(seconds: TimeInterval, text: String) {
        #expect(PanelText.age(seconds) == text)
    }

    @Test("last updated counts minutes, then hours, then days; nothing before the first refresh")
    func lastUpdated() {
        #expect(PanelText.lastUpdated(nil, now: now) == nil)
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-30), now: now) == "Last updated just now")
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-60), now: now) == "Last updated 1 min ago")
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-5 * 60 - 10), now: now) == "Last updated 5 min ago")
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-2 * 3600), now: now) == "Last updated 2 h ago")
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-3 * 86_400), now: now) == "Last updated 3 d ago")
        // A clock that went back doesn't say "in the future".
        #expect(PanelText.lastUpdated(now.addingTimeInterval(60), now: now) == "Last updated just now")
    }

    @Test("a configuration error names the file and line, and says the last valid one is used")
    func configError() {
        let error = ConfigError([
            ConfigIssue(line: 14, message: "unknown event `pr.openned` (did you mean `pr.opened`?)"),
            ConfigIssue(line: nil, message: "can't read the file"),
        ])

        #expect(PanelText.configError(error) == """
            config.toml line 14: unknown event `pr.openned` (did you mean `pr.opened`?)
            config.toml: can't read the file
            Using the last valid configuration.
            """)
    }

    @Test("a failed refresh says why", arguments: [
        (GitHubError.network("The Internet connection appears to be offline."),
         "Couldn't reach GitHub: The Internet connection appears to be offline."),
        (.http(502), "GitHub answered with HTTP 502."),
        (.malformed, "GitHub's answer couldn't be read."),
        (.graphQL("Something went wrong"), "GitHub: Something went wrong"),
        (.unauthorized, "GitHub rejected the token."),
        (.rateLimited(resetAt: Date(timeIntervalSince1970: 0), api: .graphql), "The GraphQL rate limit ran out."),
        (.secondaryLimit(retryAfter: 60), "GitHub asked shipyard to slow down."),
    ] as [(GitHubError, String)])
    func fetchError(error: GitHubError, text: String) {
        #expect(PanelText.fetchError(error) == text)
    }
}
