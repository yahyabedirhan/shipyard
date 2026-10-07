import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

@Suite("Configuration: pings")
struct ConfigurationPingsTests {
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
            ConfigurationIssue(line: 3, message: "`states` doesn't apply to pings; `pings` takes only `show` and `seen-window`"),
            ConfigurationIssue(line: 4, message: "`authors` doesn't apply to pings; `pings` takes only `show` and `seen-window`"),
            ConfigurationIssue(line: 9, message: "`drafts` doesn't apply to pings; `pings` takes only `show` and `seen-window`"),
            ConfigurationIssue(line: 9, message: "`review-requested` doesn't apply to pings; `pings` takes only `show` and `seen-window`"),
        ])
    }

    @Test("[herdr] terminal names an app when set")
    func herdrTerminal() throws {
        let config = try #require(decoded("[herdr]\nterminal = \" Ghostty \"\n")).configuration
        #expect(config.herdr.terminal == "Ghostty")
        #expect(rejection("[herdr]\nterminal = \" \"\n") == [
            ConfigurationIssue(line: 2, message: "`terminal` names your terminal app, by name or bundle id; leave it out to only focus the tab"),
        ])
        #expect(rejection("[herdr]\nterminal = true\n") == [ConfigurationIssue(line: 2, message: "`herdr.terminal` must be a string")])
        let warnings = try #require(decoded("[herdr]\nterminl = \"Ghostty\"\n")).warnings
        #expect(warnings == [ConfigurationIssue(line: 2, message: "unknown setting `herdr.terminl` (ignored; did you mean `terminal`?)")])
    }

    @Test("show must be true or false; another key under pings is only a warning")
    func showTypeAndUnknownKeys() throws {
        #expect(rejection("[defaults.pings]\nshow = \"yes\"\n") == [ConfigurationIssue(line: 2, message: "`defaults.pings.show` must be true or false")])
        let warnings = try #require(decoded("[defaults.pings]\nshwo = false\n")).warnings
        #expect(warnings == [ConfigurationIssue(line: 2, message: "unknown setting `defaults.pings.shwo` (ignored; did you mean `show`?)")])
    }

    @Test("seen-window is written like closed-window, and a bad one is rejected on its line with the nearest spelling")
    func seenWindowSyntax() {
        #expect(rejection("[defaults.pings]\nseen-window = \"1 day\"\n") == [ConfigurationIssue(
            line: 2,
            message: "`seen-window` must be a whole number and one unit, `s`, `m`, `h` or `d`, such as \"30m\" (got \"1 day\"; did you mean \"1d\"?)"
        )])
        #expect(rejection("[defaults.pings]\nseen-window = 24\n") == [ConfigurationIssue(
            line: 2,
            message: "`defaults.pings.seen-window` must be a string: a whole number and one unit, `s`, `m`, `h` or `d`, such as \"30m\""
        )])
    }
}
