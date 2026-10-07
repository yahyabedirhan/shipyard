import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

@Suite("Configuration: notes")
struct ConfigurationNotesTests {
    @Test("the filters other kinds take are rejected under notes, each on its line")
    func filtersThatDoNotApply() {
        let issues = rejection("""
            [defaults.notes]
            states = ["open"]
            seen-window = "1d"

            [[projects]]
            slug = "a"
            repositories = ["o/a"]
            notes = { authors = { hide = ["bots"] } }
            """)
        #expect(issues == [
            ConfigurationIssue(line: 2, message: "`states` doesn't apply to notes; `notes` takes only `show`"),
            ConfigurationIssue(line: 3, message: "`seen-window` doesn't apply to notes; `notes` takes only `show`"),
            ConfigurationIssue(line: 8, message: "`authors` doesn't apply to notes; `notes` takes only `show`"),
        ])
    }

    @Test("show must be true or false; another key under notes is only a warning")
    func showTypeAndUnknownKeys() throws {
        #expect(rejection("[defaults.notes]\nshow = 1\n") == [ConfigurationIssue(line: 2, message: "`defaults.notes.show` must be true or false")])
        let warnings = try #require(decoded("version = 1\n[defaults.notes]\nshwo = false\n")).warnings
        #expect(warnings == [ConfigurationIssue(line: 3, message: "unknown setting `defaults.notes.shwo` (ignored; did you mean `show`?)")])
    }
}
