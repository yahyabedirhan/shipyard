import Foundation
@testable import ShipyardCore
import Testing

@Suite("Configuration: repository selectors")
struct ConfigurationRepositoriesTests {
    @Test("groups, owner wildcards and single repositories decode, with archived and forks per project")
    func selectorsDecode() throws {
        let config = try #require(decoded("""
            [defaults]
            archived = true

            [[projects]]
            name = "mine"
            repositories = ["owned", "organizations", "collaborator", "Some-Org/*", "o/r"]
            forks = false

            [[projects]]
            name = "plain"
            repositories = ["o/r"]
            archived = false
            """)).configuration

        #expect(config.projects[0].repositories == [
            .group(.owned), .group(.organizations), .group(.collaborator), .owner("Some-Org"), .repository("o/r"),
        ])
        let mine = config.settings(for: config.projects[0])
        #expect(mine.archived)
        #expect(!mine.forks)
        #expect(mine.repositorySlugs == ["o/r"])
        let plain = config.settings(for: config.projects[1])
        #expect(!plain.archived)
        #expect(plain.forks)
        // As written in the file.
        #expect(config.projects[0].repositories.map(\.description) == ["owned", "organizations", "collaborator", "Some-Org/*", "o/r"])
    }

    @Test("an author group or a login in repositories is rejected with a hint, on its own line")
    func authorsInRepositories() {
        let issues = rejection("""
            [[projects]]
            name = "a"
            repositories = [
              "me",
              "others",
              "@yahyabedirhan",
            ]
            """)
        let takes = "`repositories` takes `owner/name`, `owner/*`, `owned`, `organizations` or `collaborator`"
        #expect(issues == [
            ConfigIssue(line: 4, message: "`me` is an author group; \(takes)"),
            ConfigIssue(line: 5, message: "`others` is an author group; \(takes)"),
            ConfigIssue(line: 6, message: "`@yahyabedirhan` is a login; \(takes); for their repositories write `yahyabedirhan/*`"),
        ])
    }

    @Test("a misspelt group suggests the group; a bad wildcard is refused")
    func misspeltGroups() {
        #expect(rejection("[[projects]]\nname = \"a\"\nrepositories = [\"ownd\"]\n")
            == [ConfigIssue(line: 3, message: "unknown repository group `ownd` (did you mean `owned`?)")])
        #expect(rejection("[[projects]]\nname = \"a\"\nrepositories = [\"organisations\"]\n")
            == [ConfigIssue(line: 3, message: "unknown repository group `organisations` (did you mean `organizations`?)")])
        #expect(rejection("[[projects]]\nname = \"a\"\nrepositories = [\"*/*\", \"o/r*\"]\n") == [
            ConfigIssue(line: 3, message: "repository `*/*` isn't `owner/name` or `owner/*`"),
            ConfigIssue(line: 3, message: "repository `o/r*` isn't `owner/name` or `owner/*`"),
        ])
        #expect(rejection("[[projects]]\nname = \"a\"\nrepositories = [\"a b\"]\n")
            == [ConfigIssue(line: 3, message: "repository `a b` isn't `owner/name`, `owner/*`, `owned`, `organizations` or `collaborator`")])
    }

    @Test("a group or a wildcard listed twice in one project is rejected, whatever its case")
    func duplicateSelectors() {
        let issues = rejection("""
            [[projects]]
            name = "a"
            repositories = [
              "owned",
              "my-org/*",
              "owned",
              "My-Org/*",
            ]
            """)
        #expect(issues == [
            ConfigIssue(line: 6, message: "project `a` lists repository `owned` twice (names aren't case-sensitive)"),
            ConfigIssue(line: 7, message: "project `a` lists repository `My-Org/*` twice (names aren't case-sensitive)"),
        ])
    }

    @Test("archived and forks must be true or false")
    func archivedAndForksTypes() {
        #expect(rejection("[defaults]\narchived = \"yes\"\n") == [ConfigIssue(line: 2, message: "`defaults.archived` must be true or false")])
        #expect(rejection("[[projects]]\nname = \"a\"\nrepositories = [\"owned\"]\nforks = 0\n")
            == [ConfigIssue(line: 4, message: "`projects[0].forks` must be true or false")])
    }

    @Test("the file's selectors, and those a preset writes in code, parse the same")
    func literals() throws {
        let fromCode: [RepositorySelector] = ["owned", "o/*", "o/r"]
        #expect(fromCode == [.group(.owned), .owner("o"), .repository("o/r")])
        #expect(try RepositorySelector.parse("O/*").lookup == RepositorySelector.parse("o/*").lookup)
        #expect(RepositorySelector.repository("o/r").lookup == nil)
    }
}
