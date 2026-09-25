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

    // MARK: - The connect screen

    @Test("with no gh token the connect screen says to install gh and run gh auth login")
    func connectNoToken() {
        let text = PanelText.connect(.noToken)
        #expect(text.title == "Connect to GitHub")
        #expect(text.message.contains("GitHub CLI"))
        #expect(text.command == "gh auth login")
        #expect(text.suggestsInstallingGh)
        #expect(PanelText.installGh.contains("https://cli.github.com"))
        #expect(PanelText.installGh.contains("brew install gh"))
    }

    @Test("while shipyard looks for gh's token the panel says it's connecting")
    func connecting() {
        #expect(PanelText.connecting == "Connecting to GitHub…")
    }

    @Test("a Try again that leaves shipyard signed out says why, so the click doesn't look dead", arguments: [
        (Shipyard.SignedOutReason.noToken, "gh still isn't signed in."),
        (.rejected(.gh), "GitHub still rejects gh's token."),
        (.rejected(.tokenStore), "GitHub still rejects the token."),
        (.signedOut(.signedOut), "Still not connected."),
        (.signedOut(.ghStillSignedIn), "Still not connected."),
    ])
    func stillSignedOut(reason: Shipyard.SignedOutReason, text: String) {
        #expect(PanelText.stillSignedOut(reason) == text)
    }

    @Test("a rejected gh token says it was revoked or expired and to sign gh in again")
    func connectRejectedGh() {
        let text = PanelText.connect(.rejected(.gh))
        #expect(text.title == "GitHub rejected gh's token")
        #expect(text.message.contains("revoked or has expired"))
        #expect(text.command == "gh auth login")
        #expect(!text.suggestsInstallingGh)
    }

    @Test("a rejected stored token also points at gh auth login")
    func connectRejectedStored() {
        let text = PanelText.connect(.rejected(.tokenStore))
        #expect(text.title == "GitHub rejected shipyard's token")
        #expect(text.command == "gh auth login")
    }

    @Test("signing out while gh is still signed in says to run gh auth logout")
    func connectSignedOutGhStillSignedIn() {
        let text = PanelText.connect(.signedOut(.ghStillSignedIn))
        #expect(text.title == "Signed out")
        #expect(text.message.contains("still signed in"))
        #expect(text.command == "gh auth logout")
        #expect(!text.suggestsInstallingGh)
    }

    @Test("signing out with nothing left signed in points back at gh auth login")
    func connectSignedOut() {
        let text = PanelText.connect(.signedOut(.signedOut))
        #expect(text.title == "Signed out")
        #expect(text.command == "gh auth login")
    }
}
