import Foundation
@testable import ShipyardCore
import Testing

@Suite("Configuration: pings")
struct ConfigurationPingsTests {
    @Test("pings are shown by default, in every project")
    func shownByDefault() throws {
        let config = try #require(decoded("[[projects]]\nname = \"a\"\nrepositories = [\"o/a\"]\n")).configuration
        #expect(config.defaults.pings.show)
        #expect(config.settings(for: config.projects[0]).shows(.ping))
    }

    @Test("[defaults.pings] show sets every project's, and a project's pings override it")
    func showAndOverride() throws {
        let config = try #require(decoded("""
            [defaults.pings]
            show = false

            [[projects]]
            name = "quiet"
            repositories = ["o/a"]

            [[projects]]
            name = "loud"
            repositories = ["o/b"]
            pings = { show = true }
            """)).configuration
        #expect(!config.settings(for: config.projects[0]).shows(.ping))
        #expect(config.settings(for: config.projects[1]).shows(.ping))
    }

    @Test("states, authors, drafts and review-requested under pings are rejected, each on its line")
    func filtersThatDoNotApply() {
        let issues = rejection("""
            [defaults.pings]
            show = true
            states = ["open"]
            authors = { hide = ["bots"] }

            [[projects]]
            name = "a"
            repositories = ["o/a"]
            pings = { drafts = false, review-requested = true }
            """)
        #expect(issues == [
            ConfigIssue(line: 3, message: "`states` doesn't apply to pings; `pings` takes only `show`"),
            ConfigIssue(line: 4, message: "`authors` doesn't apply to pings; `pings` takes only `show`"),
            ConfigIssue(line: 9, message: "`drafts` doesn't apply to pings; `pings` takes only `show`"),
            ConfigIssue(line: 9, message: "`review-requested` doesn't apply to pings; `pings` takes only `show`"),
        ])
    }

    @Test("show must be true or false; another key under pings is only a warning")
    func showTypeAndUnknownKeys() throws {
        #expect(rejection("[defaults.pings]\nshow = \"yes\"\n") == [ConfigIssue(line: 2, message: "`defaults.pings.show` must be true or false")])
        let warnings = try #require(decoded("[defaults.pings]\nshwo = false\n")).warnings
        #expect(warnings == [ConfigIssue(line: 2, message: "unknown setting `defaults.pings.shwo` (ignored; did you mean `show`?)")])
    }
}
