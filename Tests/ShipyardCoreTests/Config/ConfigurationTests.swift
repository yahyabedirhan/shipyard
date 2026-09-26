import Foundation
@testable import ShipyardCore
import Testing

/// Decodes `text`, failing the test if it's rejected.
func decoded(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> Configuration.Decoded? {
    do {
        return try Configuration.decode(text)
    } catch {
        Issue.record("expected the file to decode, got: \(error)", sourceLocation: sourceLocation)
        return nil
    }
}

/// The problems a rejected file is rejected for; fails the test if it decodes.
func rejection(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) -> [ConfigIssue] {
    do throws(ConfigError) {
        _ = try Configuration.decode(text)
        Issue.record("expected the file to be rejected", sourceLocation: sourceLocation)
        return []
    } catch {
        return error.issues
    }
}

/// The repository root, for the design document and the schema.
let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent() // Config
    .deletingLastPathComponent() // ShipyardCoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent()

/// The example `config.toml` in `docs/low-level-design.md`, read from the
/// design itself so the two can't drift apart.
func designExample() throws -> String {
    let design = try String(contentsOf: repositoryRoot.appendingPathComponent("docs/low-level-design.md"), encoding: .utf8)
    let start = try #require(design.range(of: "```toml\n#:schema"))
    let body = design[design.index(start.lowerBound, offsetBy: "```toml\n".count)...]
    let end = try #require(body.range(of: "\n```"))
    return String(body[..<end.lowerBound]) + "\n"
}

/// Every key the configuration has, each set away from its default.
let everyKey = """
    #:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json
    version = 1
    refresh-interval-seconds = 300
    launch-at-login = false

    [menu-bar]
    count = "per-kind"

    [menu]
    layout = "tabs"

    [rate-limit]
    show = "when-low"
    max-share-percent = 25

    [attention]
    unseen = false
    changed = false
    review-requested = false
    checks-failed = false

    [defaults]
    group-by = "repository"
    subsections = true
    sort-by = "created"
    archived = true
    forks = false

    [defaults.pull-requests]
    show = false
    states = ["open"]
    closed-window-days = 14
    drafts = false
    authors = { show = ["others", "@dependabot[bot]"], hide = ["@octocat"] }
    review-requested = true

    [defaults.issues]
    show = true
    states = ["open"]
    closed-window-days = 0
    authors = { show = ["others"], hide = ["bots"] }

    [defaults.workflow-runs]
    show = true
    states = ["in-progress", "failed"]
    finished-window-hours = 12
    branches = "all"
    authors = { show = ["me"], hide = ["@yabepa"] }

    [[defaults.notifications]]
    event = "pr.merged"
    authors = ["me"]

    [[defaults.notifications]]
    event = "run.failed"

    [[projects]]
    name = "blog"
    repositories = ["yahyabedirhan/blog-frontend", "yahyabedirhan/blog.api", "my-org/*", "owned", "organizations", "collaborator"]
    archived = false
    forks = true
    pull-requests = { show = true, states = ["merged", "closed"], closed-window-days = 1, drafts = true, authors = { show = [], hide = ["me", "bots"] }, review-requested = false }
    issues = { show = false, states = ["closed"], closed-window-days = 30, authors = { show = ["@renovate[bot]"], hide = [] } }
    workflow-runs = { show = false, states = ["succeeded"], finished-window-hours = 1, branches = "default-and-pull-requests", authors = { show = ["bots"], hide = ["others"] } }
    notifications = [{ event = "issue.opened", authors = ["bots", "@octocat"] }]
    group-by = "date"
    subsections = false
    sort-by = "title"

    """

@Suite("Configuration: decoding")
struct ConfigurationDecodingTests {
    @Test("an empty file is the defaults with no projects")
    func emptyFile() throws {
        for text in ["", "\n", "# only a comment\n"] {
            let result = try #require(decoded(text))
            #expect(result.configuration == Configuration())
            #expect(result.warnings.isEmpty)
        }
        let fromData = try Configuration.decode(Data())
        #expect(fromData.configuration.projects.isEmpty)
    }

    @Test("the defaults are the documented ones")
    func defaults() {
        let config = Configuration()
        #expect(config.version == 1)
        #expect(config.refreshIntervalSeconds == 120)
        #expect(config.launchAtLogin)
        #expect(config.menuBar.count == .total)
        #expect(config.menu.layout == .list)
        #expect(config.rateLimit == .init(show: .always, maxSharePercent: 10))
        #expect(config.attention == .init(unseen: true, changed: true, reviewRequested: true, checksFailed: true))
        // Every author, in every kind: an existing file lists what it did.
        #expect(config.defaults.pullRequests == .init(
            show: true, states: [.open, .merged, .closed], closedWindowDays: 7, drafts: true, authors: AuthorFilter(show: [], hide: []), reviewRequested: false
        ))
        #expect(config.defaults.issues == .init(show: false, states: [.open, .closed], closedWindowDays: 7, authors: AuthorFilter()))
        #expect(config.defaults.workflowRuns == .init(
            show: false, states: [.inProgress, .failed, .succeeded], finishedWindowHours: 3, branches: .defaultAndPullRequests, authors: AuthorFilter()
        ))
        #expect(config.defaults.notifications == [NotificationRule(event: .prOpened, authors: [])])
        #expect(config.defaults.arrangement == .init(groupBy: .kind, subsections: nil, sortBy: .updated))
        #expect(!config.defaults.archived)
        #expect(config.defaults.forks)
        #expect(config.projects.isEmpty)
        #expect(!config.hasProjects)
    }

    @Test("the design's example file decodes with the documented defaults")
    func designExampleDecodes() throws {
        // The design's example file already uses settings that aren't built yet;
        // this wrapper comes off once the example decodes.
        withKnownIssue {
            let result = try #require(decoded(try designExample()))
            #expect(result.warnings.isEmpty)
            let config = result.configuration

            var expected = Configuration()
            expected.projects = [
                Configuration.Project(
                    name: "e-commerce",
                    repositories: ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"],
                    issues: IssueOverrides(show: true),
                    notifications: [
                        NotificationRule(event: .prOpened, authors: [.others]),
                        NotificationRule(event: .runFailed),
                    ]
                ),
                Configuration.Project(name: "job-search", repositories: ["yahyabedirhan/job-search"]),
            ]
            #expect(config == expected)
        }
    }

    @Test("every key decodes, spelt in kebab-case")
    func everyKeyDecodes() throws {
        let result = try #require(decoded(everyKey))
        #expect(result.warnings.isEmpty)
        let config = result.configuration
        #expect(config.refreshIntervalSeconds == 300)
        #expect(!config.launchAtLogin)
        #expect(config.menuBar.count == .perKind)
        #expect(config.menu.layout == .tabs)
        #expect(config.rateLimit == .init(show: .whenLow, maxSharePercent: 25))
        #expect(config.attention == .init(unseen: false, changed: false, reviewRequested: false, checksFailed: false))
        #expect(config.defaults.pullRequests == .init(
            show: false, states: [.open], closedWindowDays: 14, drafts: false,
            authors: AuthorFilter(show: [.others, .login("dependabot[bot]")], hide: [.login("octocat")]),
            reviewRequested: true
        ))
        #expect(config.defaults.issues == .init(show: true, states: [.open], closedWindowDays: 0, authors: AuthorFilter(show: [.others], hide: [.bots])))
        #expect(config.defaults.workflowRuns == .init(
            show: true, states: [.inProgress, .failed], finishedWindowHours: 12, branches: .all, authors: AuthorFilter(show: [.me], hide: [.login("yabepa")])
        ))
        #expect(config.defaults.notifications == [
            NotificationRule(event: .prMerged, authors: [.me]),
            NotificationRule(event: .runFailed),
        ])
        #expect(config.defaults.archived)
        #expect(!config.defaults.forks)
        let project = try #require(config.projects.first)
        #expect(project.name == "blog")
        #expect(project.repositories == [
            .repository("yahyabedirhan/blog-frontend"), .repository("yahyabedirhan/blog.api"),
            .owner("my-org"), .group(.owned), .group(.organizations), .group(.collaborator),
        ])
        #expect(project.archived == false)
        #expect(project.forks == true)
        #expect(project.pullRequests == .init(
            show: true, states: [.merged, .closed], closedWindowDays: 1, drafts: true, authors: .init(show: [], hide: [.me, .bots]), reviewRequested: false
        ))
        #expect(project.issues == .init(show: false, states: [.closed], closedWindowDays: 30, authors: .init(show: [.login("renovate[bot]")], hide: [])))
        #expect(project.workflowRuns == .init(
            show: false, states: [.succeeded], finishedWindowHours: 1, branches: .defaultAndPullRequests, authors: .init(show: [.bots], hide: [.others])
        ))
        #expect(project.notifications == [NotificationRule(event: .issueOpened, authors: [.bots, .login("octocat")])])
        #expect(config.defaults.arrangement == .init(groupBy: .repository, subsections: true, sortBy: .created))
        #expect(project.arrangement == .init(groupBy: .date, subsections: false, sortBy: .title))
    }

    @Test("every group-by and sort-by choice decodes")
    func everyArrangement() throws {
        for groupBy in GroupBy.allCases {
            for sortBy in SortBy.allCases {
                let text = "[defaults]\ngroup-by = \"\(groupBy.rawValue)\"\nsort-by = \"\(sortBy.rawValue)\"\n"
                let config = try #require(decoded(text)).configuration
                #expect(config.defaults.arrangement == .init(groupBy: groupBy, sortBy: sortBy))
            }
        }
    }

    @Test("every event and author selector decodes")
    func everyEvent() throws {
        let selectors: [AuthorSelector] = AuthorSelector.groups + [.login("octocat"), .login("dependabot[bot]")]
        for event in EventKind.allCases {
            for authors in [[], selectors] {
                let list = authors.map { "\"\($0)\"" }.joined(separator: ", ")
                let text = "[[defaults.notifications]]\nevent = \"\(event.rawValue)\"\nauthors = [\(list)]\n"
                let result = try #require(decoded(text))
                #expect(result.warnings.isEmpty)
                #expect(result.configuration.defaults.notifications == [NotificationRule(event: event, authors: authors)])
            }
        }
    }

    @Test("projects and notification rules may be written inline or as blocks")
    func inlineAndBlocks() throws {
        let text = """
            projects = [{ name = "a", repositories = ["o/a"] }]

            [defaults]
            notifications = []
            """
        let config = try #require(decoded(text)).configuration
        #expect(config.projects.map(\.name) == ["a"])
        #expect(config.defaults.notifications.isEmpty)
    }
}

@Suite("Configuration: validation")
struct ConfigurationValidationTests {
    @Test("invalid TOML is rejected with its line")
    func invalidTOML() {
        let issues = rejection("version = 1\n[menu-bar\ncount = \"total\"\n")
        #expect(issues.count == 1)
        #expect(issues.first?.line == 2)
        #expect(issues.first?.message.hasPrefix("invalid TOML: ") == true)
    }

    @Test("an unknown event is rejected with the nearest valid one")
    func unknownEvent() {
        let issues = rejection("""
            [[defaults.notifications]]
            event = "pr.openned"
            """)
        #expect(issues == [ConfigIssue(line: 2, message: "unknown event `pr.openned` (did you mean `pr.opened`?)")])
        #expect(issues.first?.description == "line 2: unknown event `pr.openned` (did you mean `pr.opened`?)")
    }

    @Test("an unknown event inside a multi-line list is placed on its own line")
    func unknownEventInList() {
        let issues = rejection("""
            [[projects]]
            name = "a"
            repositories = ["o/a"]
            notifications = [
              { event = "pr.opened" },
              { event = "run.faild" },
            ]
            """)
        #expect(issues == [ConfigIssue(line: 6, message: "unknown event `run.faild` (did you mean `run.failed`?)")])
    }

    @Test("an event nothing like a valid one lists the valid ones")
    func unrecognisableEvent() {
        let issues = rejection("[[defaults.notifications]]\nevent = \"banana\"\n")
        #expect(issues.count == 1)
        #expect(issues.first?.line == 2)
        #expect(issues.first?.message.hasPrefix("unknown event `banana` (expected one of `pr.opened`, `pr.merged`") == true)
    }

    @Test("a rule without an event, and other unknown choices, are rejected")
    func otherChoices() {
        #expect(rejection("[[defaults.notifications]]\nauthors = \"me\"\n")
            == [ConfigIssue(line: 1, message: "a notification rule needs an `event`")])
        #expect(rejection("[[defaults.notifications]]\nevent = \"pr.opened\"\nauthors = \"bot\"\n")
            == [ConfigIssue(line: 3, message: "unknown author `bot` (did you mean `bots` or `@bot`?)")])
        #expect(rejection("[menu-bar]\ncount = \"per_kind\"\n")
            == [ConfigIssue(line: 2, message: "unknown value `per_kind` for `count` (did you mean `per-kind`?)")])
        #expect(rejection("[menu]\nlayout = \"tab\"\n")
            == [ConfigIssue(line: 2, message: "unknown value `tab` for `layout` (did you mean `tabs`?)")])
        #expect(rejection("[menu]\nlayout = \"grid\"\n")
            == [ConfigIssue(line: 2, message: "unknown value `grid` for `layout` (expected one of `list`, `tabs`)")])
        #expect(rejection("[menu]\nlayout = 2\n")
            == [ConfigIssue(line: 2, message: "`menu.layout` must be a string")])
        #expect(rejection("[rate-limit]\nshow = \"sometimes\"\n")
            == [ConfigIssue(line: 2, message: "unknown value `sometimes` for `show` (expected one of `always`, `when-low`, `never`)")])
        #expect(rejection("[defaults.workflow-runs]\nbranches = \"al\"\n")
            == [ConfigIssue(line: 2, message: "unknown value `al` for `branches` (did you mean `all`?)")])
    }

    @Test("an unknown group-by or sort-by is rejected with the nearest valid one")
    func arrangementChoices() {
        #expect(rejection("[defaults]\ngroup-by = \"repo\"\n")
            == [ConfigIssue(line: 2, message: "unknown value `repo` for `group-by` (expected one of `kind`, `repository`, `date`, `author`, `none`)")])
        #expect(rejection("[defaults]\ngroup-by = \"repositories\"\n")
            == [ConfigIssue(line: 2, message: "unknown value `repositories` for `group-by` (did you mean `repository`?)")])
        #expect(rejection("[defaults]\nsort-by = \"update\"\n")
            == [ConfigIssue(line: 2, message: "unknown value `update` for `sort-by` (did you mean `updated`?)")])
        #expect(rejection("[[projects]]\nname = \"a\"\nrepositories = [\"o/a\"]\ngroup-by = \"authors\"\n")
            == [ConfigIssue(line: 4, message: "unknown value `authors` for `group-by` (did you mean `author`?)")])
        #expect(rejection("[defaults]\nsort-by = \"oldest\"\n")
            == [ConfigIssue(line: 2, message: "unknown value `oldest` for `sort-by` (expected one of `updated`, `created`, `title`)")])
        #expect(rejection("[defaults]\nsubsections = \"yes\"\n")
            == [ConfigIssue(line: 2, message: "`defaults.subsections` must be true or false")])
    }

    @Test("a project's arrangement merges key by key onto the defaults")
    func arrangementMerges() throws {
        let config = try #require(decoded("""
            [defaults]
            group-by = "repository"
            subsections = true

            [[projects]]
            name = "a"
            repositories = ["o/a"]
            sort-by = "title"

            [[projects]]
            name = "b"
            repositories = ["o/b"]
            group-by = "none"
            subsections = false
            """)).configuration
        #expect(config.settings(for: config.projects[0]).arrangement == .init(groupBy: .repository, subsections: true, sortBy: .title))
        #expect(config.settings(for: config.projects[1]).arrangement == .init(groupBy: .none, subsections: false, sortBy: .updated))
    }

        @Test("a repository that isn't owner/name, owner/* or a group is rejected")
    func repositorySlugs() {
        let issues = rejection("""
            [[projects]]
            name = "a"
            repositories = [
              "o/good",
              "just-a-name",
              "o/b/c",
              "/x",
              "o/",
            ]
            """)
        #expect(issues == [
            ConfigIssue(line: 5, message: "unknown repository group `just-a-name` (did you mean `just-a-name/*`, or a repository as `just-a-name/name`?)"),
            ConfigIssue(line: 6, message: "repository `o/b/c` isn't `owner/name` or `owner/*`"),
            ConfigIssue(line: 7, message: "repository `/x` isn't `owner/name` or `owner/*`"),
            ConfigIssue(line: 8, message: "repository `o/` isn't `owner/name` or `owner/*`"),
        ])
        #expect(ConfigurationReader.isRepositorySlug("yahyabedirhan/e-commerce_v2.api"))
    }

    @Test("a repository listed twice in one project is rejected, whatever its case")
    func duplicateRepositories() {
        let issues = rejection("""
            [[projects]]
            name = "a"
            repositories = [
              "o/r",
              "o/other",
              "o/r",
              "O/R",
            ]

            [[projects]]
            name = "b"
            repositories = ["o/r"]
            """)
        #expect(issues == [
            ConfigIssue(line: 6, message: "project `a` lists repository `o/r` twice (names aren't case-sensitive)"),
            ConfigIssue(line: 7, message: "project `a` lists repository `O/R` twice (names aren't case-sensitive)"),
        ])
    }

    @Test("a project needs a name and at least one repository")
    func projectRequirements() {
        #expect(rejection("[[projects]]\nrepositories = [\"o/a\"]\n")
            == [ConfigIssue(line: 1, message: "a project needs a `name`")])
        #expect(rejection("[[projects]]\nname = \"a\"\n")
            == [ConfigIssue(line: 1, message: "project `a` needs `repositories`, a list of repositories (`owner/name`, `owner/*` or a group such as `owned`)")])
        #expect(rejection("[[projects]]\nname = \"a\"\nrepositories = []\n")
            == [ConfigIssue(line: 3, message: "project `a` needs at least one repository")])
        #expect(rejection("[[projects]]\nname = \" \"\nrepositories = [\"o/a\"]\n")
            == [ConfigIssue(line: 2, message: "a project's `name` can't be empty")])
    }

    @Test("duplicate project names are rejected")
    func duplicateNames() {
        let issues = rejection("""
            [[projects]]
            name = "a"
            repositories = ["o/a"]

            [[projects]]
            name = "a"
            repositories = ["o/b"]
            """)
        #expect(issues == [ConfigIssue(line: 6, message: "project name `a` is used twice (first on line 2)")])
    }

    @Test("review-requested must be true or false, and a project's overrides the default")
    func reviewRequested() throws {
        #expect(rejection("[[projects]]\nname = \"a\"\nrepositories = [\"o/a\"]\npull-requests = { review-requested = \"yes\" }\n")
            == [ConfigIssue(line: 4, message: "`projects[0].pull-requests.review-requested` must be true or false")])

        let config = try #require(decoded("""
            [defaults.pull-requests]
            review-requested = true

            [[projects]]
            name = "queue"
            repositories = ["o/a"]

            [[projects]]
            name = "all"
            repositories = ["o/a"]
            pull-requests = { review-requested = false }
            """)).configuration
        #expect(config.settings(for: config.projects[0]).pullRequests.reviewRequested)
        #expect(!config.settings(for: config.projects[1]).pullRequests.reviewRequested)
    }

    @Test("negative windows are rejected")
    func negativeWindows() {
        #expect(rejection("[defaults.pull-requests]\nclosed-window-days = -1\n")
            == [ConfigIssue(line: 2, message: "`closed-window-days` can't be negative (got -1)")])
        #expect(rejection("[defaults.issues]\nclosed-window-days = -2\n")
            == [ConfigIssue(line: 2, message: "`closed-window-days` can't be negative (got -2)")])
        #expect(rejection("[defaults.workflow-runs]\nfinished-window-hours = -3\n")
            == [ConfigIssue(line: 2, message: "`finished-window-hours` can't be negative (got -3)")])
        #expect(rejection("[[projects]]\nname = \"a\"\nrepositories = [\"o/a\"]\nissues = { closed-window-days = -4 }\n")
            == [ConfigIssue(line: 4, message: "`closed-window-days` can't be negative (got -4)")])
        #expect(decoded("[defaults.pull-requests]\nclosed-window-days = 0\n")?.configuration.defaults.pullRequests.closedWindowDays == 0)
    }

    @Test("an interval under 30 seconds is rejected")
    func interval() {
        #expect(rejection("refresh-interval-seconds = 29\n")
            == [ConfigIssue(line: 1, message: "`refresh-interval-seconds` must be at least 30 (got 29)")])
        #expect(decoded("refresh-interval-seconds = 30\n")?.configuration.refreshIntervalSeconds == 30)
    }

    @Test("a rate-limit share outside 1–50 is rejected")
    func share() {
        for share in [0, 51, -5] {
            #expect(rejection("[rate-limit]\nmax-share-percent = \(share)\n")
                == [ConfigIssue(line: 2, message: "`max-share-percent` must be between 1 and 50 (got \(share))")])
        }
        for share in [1, 50] {
            #expect(decoded("[rate-limit]\nmax-share-percent = \(share)\n")?.configuration.rateLimit.maxSharePercent == share)
        }
    }

    @Test("a value of the wrong type is rejected with its line")
    func wrongTypes() {
        #expect(rejection("version = 1\nlaunch-at-login = \"yes\"\n")
            == [ConfigIssue(line: 2, message: "`launch-at-login` must be true or false")])
        #expect(rejection("refresh-interval-seconds = 90.5\n")
            == [ConfigIssue(line: 1, message: "`refresh-interval-seconds` must be a whole number")])
        #expect(rejection("hide-authors = \"dependabot[bot]\"\n")
            == [ConfigIssue(line: 1, message: "`hide-authors` must be a list of strings")])
        #expect(rejection("menu-bar = 3\n")
            == [ConfigIssue(line: 1, message: "`menu-bar` must be a table")])
    }

    @Test("an unsupported version is rejected")
    func version() {
        #expect(rejection("version = 2\n")
            == [ConfigIssue(line: 1, message: "`version` 2 isn't supported; this shipyard reads version 1")])
    }

    @Test("every problem in the file is reported, in order")
    func severalProblems() {
        let issues = rejection("""
            refresh-interval-seconds = 10
            [rate-limit]
            max-share-percent = 90
            """)
        #expect(issues.map(\.line) == [1, 3])
        let error = ConfigError(issues)
        #expect(error.line == 1)
        #expect(error.message == "`refresh-interval-seconds` must be at least 30 (got 10)")
    }
}

@Suite("Configuration: unknown keys")
struct ConfigurationWarningTests {
    @Test("unknown keys are warnings, not errors, and are ignored")
    func unknownKeys() throws {
        let result = try #require(decoded("""
            refreshIntervalSeconds = 60
            theme = "dark"

            [attention]
            unseeen = false

            [[projects]]
            name = "a"
            repositories = ["o/a"]
            colour = "red"
            """))
        #expect(result.configuration.refreshIntervalSeconds == 120)
        #expect(result.configuration.attention.unseen)
        #expect(result.configuration.projects.map(\.name) == ["a"])
        #expect(Set(result.warnings) == [
            ConfigIssue(line: 1, message: "unknown setting `refreshIntervalSeconds` (ignored; did you mean `refresh-interval-seconds`?)"),
            ConfigIssue(line: 2, message: "unknown setting `theme` (ignored)"),
            ConfigIssue(line: 5, message: "unknown setting `attention.unseeen` (ignored; did you mean `unseen`?)"),
            ConfigIssue(line: 10, message: "unknown setting `projects[0].colour` (ignored)"),
        ])
    }
}

@Suite("Configuration: per-project settings")
struct ConfigurationMergeTests {
    let config: Configuration

    init() throws {
        config = try Configuration.decode("""
            [defaults.pull-requests]
            closed-window-days = 3
            drafts = false

            [defaults.workflow-runs]
            show = true

            [[defaults.notifications]]
            event = "pr.opened"

            [defaults.pull-requests.authors]
            show = ["others"]
            hide = ["bots"]

            [[defaults.notifications]]
            event = "run.failed"
            authors = ["me"]

            [[projects]]
            name = "overrides"
            repositories = ["o/a", "o/b"]
            pull-requests = { drafts = true, authors = { hide = ["@octocat"] } }
            issues = { show = true }
            workflow-runs = { branches = "all" }
            notifications = [{ event = "pr.merged", authors = ["others"] }]

            [[projects]]
            name = "plain"
            repositories = ["o/c"]

            [[projects]]
            name = "quiet"
            repositories = ["o/d"]
            notifications = []
            """).configuration
    }

    @Test("a project's tables merge key by key onto the defaults")
    func tablesMerge() {
        let settings = config.settings(for: config.projects[0])
        #expect(settings.name == "overrides")
        #expect(settings.repositories == ["o/a", "o/b"])
        // `authors` merges key by key too: the project's `hide`, the default `show`.
        #expect(settings.pullRequests == .init(
            show: true, closedWindowDays: 3, drafts: true, authors: AuthorFilter(show: [.others], hide: [.login("octocat")])
        ))
        #expect(settings.issues == .init(show: true, closedWindowDays: 7))
        #expect(settings.workflowRuns == .init(show: true, finishedWindowHours: 3, branches: .all))
    }

    @Test("a project's notifications replace the default list")
    func notificationsReplace() {
        #expect(config.settings(for: config.projects[0]).notifications == [NotificationRule(event: .prMerged, authors: [.others])])
        #expect(config.settings(for: config.projects[2]).notifications.isEmpty)
    }

    @Test("a project without overrides takes the defaults")
    func plainProject() {
        let settings = config.settings(for: config.projects[1])
        #expect(settings.pullRequests == config.defaults.pullRequests)
        #expect(settings.issues == config.defaults.issues)
        #expect(settings.workflowRuns == config.defaults.workflowRuns)
        #expect(settings.notifications == [
            NotificationRule(event: .prOpened),
            NotificationRule(event: .runFailed, authors: [.me]),
        ])
    }
}

@Suite("Configuration: nearest suggestion")
struct SuggestionTests {
    @Test("near misses are suggested, far ones aren't")
    func nearest() {
        let events = EventKind.allCases.map(\.rawValue)
        #expect(Suggestion.nearest(to: "pr.openned", in: events) == "pr.opened")
        #expect(Suggestion.nearest(to: "pr.review-requested", in: events) == "pr.review_requested")
        #expect(Suggestion.nearest(to: "PR.MERGED", in: events) == "pr.merged")
        #expect(Suggestion.nearest(to: "banana", in: events) == nil)
        #expect(Suggestion.distance("kitten", "sitting") == 3)
    }
}
