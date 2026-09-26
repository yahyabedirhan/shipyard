import Foundation
@testable import ShipyardCore
import Testing

@Suite("Configuration: authors")
struct ConfigurationAuthorsTests {
    @Test("a bare word that isn't an author group is rejected on its line, with a suggestion")
    func unknownAuthor() {
        #expect(rejection("""
            [defaults.pull-requests]
            authors = { hide = ["me", "bots2"] }
            """) == [ConfigIssue(line: 2, message: "unknown author `bots2` (did you mean `bots` or `@bots2`?)")])
        #expect(rejection("""
            [[projects]]
            name = "a"
            repositories = ["o/a"]
            issues = { authors = { show = [
              "others",
              "dependabot",
            ] } }
            """) == [ConfigIssue(line: 6, message: "unknown author `dependabot` (did you mean `@dependabot`?)")])
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
                ConfigIssue(line: 2, message: "`owned` is a repository group; \(takes)"),
                ConfigIssue(line: 6, message: "`yahyabedirhan/shipyard` is a repository; \(takes)"),
            ])
    }

    @Test("a kind's authors take only show and hide, as lists")
    func authorsShape() throws {
        #expect(rejection("[defaults.issues]\nauthors = [\"bots\"]\n")
            == [ConfigIssue(line: 2, message: "`defaults.issues.authors` must be a table")])
        #expect(rejection("[defaults.issues]\nauthors = { hide = \"bots\" }\n")
            == [ConfigIssue(line: 2, message: "`defaults.issues.authors.hide` must be a list of strings")])
        let result = try #require(decoded("[defaults.issues]\nauthors = { mute = [\"bots\"] }\n"))
        #expect(result.warnings.map(\.message) == ["unknown setting `defaults.issues.authors.mute` (ignored)"])
    }

    @Test("an old hide-authors is read as a hide in each kind's defaults, with a warning")
    func oldHideAuthors() throws {
        let result = try #require(decoded("""
            version = 1
            hide-authors = ["dependabot[bot]", "Renovate[bot]"]

            [defaults.issues]
            authors = { hide = ["me"] }
            """))
        let hidden: [AuthorSelector] = [.login("dependabot[bot]"), .login("Renovate[bot]")]
        let defaults = result.configuration.defaults
        #expect(defaults.pullRequests.authors == AuthorFilter(hide: hidden))
        #expect(defaults.issues.authors == AuthorFilter(hide: [.me] + hidden))
        #expect(defaults.workflowRuns.authors == AuthorFilter(hide: hidden))
        #expect(result.warnings == [ConfigIssue(
            line: 2,
            message: "`hide-authors` is the old form: it's read as `authors = { hide = [\"@dependabot[bot]\", \"@Renovate[bot]\"] }` "
                + "in `[defaults.pull-requests]`, `[defaults.issues]` and `[defaults.workflow-runs]`; write that instead"
        )])
    }

    @Test("old notification author strings are read as selectors, with a warning each")
    func oldNotificationAuthors() throws {
        let result = try #require(decoded("""
            [[defaults.notifications]]
            event = "pr.opened"
            authors = "any"

            [[defaults.notifications]]
            event = "pr.merged"
            authors = "others"

            [[projects]]
            name = "a"
            repositories = ["o/a"]
            notifications = [{ event = "run.failed", authors = "me" }, { event = "pr.opened", authors = "bots" }]
            """))
        #expect(result.configuration.defaults.notifications == [
            NotificationRule(event: .prOpened, authors: []),
            NotificationRule(event: .prMerged, authors: [.others]),
        ])
        #expect(result.configuration.projects.first?.notifications == [
            NotificationRule(event: .runFailed, authors: [.me]),
            NotificationRule(event: .prOpened, authors: [.bots]),
        ])
        let old = "is the old form of a notification rule's authors"
        #expect(result.warnings == [
            ConfigIssue(line: 3, message: "`authors = \"any\"` \(old); write `authors = []`, or leave it out, for everyone"),
            ConfigIssue(line: 7, message: "`authors = \"others\"` \(old); write `authors = [\"others\"]`"),
            ConfigIssue(line: 12, message: "`authors = \"me\"` \(old); write `authors = [\"me\"]`"),
            ConfigIssue(line: 12, message: "`authors = \"bots\"` \(old); write `authors = [\"bots\"]`"),
        ])
    }

    @Test("a single selector written as a string is rejected: authors is a list")
    func singleStringSelector() {
        #expect(rejection("[[defaults.notifications]]\nevent = \"pr.opened\"\nauthors = \"@octocat\"\n")
            == [ConfigIssue(line: 3, message: "`authors` is a list: write `authors = [\"@octocat\"]`")])
    }
}
