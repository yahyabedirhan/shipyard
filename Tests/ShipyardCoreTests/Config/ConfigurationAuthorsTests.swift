import Foundation
import ShipyardConfig
@testable import ShipyardCore
import Testing

@Suite("Configuration: authors")
struct ConfigurationAuthorsTests {
    @Test("a bare word that isn't an author group is rejected on its line, with a suggestion")
    func unknownAuthor() {
        #expect(rejection("""
            [defaults.pull-requests]
            authors = { hide = ["me", "bots2"] }
            """) == [ConfigurationIssue(line: 2, message: "unknown author `bots2` (did you mean `bots` or `@bots2`?)")])
        #expect(rejection("""
            [[projects]]
            slug = "a"
            repositories = ["o/a"]
            issues = { authors = { show = [
              "others",
              "dependabot",
            ] } }
            """) == [ConfigurationIssue(line: 6, message: "unknown author `dependabot` (did you mean `@dependabot`?)")])
    }

    @Test("a repository group or a repository in authors is rejected on its line, with a hint")
    func repositoryAsAuthor() {
        let takes = "`authors` takes `me`, `others`, `bots` or an `@login`"
        #expect(rejection("""
            [defaults.workflow-runs]
            authors = { show = ["owned"] }

            [[defaults.notifications]]
            event = "pr.opened"
            authors = ["yahyabedirhan/shipyard"]
            """) == [
                ConfigurationIssue(line: 2, message: "`owned` is a repository group; \(takes)"),
                ConfigurationIssue(line: 6, message: "`yahyabedirhan/shipyard` is a repository; \(takes)"),
            ])
    }

    @Test("a kind's authors take only show and hide, as lists")
    func authorsShape() throws {
        #expect(rejection("[defaults.issues]\nauthors = [\"bots\"]\n")
            == [ConfigurationIssue(line: 2, message: "`defaults.issues.authors` must be a table")])
        #expect(rejection("[defaults.issues]\nauthors = { hide = \"bots\" }\n")
            == [ConfigurationIssue(line: 2, message: "`defaults.issues.authors.hide` must be a list of strings")])
        let result = try #require(decoded("version = 1\n[defaults.issues]\nauthors = { mute = [\"bots\"] }\n"))
        #expect(result.warnings.map(\.message) == ["unknown setting `defaults.issues.authors.mute` (ignored)"])
    }

    @Test("a single selector or a group written as a string is rejected: authors is a list")
    func singleStringSelector() {
        #expect(rejection("[[defaults.notifications]]\nevent = \"pr.opened\"\nauthors = \"@octocat\"\n")
            == [ConfigurationIssue(line: 3, message: "`authors` is a list: write `authors = [\"@octocat\"]`")])
        #expect(rejection("[[defaults.notifications]]\nevent = \"pr.opened\"\nauthors = \"others\"\n")
            == [ConfigurationIssue(line: 3, message: "`authors` is a list: write `authors = [\"others\"]`")])
        #expect(rejection("[[defaults.notifications]]\nevent = \"pr.opened\"\nauthors = \"any\"\n")
            == [ConfigurationIssue(line: 3, message: "unknown author `any` (an empty list means everyone)")])
    }
}
