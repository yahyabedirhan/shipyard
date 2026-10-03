import Foundation
import ShipyardConfig
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
            ConfigIssue(line: 3, message: "`states` doesn't apply to pings; `pings` takes only `show` and `seen-window`"),
            ConfigIssue(line: 4, message: "`authors` doesn't apply to pings; `pings` takes only `show` and `seen-window`"),
            ConfigIssue(line: 9, message: "`drafts` doesn't apply to pings; `pings` takes only `show` and `seen-window`"),
            ConfigIssue(line: 9, message: "`review-requested` doesn't apply to pings; `pings` takes only `show` and `seen-window`"),
        ])
    }

    @Test("[herdr] terminal is unset by default, and names an app when set")
    func herdrTerminal() throws {
        #expect(Configuration().herdr.terminal == nil)
        let config = try #require(decoded("[herdr]\nterminal = \" Ghostty \"\n")).configuration
        #expect(config.herdr.terminal == "Ghostty")
        #expect(rejection("[herdr]\nterminal = \" \"\n") == [
            ConfigIssue(line: 2, message: "`terminal` names your terminal app, by name or bundle id; leave it out to only focus the tab"),
        ])
        #expect(rejection("[herdr]\nterminal = true\n") == [ConfigIssue(line: 2, message: "`herdr.terminal` must be a string")])
        let warnings = try #require(decoded("[herdr]\nterminl = \"Ghostty\"\n")).warnings
        #expect(warnings == [ConfigIssue(line: 2, message: "unknown setting `herdr.terminl` (ignored; did you mean `terminal`?)")])
    }

    @Test("show must be true or false; another key under pings is only a warning")
    func showTypeAndUnknownKeys() throws {
        #expect(rejection("[defaults.pings]\nshow = \"yes\"\n") == [ConfigIssue(line: 2, message: "`defaults.pings.show` must be true or false")])
        let warnings = try #require(decoded("[defaults.pings]\nshwo = false\n")).warnings
        #expect(warnings == [ConfigIssue(line: 2, message: "unknown setting `defaults.pings.shwo` (ignored; did you mean `show`?)")])
    }

    @Test("seen-window is 24 hours by default; [defaults.pings] sets every project's and a project's overrides it")
    func seenWindow() throws {
        let plain = try #require(decoded("[[projects]]\nname = \"a\"\nrepositories = [\"o/a\"]\n")).configuration
        #expect(plain.settings(for: plain.projects[0]).pings.seenWindow == 86_400)
        let config = try #require(decoded("""
            [defaults.pings]
            seen-window = "30m"

            [[projects]]
            name = "short"
            repositories = ["o/a"]

            [[projects]]
            name = "long"
            repositories = ["o/b"]
            pings = { seen-window = "7d" }
            """)).configuration
        #expect(config.settings(for: config.projects[0]).pings.seenWindow == 1800)
        #expect(config.settings(for: config.projects[1]).pings.seenWindow == 7 * 86_400)
        #expect(config.settings(for: config.projects[1]).pings.show)
    }

    @Test("seen-window is written like closed-window, and a bad one is rejected on its line with the nearest spelling")
    func seenWindowSyntax() {
        #expect(rejection("[defaults.pings]\nseen-window = \"1 day\"\n") == [ConfigIssue(
            line: 2,
            message: "`seen-window` must be a whole number and one unit, `s`, `m`, `h` or `d`, such as \"30m\" (got \"1 day\"; did you mean \"1d\"?)"
        )])
        #expect(rejection("[defaults.pings]\nseen-window = 24\n") == [ConfigIssue(
            line: 2,
            message: "`defaults.pings.seen-window` must be a string: a whole number and one unit, `s`, `m`, `h` or `d`, such as \"30m\""
        )])
    }
}
