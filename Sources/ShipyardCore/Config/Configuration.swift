import Foundation

/// Everything the user controls, read from `config.toml` (ADR 0001).
///
/// Every key is optional: a missing key takes the default shown in
/// `docs/low-level-design.md`, so an empty or missing file is "defaults, no
/// projects". `Configuration.decode` (in `ConfigurationReader.swift`) reads
/// and validates the file; `settings(for:)` resolves one project's
/// effective settings.
public struct Configuration: Equatable, Sendable {
    /// The configuration format versions this build reads.
    public static let supportedVersion = 1

    public var version: Int = Configuration.supportedVersion
    /// A floor in seconds (at least 30); the rate budget may stretch it.
    public var refreshIntervalSeconds: Int = 120
    public var launchAtLogin: Bool = true
    public var menuBar = MenuBar()
    public var menu = Menu()
    public var rateLimit = RateLimitSettings()
    public var attention = AttentionToggles()
    /// What every project shows unless it overrides it.
    public var defaults = Defaults()
    /// In the order the file lists them, which is the order of the sections.
    public var projects: [Project] = []

    public init() {}

    public var hasProjects: Bool { !projects.isEmpty }

    /// A project's effective settings: each of its tables merges key by key
    /// onto `defaults`, and its `notifications` list, when present, replaces
    /// the default list.
    public func settings(for project: Project) -> ProjectSettings {
        ProjectSettings(
            name: project.name,
            repositories: project.repositories,
            pullRequests: project.pullRequests.applied(to: defaults.pullRequests),
            issues: project.issues.applied(to: defaults.issues),
            workflowRuns: project.workflowRuns.applied(to: defaults.workflowRuns),
            notifications: project.notifications ?? defaults.notifications,
            arrangement: project.arrangement.applied(to: defaults.arrangement)
        )
    }
}

// MARK: - Top-level tables

extension Configuration {
    /// `[menu-bar]`
    public struct MenuBar: Equatable, Sendable {
        public var count: MenuBarCount = .total
        public init(count: MenuBarCount = .total) { self.count = count }
    }

    /// `[menu]`
    public struct Menu: Equatable, Sendable {
        public var layout: MenuLayout = .list
        public init(layout: MenuLayout = .list) { self.layout = layout }
    }

    /// `[rate-limit]`
    public struct RateLimitSettings: Equatable, Sendable {
        public var show: RateLimitDisplay = .always
        /// The share of each hourly GitHub limit shipyard may spend, 1–50.
        public var maxSharePercent: Int = 10
        public init(show: RateLimitDisplay = .always, maxSharePercent: Int = 10) {
            self.show = show
            self.maxSharePercent = maxSharePercent
        }
    }

    /// `[attention]`: which reasons make an item need attention.
    public struct AttentionToggles: Equatable, Sendable {
        public var unseen = true
        public var changed = true
        public var reviewRequested = true
        public var checksFailed = true
        public init(unseen: Bool = true, changed: Bool = true, reviewRequested: Bool = true, checksFailed: Bool = true) {
            self.unseen = unseen
            self.changed = changed
            self.reviewRequested = reviewRequested
            self.checksFailed = checksFailed
        }
    }

    /// `[defaults]`
    public struct Defaults: Equatable, Sendable {
        public var pullRequests = PullRequestSettings()
        public var issues = IssueSettings()
        public var workflowRuns = WorkflowRunSettings()
        /// `[[defaults.notifications]]`; a new pull request in any project by default.
        public var notifications: [NotificationRule] = [NotificationRule(event: .prOpened)]
        /// `group-by`, `subsections` and `sort-by`, written straight under `[defaults]`.
        public var arrangement = ArrangementSettings()
        public init() {}
    }

    /// One `[[projects]]` block: a name, its repositories, and only the keys
    /// it overrides.
    public struct Project: Equatable, Sendable {
        public var name: String
        /// `owner/name` slugs.
        public var repositories: [String]
        public var pullRequests = PullRequestOverrides()
        public var issues = IssueOverrides()
        public var workflowRuns = WorkflowRunOverrides()
        /// Replaces the default notification rules when present.
        public var notifications: [NotificationRule]?
        /// The project's own `group-by`, `subsections` and `sort-by`.
        public var arrangement = ArrangementOverrides()

        public init(
            name: String,
            repositories: [String],
            pullRequests: PullRequestOverrides = .init(),
            issues: IssueOverrides = .init(),
            workflowRuns: WorkflowRunOverrides = .init(),
            notifications: [NotificationRule]? = nil,
            arrangement: ArrangementOverrides = .init()
        ) {
            self.name = name
            self.repositories = repositories
            self.pullRequests = pullRequests
            self.issues = issues
            self.workflowRuns = workflowRuns
            self.notifications = notifications
            self.arrangement = arrangement
        }
    }
}

// MARK: - Choices

/// `[menu-bar] count`
public enum MenuBarCount: String, CaseIterable, Sendable {
    case total
    case perKind = "per-kind"
    case none
}

/// `[menu] layout`: how the panel draws the projects once shipyard is
/// ready. `list` puts every project's rows in one scrolling list, under
/// pinned project headers; `tabs` shows one project at a time.
///
/// The cases' order is the cycle the header's layout button steps
/// through: a new layout only has to be added here to join it.
public enum MenuLayout: String, CaseIterable, Sendable {
    case list
    case tabs

    /// The layout after this one in the cycle; after the last, the first.
    public var next: MenuLayout {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        return all[(index + 1) % all.count]
    }
}

/// `[rate-limit] show`
public enum RateLimitDisplay: String, CaseIterable, Sendable {
    case always
    case whenLow = "when-low"
    case never
}

/// `group-by`: what a project's items are grouped by. One level only;
/// `none` lists them as one group.
public enum GroupBy: String, CaseIterable, Sendable {
    case kind
    case repository
    case date
    case author
    case none
}

/// `sort-by`: the order within a group, newest first or A to Z. Open (or
/// running) items always come before closed (or finished) ones.
public enum SortBy: String, CaseIterable, Sendable {
    case updated
    case created
    case title
}

/// `workflow-runs.branches`
public enum WorkflowRunBranches: String, CaseIterable, Sendable {
    case defaultAndPullRequests = "default-and-pull-requests"
    case all
}

/// The events a notification rule can name.
public enum EventKind: String, CaseIterable, Sendable {
    case prOpened = "pr.opened"
    case prMerged = "pr.merged"
    case prClosed = "pr.closed"
    case prReopened = "pr.reopened"
    case prReviewRequested = "pr.review_requested"
    case prChecksFailed = "pr.checks_failed"
    case prCommented = "pr.commented"
    case issueOpened = "issue.opened"
    case issueClosed = "issue.closed"
    case issueCommented = "issue.commented"
    case runFailed = "run.failed"
    case runSucceeded = "run.succeeded"
}

/// An event and the authors it covers. Its scope is where it's written:
/// `[[defaults.notifications]]` for every project, or a project's own list.
/// It only narrows what the project lists: an item the listing leaves out
/// is never notified (ADR 0003).
public struct NotificationRule: Equatable, Sendable {
    /// The strings `authors` took before selectors, still read with a
    /// warning: `any` is everyone, the others one author group each.
    public static let legacyAuthors = ["any", "me", "others", "bots"]

    public var event: EventKind
    /// Author selectors; empty is everyone.
    public var authors: [AuthorSelector]
    public init(event: EventKind, authors: [AuthorSelector] = []) {
        self.event = event
        self.authors = authors
    }

    /// Whether the rule covers an item's author: any of its selectors
    /// matches, or it has none.
    public func covers(_ item: Item, viewer: String?) -> Bool {
        authors.isEmpty || authors.contains { $0.matches(item, viewer: viewer) }
    }
}

// MARK: - Per-kind settings and their overrides

/// `pull-requests`
public struct PullRequestSettings: Equatable, Sendable {
    public var show = true
    public var closedWindowDays = 7
    public var drafts = true
    public var authors = AuthorFilter()
    /// `review-requested`: list only open pull requests waiting on the
    /// user's review, directly or through one of their teams.
    public var reviewRequested = false
    public init(
        show: Bool = true,
        closedWindowDays: Int = 7,
        drafts: Bool = true,
        authors: AuthorFilter = AuthorFilter(),
        reviewRequested: Bool = false
    ) {
        self.show = show
        self.closedWindowDays = closedWindowDays
        self.drafts = drafts
        self.authors = authors
        self.reviewRequested = reviewRequested
    }
}

/// `issues`
public struct IssueSettings: Equatable, Sendable {
    public var show = false
    public var closedWindowDays = 7
    public var authors = AuthorFilter()
    public init(show: Bool = false, closedWindowDays: Int = 7, authors: AuthorFilter = AuthorFilter()) {
        self.show = show
        self.closedWindowDays = closedWindowDays
        self.authors = authors
    }
}

/// `workflow-runs`
public struct WorkflowRunSettings: Equatable, Sendable {
    public var show = false
    public var finishedWindowHours = 3
    public var branches: WorkflowRunBranches = .defaultAndPullRequests
    public var authors = AuthorFilter()
    public init(
        show: Bool = false,
        finishedWindowHours: Int = 3,
        branches: WorkflowRunBranches = .defaultAndPullRequests,
        authors: AuthorFilter = AuthorFilter()
    ) {
        self.show = show
        self.finishedWindowHours = finishedWindowHours
        self.branches = branches
        self.authors = authors
    }
}

/// The `pull-requests` keys a table sets; unset keys keep the value below.
public struct PullRequestOverrides: Equatable, Sendable {
    public var show: Bool?
    public var closedWindowDays: Int?
    public var drafts: Bool?
    public var authors: AuthorFilterOverrides
    public var reviewRequested: Bool?
    public init(
        show: Bool? = nil,
        closedWindowDays: Int? = nil,
        drafts: Bool? = nil,
        authors: AuthorFilterOverrides = .init(),
        reviewRequested: Bool? = nil
    ) {
        self.show = show
        self.closedWindowDays = closedWindowDays
        self.drafts = drafts
        self.authors = authors
        self.reviewRequested = reviewRequested
    }

    public func applied(to base: PullRequestSettings) -> PullRequestSettings {
        PullRequestSettings(
            show: show ?? base.show,
            closedWindowDays: closedWindowDays ?? base.closedWindowDays,
            drafts: drafts ?? base.drafts,
            authors: authors.applied(to: base.authors),
            reviewRequested: reviewRequested ?? base.reviewRequested
        )
    }
}

/// The `issues` keys a table sets; unset keys keep the value below.
public struct IssueOverrides: Equatable, Sendable {
    public var show: Bool?
    public var closedWindowDays: Int?
    public var authors: AuthorFilterOverrides
    public init(show: Bool? = nil, closedWindowDays: Int? = nil, authors: AuthorFilterOverrides = .init()) {
        self.show = show
        self.closedWindowDays = closedWindowDays
        self.authors = authors
    }

    public func applied(to base: IssueSettings) -> IssueSettings {
        IssueSettings(
            show: show ?? base.show,
            closedWindowDays: closedWindowDays ?? base.closedWindowDays,
            authors: authors.applied(to: base.authors)
        )
    }
}

/// The `workflow-runs` keys a table sets; unset keys keep the value below.
public struct WorkflowRunOverrides: Equatable, Sendable {
    public var show: Bool?
    public var finishedWindowHours: Int?
    public var branches: WorkflowRunBranches?
    public var authors: AuthorFilterOverrides
    public init(
        show: Bool? = nil,
        finishedWindowHours: Int? = nil,
        branches: WorkflowRunBranches? = nil,
        authors: AuthorFilterOverrides = .init()
    ) {
        self.show = show
        self.finishedWindowHours = finishedWindowHours
        self.branches = branches
        self.authors = authors
    }

    public func applied(to base: WorkflowRunSettings) -> WorkflowRunSettings {
        WorkflowRunSettings(
            show: show ?? base.show,
            finishedWindowHours: finishedWindowHours ?? base.finishedWindowHours,
            branches: branches ?? base.branches,
            authors: authors.applied(to: base.authors)
        )
    }
}

/// How a project's listed items are grouped, sorted and drawn.
public struct ArrangementSettings: Equatable, Sendable {
    public var groupBy: GroupBy = .kind
    /// Groups drawn as subheaders (`true`) or dividers (`false`); `nil`
    /// keeps each layout's own: dividers in the list, subheaders in a tab.
    public var subsections: Bool?
    public var sortBy: SortBy = .updated
    public init(groupBy: GroupBy = .kind, subsections: Bool? = nil, sortBy: SortBy = .updated) {
        self.groupBy = groupBy
        self.subsections = subsections
        self.sortBy = sortBy
    }
}

/// The arrangement keys a table sets; unset keys keep the value below.
public struct ArrangementOverrides: Equatable, Sendable {
    public var groupBy: GroupBy?
    public var subsections: Bool?
    public var sortBy: SortBy?
    public init(groupBy: GroupBy? = nil, subsections: Bool? = nil, sortBy: SortBy? = nil) {
        self.groupBy = groupBy
        self.subsections = subsections
        self.sortBy = sortBy
    }

    public func applied(to base: ArrangementSettings) -> ArrangementSettings {
        ArrangementSettings(
            groupBy: groupBy ?? base.groupBy,
            subsections: subsections ?? base.subsections,
            sortBy: sortBy ?? base.sortBy
        )
    }
}

/// A project with defaults and its overrides merged: what the refresh, the
/// menu model and the notification rules read.
public struct ProjectSettings: Equatable, Sendable {
    public var name: String
    public var repositories: [String]
    public var pullRequests: PullRequestSettings
    public var issues: IssueSettings
    public var workflowRuns: WorkflowRunSettings
    public var notifications: [NotificationRule]
    public var arrangement: ArrangementSettings

    public init(
        name: String,
        repositories: [String],
        pullRequests: PullRequestSettings,
        issues: IssueSettings,
        workflowRuns: WorkflowRunSettings,
        notifications: [NotificationRule],
        arrangement: ArrangementSettings = ArrangementSettings()
    ) {
        self.name = name
        self.repositories = repositories
        self.pullRequests = pullRequests
        self.issues = issues
        self.workflowRuns = workflowRuns
        self.notifications = notifications
        self.arrangement = arrangement
    }

    /// Whether the project lists items of `kind` (its `show` for that kind).
    public func shows(_ kind: ItemKind) -> Bool {
        switch kind {
        case .pullRequest: pullRequests.show
        case .issue: issues.show
        case .workflowRun: workflowRuns.show
        }
    }

    /// Whose items of `kind` the project lists.
    public func authors(of kind: ItemKind) -> AuthorFilter {
        switch kind {
        case .pullRequest: pullRequests.authors
        case .issue: issues.authors
        case .workflowRun: workflowRuns.authors
        }
    }
}

// MARK: - Problems

/// One problem found in the file, with the line it's on when known.
public struct ConfigIssue: Hashable, Sendable, CustomStringConvertible {
    /// 1-based line in `config.toml`, when the problem can be placed.
    public var line: Int?
    public var message: String

    public init(line: Int?, message: String) {
        self.line = line
        self.message = message
    }

    /// "line 14: unknown event `pr.openned` (did you mean `pr.opened`?)"
    public var description: String {
        line.map { "line \($0): \(message)" } ?? message
    }
}

/// Why the file was rejected. The store keeps the last valid configuration
/// and exposes this for the panel's banner.
public struct ConfigError: Error, Equatable, Sendable, CustomStringConvertible {
    /// Every problem found, in file order where known; never empty.
    public var issues: [ConfigIssue]

    public init(_ issues: [ConfigIssue]) {
        precondition(!issues.isEmpty, "a ConfigError needs at least one issue")
        self.issues = issues
    }

    /// The first problem's line, for the banner.
    public var line: Int? { issues[0].line }
    /// The first problem's message, for the banner.
    public var message: String { issues[0].message }

    public var description: String {
        issues.map(\.description).joined(separator: "\n")
    }
}

// MARK: - Appending projects

/// A project the picker adds: just a name and its repositories.
public struct NewProject: Equatable, Sendable {
    public var name: String
    public var repositories: [String]
    public init(name: String, repositories: [String]) {
        self.name = name
        self.repositories = repositories
    }
}

extension Configuration {
    /// Where the published JSON Schema lives; the file's `#:schema` line points here.
    public static let schemaURL = "https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json"

    /// The text a new configuration file starts with: the settings people
    /// reach for first, commented out at their defaults, so uncommenting one
    /// changes nothing until its value is edited. Top-level keys come above
    /// every table and tables above the projects the picker appends, so any
    /// example, or all of them, can be uncommented and the file stays valid.
    public static let header = """
        #:schema \(schemaURL)
        # shipyard configuration. You and your agents edit this file; shipyard
        # applies changes live. It writes to it only to add projects and, from
        # the menu's layout button, to set layout under [menu]; the rest stays.
        # Every key is optional. Keys, defaults and events are in the schema above.
        # The settings below are commented out at their defaults: uncomment one
        # and change its value to use it.
        version = \(supportedVersion)

        # How the menu draws your projects: "list" (every project in one
        # scrolling list) or "tabs" (one project at a time).
        # [menu]
        # layout = "list"

        # The number next to the menu bar icon: "total" (items that need your
        # attention), "per-kind" (pull requests, issues and runs apart) or "none".
        # [menu-bar]
        # count = "total"

        # Whose pull requests every project lists: show (empty: everyone)
        # minus hide. Authors are the groups me, others and bots, or one
        # login written with @, e.g. "@dependabot[bot]". Issues and runs
        # take authors the same way; a project can override it in its block.
        # [defaults.pull-requests]
        # authors = { show = [], hide = [] }

        # How each project's items are grouped: "kind" (pull requests, issues,
        # runs), "repository", "date", "author" or "none"; and sorted within a
        # group: "updated", "created" or "title". A project can set its own.
        # [defaults]
        # group-by = "kind"
        # sort-by = "updated"

        # List issues too, not only pull requests, in every project: set show
        # to true. A project can override it in its own block.
        # [defaults.issues]
        # show = false

        # List GitHub Actions workflow runs in every project: set show to true.
        # [defaults.workflow-runs]
        # show = false

        # When to notify, for every project: one block per rule. The list
        # replaces the default rule below, so keep it to hear of new pull
        # requests. Other events include "run.failed" and "pr.review_requested";
        # authors narrows a rule to some authors, as above (empty: everyone).
        # [[defaults.notifications]]
        # event = "pr.opened"
        # authors = []

        # The largest share of each hourly GitHub rate limit shipyard may spend,
        # in percent (1 to 50). The limit is shared with your other tools.
        # [rate-limit]
        # max-share-percent = 10

        # Projects: one [[projects]] block each, below. The project picker
        # appends them here.

        """

    /// The `[[projects]]` blocks the picker appends to the end of the file.
    /// Each block is self-contained, so appending never disturbs what's above.
    public static func appendText(projects: [NewProject]) -> String {
        projects.map { project in
            let repositories = project.repositories.map(tomlString).joined(separator: ", ")
            return """

                [[projects]]
                name = \(tomlString(project.name))
                repositories = [\(repositories)]

                """
        }.joined()
    }

    /// A TOML basic string with `"`, `\` and control characters escaped.
    static func tomlString(_ value: String) -> String {
        var out = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    out += String(format: "\\u%04X", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
