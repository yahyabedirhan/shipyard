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
    public var herdr = HerdrSettings()
    public var remote = RemoteSettings()
    /// What every project shows unless it overrides it.
    public var defaults = Defaults()
    /// In the order the file lists them, which is the order of the sections.
    public var projects: [Project] = []

    public init() {}

    public var hasProjects: Bool { !projects.isEmpty }

    /// What a machine's own section (`[remote] machines`) lists with: the
    /// defaults, as for a project that overrides nothing.
    public func settings(forMachine label: String) -> ProjectSettings {
        settings(for: Project(name: label, repositories: []))
    }

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
            pings: project.pings.applied(to: defaults.pings),
            notifications: project.notifications ?? defaults.notifications,
            arrangement: project.arrangement.applied(to: defaults.arrangement),
            archived: project.archived ?? defaults.archived,
            forks: project.forks ?? defaults.forks
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

    /// `[herdr]`: how a ping's Herdr action (`--herdr`) takes the user there.
    public struct HerdrSettings: Equatable, Sendable {
        /// The terminal app Herdr runs in, by name (`Ghostty`) or bundle id,
        /// brought forward after the tab is focused; `nil` (the default)
        /// only focuses the tab.
        public var terminal: String?
        public init(terminal: String? = nil) { self.terminal = terminal }
    }

    /// `[remote]`: the other machines whose pings the menu lists.
    public struct RemoteSettings: Equatable, Sendable {
        /// The machines, by the labels the Mac's Herdr knows them by as
        /// saved machines (`herdr --machine <label>`), in the order their
        /// sections follow the projects; none by default. Labels only:
        /// never a host or an address.
        public var machines: [String]
        public init(machines: [String] = []) { self.machines = machines }
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
        public var pings = PingSettings()
        /// `[[defaults.notifications]]`; a new pull request and a new ping
        /// in any project by default.
        public var notifications: [NotificationRule] = [NotificationRule(event: .prOpened), NotificationRule(event: .pingSent)]
        /// `group-by`, `subsections`, `sort-by` and `show-first`, written straight under `[defaults]`.
        public var arrangement = ArrangementSettings()
        /// Whether repository groups and `owner/*` bring in archived repositories.
        public var archived = false
        /// Whether repository groups and `owner/*` bring in forks.
        public var forks = true
        public init() {}
    }

    /// One `[[projects]]` block: a name, its repositories, and only the keys
    /// it overrides.
    public struct Project: Equatable, Sendable {
        public var name: String
        /// Repository selectors: `owner/name`, `owner/*` and repository groups.
        public var repositories: [RepositorySelector]
        public var pullRequests = PullRequestOverrides()
        public var issues = IssueOverrides()
        public var workflowRuns = WorkflowRunOverrides()
        public var pings = PingOverrides()
        /// Replaces the default notification rules when present.
        public var notifications: [NotificationRule]?
        /// The project's own `group-by`, `subsections`, `sort-by` and `show-first`.
        public var arrangement = ArrangementOverrides()
        /// `archived` and `forks`, when the project sets them.
        public var archived: Bool?
        public var forks: Bool?

        public init(
            name: String,
            repositories: [RepositorySelector],
            pullRequests: PullRequestOverrides = .init(),
            issues: IssueOverrides = .init(),
            workflowRuns: WorkflowRunOverrides = .init(),
            pings: PingOverrides = .init(),
            notifications: [NotificationRule]? = nil,
            arrangement: ArrangementOverrides = .init(),
            archived: Bool? = nil,
            forks: Bool? = nil
        ) {
            self.name = name
            self.repositories = repositories
            self.pullRequests = pullRequests
            self.issues = issues
            self.workflowRuns = workflowRuns
            self.pings = pings
            self.notifications = notifications
            self.arrangement = arrangement
            self.archived = archived
            self.forks = forks
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
    /// An agent sent a new ping (`shipyard ping`).
    case pingSent = "ping.sent"
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
    /// matches, or it has none. A ping has no GitHub author, so a rule with
    /// `authors` never covers one.
    public func covers(_ item: Item, viewer: String?) -> Bool {
        if item.kind == .ping { return authors.isEmpty }
        return authors.isEmpty || authors.contains { $0.matches(item, viewer: viewer) }
    }
}

// MARK: - Per-kind settings and their overrides

/// `pull-requests`
public struct PullRequestSettings: Equatable, Sendable {
    public var show = true
    /// Which pull requests are listed by where they stand; all three by default.
    public var states = Set(StateGroup.all(for: .pullRequest))
    /// `closed-window`: how long a closed one stays listed, in seconds; 0 hides it.
    public var closedWindow: TimeInterval = 7 * 86_400
    public var drafts = true
    public var authors = AuthorFilter()
    /// `review-requested`: list only open pull requests waiting on the
    /// user's review, directly or through one of their teams.
    public var reviewRequested = false
    public init(
        show: Bool = true,
        states: Set<StateGroup> = Set(StateGroup.all(for: .pullRequest)),
        closedWindow: TimeInterval = 7 * 86_400,
        drafts: Bool = true,
        authors: AuthorFilter = AuthorFilter(),
        reviewRequested: Bool = false
    ) {
        self.show = show
        self.states = states
        self.closedWindow = closedWindow
        self.drafts = drafts
        self.authors = authors
        self.reviewRequested = reviewRequested
    }
}

/// `issues`
public struct IssueSettings: Equatable, Sendable {
    public var show = false
    /// Which issues are listed by where they stand; open and closed by default.
    public var states = Set(StateGroup.all(for: .issue))
    /// `closed-window`: how long a closed one stays listed, in seconds; 0 hides it.
    public var closedWindow: TimeInterval = 7 * 86_400
    public var authors = AuthorFilter()
    public init(
        show: Bool = false,
        states: Set<StateGroup> = Set(StateGroup.all(for: .issue)),
        closedWindow: TimeInterval = 7 * 86_400,
        authors: AuthorFilter = AuthorFilter()
    ) {
        self.show = show
        self.states = states
        self.closedWindow = closedWindow
        self.authors = authors
    }
}

/// `workflow-runs`
public struct WorkflowRunSettings: Equatable, Sendable {
    public var show = false
    /// Which runs are listed by where they stand; all three by default.
    public var states = Set(StateGroup.all(for: .workflowRun))
    /// `finished-window`: how long a finished run stays listed, in seconds; 0 hides it.
    public var finishedWindow: TimeInterval = 3 * 3600
    public var branches: WorkflowRunBranches = .defaultAndPullRequests
    public var authors = AuthorFilter()
    public init(
        show: Bool = false,
        states: Set<StateGroup> = Set(StateGroup.all(for: .workflowRun)),
        finishedWindow: TimeInterval = 3 * 3600,
        branches: WorkflowRunBranches = .defaultAndPullRequests,
        authors: AuthorFilter = AuthorFilter()
    ) {
        self.show = show
        self.states = states
        self.finishedWindow = finishedWindow
        self.branches = branches
        self.authors = authors
    }
}

/// The `pull-requests` keys a table sets; unset keys keep the value below.
public struct PullRequestOverrides: Equatable, Sendable {
    public var show: Bool?
    public var states: Set<StateGroup>?
    public var closedWindow: TimeInterval?
    public var drafts: Bool?
    public var authors: AuthorFilterOverrides
    public var reviewRequested: Bool?
    public init(
        show: Bool? = nil,
        states: Set<StateGroup>? = nil,
        closedWindow: TimeInterval? = nil,
        drafts: Bool? = nil,
        authors: AuthorFilterOverrides = .init(),
        reviewRequested: Bool? = nil
    ) {
        self.show = show
        self.states = states
        self.closedWindow = closedWindow
        self.drafts = drafts
        self.authors = authors
        self.reviewRequested = reviewRequested
    }

    public func applied(to base: PullRequestSettings) -> PullRequestSettings {
        PullRequestSettings(
            show: show ?? base.show,
            states: states ?? base.states,
            closedWindow: closedWindow ?? base.closedWindow,
            drafts: drafts ?? base.drafts,
            authors: authors.applied(to: base.authors),
            reviewRequested: reviewRequested ?? base.reviewRequested
        )
    }
}

/// The `issues` keys a table sets; unset keys keep the value below.
public struct IssueOverrides: Equatable, Sendable {
    public var show: Bool?
    public var states: Set<StateGroup>?
    public var closedWindow: TimeInterval?
    public var authors: AuthorFilterOverrides
    public init(show: Bool? = nil, states: Set<StateGroup>? = nil, closedWindow: TimeInterval? = nil, authors: AuthorFilterOverrides = .init()) {
        self.show = show
        self.states = states
        self.closedWindow = closedWindow
        self.authors = authors
    }

    public func applied(to base: IssueSettings) -> IssueSettings {
        IssueSettings(
            show: show ?? base.show,
            states: states ?? base.states,
            closedWindow: closedWindow ?? base.closedWindow,
            authors: authors.applied(to: base.authors)
        )
    }
}

/// The `workflow-runs` keys a table sets; unset keys keep the value below.
public struct WorkflowRunOverrides: Equatable, Sendable {
    public var show: Bool?
    public var states: Set<StateGroup>?
    public var finishedWindow: TimeInterval?
    public var branches: WorkflowRunBranches?
    public var authors: AuthorFilterOverrides
    public init(
        show: Bool? = nil,
        states: Set<StateGroup>? = nil,
        finishedWindow: TimeInterval? = nil,
        branches: WorkflowRunBranches? = nil,
        authors: AuthorFilterOverrides = .init()
    ) {
        self.show = show
        self.states = states
        self.finishedWindow = finishedWindow
        self.branches = branches
        self.authors = authors
    }

    public func applied(to base: WorkflowRunSettings) -> WorkflowRunSettings {
        WorkflowRunSettings(
            show: show ?? base.show,
            states: states ?? base.states,
            finishedWindow: finishedWindow ?? base.finishedWindow,
            branches: branches ?? base.branches,
            authors: authors.applied(to: base.authors)
        )
    }
}

/// `pings`: the pings agents send with the `shipyard` CLI. They take no
/// `states`, `authors`, `drafts` or `review-requested`.
public struct PingSettings: Equatable, Sendable {
    public var show = true
    /// `seen-window`: how long a seen ping stays listed, in seconds, counted
    /// from when it was seen; 0 lets it leave at once. An unseen ping stays.
    public var seenWindow: TimeInterval = 86_400
    public init(show: Bool = true, seenWindow: TimeInterval = 86_400) {
        self.show = show
        self.seenWindow = seenWindow
    }
}

/// The `pings` keys a table sets; unset keys keep the value below.
public struct PingOverrides: Equatable, Sendable {
    public var show: Bool?
    public var seenWindow: TimeInterval?
    public init(show: Bool? = nil, seenWindow: TimeInterval? = nil) {
        self.show = show
        self.seenWindow = seenWindow
    }

    public func applied(to base: PingSettings) -> PingSettings {
        PingSettings(show: show ?? base.show, seenWindow: seenWindow ?? base.seenWindow)
    }
}

/// How a project's listed items are grouped, sorted and drawn.
public struct ArrangementSettings: Equatable, Sendable {
    public var groupBy: GroupBy = .kind
    /// Groups drawn as subheaders (`true`) or dividers (`false`); `nil`
    /// keeps each layout's own: dividers in the list, subheaders in a tab.
    public var subsections: Bool?
    public var sortBy: SortBy = .updated
    /// How many rows each group shows before a Show more row; `0` shows
    /// them all. With `group-by = "none"` it caps the whole project.
    public var showFirst: Int = 0
    public init(groupBy: GroupBy = .kind, subsections: Bool? = nil, sortBy: SortBy = .updated, showFirst: Int = 0) {
        self.groupBy = groupBy
        self.subsections = subsections
        self.sortBy = sortBy
        self.showFirst = showFirst
    }
}

/// The arrangement keys a table sets; unset keys keep the value below.
public struct ArrangementOverrides: Equatable, Sendable {
    public var groupBy: GroupBy?
    public var subsections: Bool?
    public var sortBy: SortBy?
    public var showFirst: Int?
    public init(groupBy: GroupBy? = nil, subsections: Bool? = nil, sortBy: SortBy? = nil, showFirst: Int? = nil) {
        self.groupBy = groupBy
        self.subsections = subsections
        self.sortBy = sortBy
        self.showFirst = showFirst
    }

    public func applied(to base: ArrangementSettings) -> ArrangementSettings {
        ArrangementSettings(
            groupBy: groupBy ?? base.groupBy,
            subsections: subsections ?? base.subsections,
            sortBy: sortBy ?? base.sortBy,
            showFirst: showFirst ?? base.showFirst
        )
    }
}

/// A project with defaults and its overrides merged: what the refresh, the
/// menu model and the notification rules read.
public struct ProjectSettings: Equatable, Sendable {
    public var name: String
    /// As configured; `resolved(by:)` turns the groups and wildcards into
    /// the repositories they stand for.
    public var repositories: [RepositorySelector]
    public var pullRequests: PullRequestSettings
    public var issues: IssueSettings
    public var workflowRuns: WorkflowRunSettings
    public var pings: PingSettings
    public var notifications: [NotificationRule]
    public var arrangement: ArrangementSettings
    /// Whether groups and `owner/*` bring in archived repositories.
    public var archived: Bool
    /// Whether groups and `owner/*` bring in forks.
    public var forks: Bool

    public init(
        name: String,
        repositories: [RepositorySelector],
        pullRequests: PullRequestSettings,
        issues: IssueSettings,
        workflowRuns: WorkflowRunSettings,
        pings: PingSettings = PingSettings(),
        notifications: [NotificationRule],
        arrangement: ArrangementSettings = ArrangementSettings(),
        archived: Bool = false,
        forks: Bool = true
    ) {
        self.name = name
        self.repositories = repositories
        self.pullRequests = pullRequests
        self.issues = issues
        self.workflowRuns = workflowRuns
        self.pings = pings
        self.notifications = notifications
        self.arrangement = arrangement
        self.archived = archived
        self.forks = forks
    }

    /// The single repositories among its selectors (`owner/name`), in order:
    /// all of them once the settings are `resolved(by:)`.
    public var repositorySlugs: [String] { repositories.compactMap(\.slug) }

    /// Whether the project lists the review search's pull requests from any
    /// repository (`anywhere`).
    public var usesAnywhere: Bool { repositories.contains(.anywhere) }

    /// These settings watching exactly the repositories `resolved` found for
    /// them, each as `owner/name`. Without a resolution (none yet), only the
    /// single repositories the project names. `anywhere` stays, since it
    /// resolves to no repositories.
    public func resolved(by resolved: ResolvedRepositories?) -> ProjectSettings {
        var settings = self
        settings.repositories = (resolved?.repositories ?? repositorySlugs).map(RepositorySelector.repository)
        if usesAnywhere { settings.repositories.append(.anywhere) }
        return settings
    }

    /// Whether the project lists items of `kind` (its `show` for that kind).
    public func shows(_ kind: ItemKind) -> Bool {
        switch kind {
        case .pullRequest: pullRequests.show
        case .issue: issues.show
        case .workflowRun: workflowRuns.show
        case .ping: pings.show
        }
    }

    /// Which of `kind`'s states the project lists.
    public func states(of kind: ItemKind) -> Set<StateGroup> {
        switch kind {
        case .pullRequest: pullRequests.states
        case .issue: issues.states
        case .workflowRun: workflowRuns.states
        case .ping: Set(StateGroup.all(for: .ping))
        }
    }

    /// Whose items of `kind` the project lists.
    public func authors(of kind: ItemKind) -> AuthorFilter {
        switch kind {
        case .pullRequest: pullRequests.authors
        case .issue: issues.authors
        case .workflowRun: workflowRuns.authors
        // A ping has no GitHub author: every one is listed.
        case .ping: AuthorFilter()
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
        # applies changes live. It writes to it only to add projects, to set
        # layout under [menu] from the menu's layout button, and, during
        # onboarding, to write a preset over a file holding nothing but
        # version; the rest stays.
        # Every key is optional. Keys, defaults and events are in the schema above.
        # The settings below are commented out at their defaults: uncomment one
        # and change its value to use it.
        version = \(supportedVersion)

        # How the menu draws your projects: "list" (every project in one
        # scrolling list) or "tabs" (one project at a time).
        # [menu]
        # layout = "list"

        # The number next to the menu bar icon: "total" (items that need your
        # attention), "per-kind" (pull requests, issues, runs and pings apart) or "none".
        # [menu-bar]
        # count = "total"

        # Whose pull requests every project lists: show (empty: everyone)
        # minus hide. Authors are the groups me, others and bots, or one
        # login written with @, e.g. "@dependabot[bot]". Issues and runs
        # take authors the same way; a project can override it in its block.
        # [defaults.pull-requests]
        # authors = { show = [], hide = [] }

        # How each project's items are grouped: "kind" (pull requests, issues,
        # runs), "repository", "date", "author" or "none"; sorted within a
        # group: "updated", "created" or "title"; and how many rows a group
        # shows before a Show more row (0: all). A project can set its own.
        # [defaults]
        # group-by = "kind"
        # sort-by = "updated"
        # show-first = 0

        # List issues too, not only pull requests, in every project: set show
        # to true. states picks which: "open", "closed" or both. Pull requests
        # take states too ("open", "merged", "closed"), and runs ("in-progress",
        # "failed", "succeeded"). A project can override both in its own block.
        # [defaults.issues]
        # show = false
        # states = ["open", "closed"]

        # List GitHub Actions workflow runs in every project: set show to true.
        # [defaults.workflow-runs]
        # show = false

        # List the pings your agents send with `shipyard ping` in every
        # project: set show to false to hide them. A seen ping stays listed
        # for seen-window, then leaves; an unseen one stays until you see it.
        # A project can override both.
        # [defaults.pings]
        # show = true
        # seen-window = "24h"

        # When to notify, for every project: one block per rule. The list
        # replaces the default rules below, so keep them to hear of new pull
        # requests and pings. Other events include "run.failed" and
        # "pr.review_requested"; authors narrows a rule to some authors, as
        # above (empty: everyone).
        # [[defaults.notifications]]
        # event = "pr.opened"
        # authors = []
        # [[defaults.notifications]]
        # event = "ping.sent"
        # authors = []

        # Using Herdr? A ping an agent sends with --herdr focuses its tab when
        # clicked. To bring your terminal forward too, add a [herdr] table and
        # set terminal in it to the terminal app's name or bundle id, such as "Ghostty".

        # The largest share of each hourly GitHub rate limit shipyard may spend,
        # in percent (1 to 50). The limit is shared with your other tools.
        # [rate-limit]
        # max-share-percent = 10

        # Projects: one [[projects]] block each, below. The project picker
        # appends them here. A project's repositories can be owner/name,
        # owner/* (everything an owner has) or a group: owned, organizations
        # or collaborator.

        """

    /// The `[[projects]]` blocks the picker appends to the end of the file.
    /// Each block is self-contained, so appending never disturbs what's above.
    public static func appendText(projects: [NewProject]) -> String {
        projects.map { "\n" + projectBlock($0) }.joined()
    }

    /// One project's `[[projects]]` block: its header, name and
    /// repositories, ending in a newline. The picker's appends and the
    /// presets both build on it, each adding the blank lines around it.
    static func projectBlock(_ project: NewProject) -> String {
        let repositories = project.repositories.map(tomlString).joined(separator: ", ")
        return """
            [[projects]]
            name = \(tomlString(project.name))
            repositories = [\(repositories)]

            """
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
