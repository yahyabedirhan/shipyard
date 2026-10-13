import Foundation

/// What the panel draws: one section per project, in configuration order,
/// then one per remote machine with pings of its own (`[remote] machines`),
/// the attention count and menu bar label, and when the list was last
/// brought up to date. It's built from the projects' listings (`Listing`
/// decides which items a project has); every display rule (order, state and
/// check dot, which rows need attention, what the menu bar says) lives here,
/// so tests reach them without SwiftUI.
public struct MenuModel: Equatable, Sendable {
    public var sections: [MenuSection]
    /// Rows needing attention across all projects, per kind; a row listed
    /// in two projects counts once. `attention.total` is the attention count.
    public var attention: AttentionCounts
    /// What the menu bar shows next to the icon, per `[menu-bar] count`.
    public var menuBarLabel: MenuBarLabel
    /// How the panel draws the sections, per `[menu] layout`.
    public var layout: MenuLayout
    /// When the rows were fetched; `nil` before the first refresh succeeded.
    public var lastUpdated: Date?
    /// Why the latest refresh failed, while the rows above are kept from an
    /// earlier one; `nil` after a refresh succeeds.
    public var fetchError: GitHubError?
    /// When the next refresh runs and why: the configured interval,
    /// stretched to stay within the rate-limit share, backed off because a
    /// limit is low, or paused until a reset. The banner says so unless it's
    /// `configured`; `nil` before the first refresh.
    public var refreshDelay: RefreshDelay?
    /// The footer's rate-limit indicator; `nil` when `[rate-limit] show`
    /// hides it or no limit is known yet.
    public var rateIndicator: RateIndicator?
    /// The subsections the user folded, as app state has them: the
    /// sections' groups carry theirs, and the All tab, arranged when it's
    /// drawn, reads its own from here.
    public var foldedGroups: Set<GroupID>
    /// One quiet line per remote machine that couldn't be read, or whose
    /// list stopped early (`MachineNotice.notices`), in configuration order.
    public var machineNotices: [MachineNotice] = []

    public init(
        sections: [MenuSection] = [],
        attention: AttentionCounts = AttentionCounts(),
        menuBarLabel: MenuBarLabel = .hidden,
        layout: MenuLayout = .list,
        lastUpdated: Date? = nil,
        fetchError: GitHubError? = nil,
        refreshDelay: RefreshDelay? = nil,
        rateIndicator: RateIndicator? = nil,
        foldedGroups: Set<GroupID> = []
    ) {
        self.foldedGroups = foldedGroups
        self.sections = sections
        self.attention = attention
        self.menuBarLabel = menuBarLabel
        self.layout = layout
        self.lastUpdated = lastUpdated
        self.fetchError = fetchError
        self.refreshDelay = refreshDelay
        self.rateIndicator = rateIndicator
    }

    /// Whether ⌘R and the Refresh button work: not while paused.
    public var canRefreshNow: Bool { !(refreshDelay?.isPaused ?? false) }

    /// The fetch error the panel's banner shows: `fetchError`, unless it's a
    /// rate limit that paused refreshing, which the pause banner explains.
    public var bannerFetchError: GitHubError? {
        switch fetchError {
        case .rateLimited, .secondaryLimit:
            canRefreshNow ? fetchError : nil
        default:
            fetchError
        }
    }

    /// Before anything was fetched.
    public static let empty = MenuModel()

    /// The group `id` names in a project's section, capped or expanded:
    /// what Show more and Show less act on; `nil` when it's not listed.
    public func group(_ id: GroupID) -> RowGroup? {
        sections.first { $0.name == id.project }?.groups.first { $0.id == id }
    }

    /// The subsection `id` names, as drawn: in a project's section, or in
    /// the All tab; `nil` when no such group is listed, or it's drawn after
    /// a divider, which has no subheader to fold.
    public func subsection(_ id: GroupID) -> RowGroup? {
        let groups = id.project.isEmpty
            ? tabContent(for: .all).groups
            : sections.first { $0.name == id.project }?.groups ?? []
        return groups.first { $0.id == id && $0.showsHeader }
    }

    /// Of `folds`, the ones to keep after a refresh: a group still listed
    /// (folded or not, under a subheader or a divider, so switching
    /// `subsections` back finds it), or any fold of a project whose rows
    /// aren't all here (not loaded, or a repository failed), whose groups
    /// may come back. A removed project's folds, and a group gone from its
    /// project (or from the All tab), are pruned.
    public func foldsToKeep(_ folds: Set<GroupID>) -> Set<GroupID> {
        let allTab = Set(tabContent(for: .all).groups.map(\.id))
        return folds.filter { id in
            if id.project.isEmpty { return allTab.contains(id) }
            guard let section = sections.first(where: { $0.name == id.project }) else { return false }
            return !section.isLoaded || !section.errors.isEmpty || section.groups.contains { $0.id == id }
        }
    }

    /// The order kinds appear in within a section.
    static let kindOrder: [ItemKind] = [.pullRequest, .ping, .issue, .workflowRun, .note]

    /// The order of the chips in a list section's header. It is the same
    /// list as `ItemKind.commandOrder` on purpose, kept apart so the chips'
    /// order stays fixed whatever that list becomes. The `[menu]
    /// header-counts` default (`Configuration.Menu`) and the schema list
    /// the same order; `ConfigSchemaTests` checks the three agree.
    static let headerCountOrder: [ItemKind] = [.pullRequest, .issue, .workflowRun, .ping, .note]

}

/// One project in the panel.
public struct MenuSection: Equatable, Sendable, Identifiable {
    /// What identifies the section: the project's slug, unique in the
    /// configuration, or a remote machine's label.
    public var name: String
    /// What its header and tab show: the project's title, or the machine's label.
    public var title: String
    /// Its listed items as `Arrangement` groups and sorts them: by default
    /// pull requests, then pings, then issues, then workflow runs, then
    /// notes; within each kind, open
    /// (or running) items first (most recently updated first), then closed
    /// (or finished) ones (most recently closed first).
    public var groups: [RowGroup]
    /// One per selector of this project that couldn't be resolved (such as
    /// an `owner/*` whose owner can't be seen), then one per repository that
    /// couldn't be fetched.
    public var errors: [MenuErrorRow]
    /// Notes drawn after the error rows, such as the review search's limit
    /// in a project using `anywhere`.
    public var notes: [String]
    /// Whether a row's second line names its repository: only when the
    /// project has more than one, or uses `anywhere`.
    public var showsRepository: Bool
    /// Rows in this section needing attention: what Mark all seen covers
    /// and a project's tab counts.
    public var attentionCount: Int
    /// The list header's chips: one per kind `[menu] header-counts` lists
    /// that this section has rows of, in the header's own order, each with
    /// its row count and whether it needs attention. A kind without rows
    /// here has no chip. `applyAttention` fills it; empty until then.
    public var headerCounts: [HeaderCount] = []
    /// Whether the user collapsed it. Its rows are still here, and still
    /// count towards the attention count.
    public var isCollapsed: Bool
    /// Whether its rows were fetched: `false` before the first refresh
    /// succeeded, when the section is listed without rows.
    public var isLoaded: Bool
    /// The project's repositories (`owner/name`): the ones it names and,
    /// once fetched, the ones its groups and wildcards resolved to.
    public var repositories: [String]
    /// The machine's label, for a remote machine's own section (its pings
    /// filed under no project); `nil` for a project's.
    public var machine: String?
    /// The header's new-note icon: on a project that shows notes while
    /// ntn can start one (`MenuModel.build`'s `notes`); `nil` hides it.
    public var newNote: NewNoteButton?
    /// The project's notes database in Notion, which the notes count opens;
    /// `nil` before a read matched one.
    public var notesDatabase: URL?

    public var id: String { name }

    /// Every row of every group, in order, the ones a cap hides too: what
    /// the counts, "Mark all seen" and the All tab read.
    public var rows: [MenuRow] { groups.flatMap(\.allRows) }

    /// A section whose rows are one group, as `group-by = "none"` makes.
    public init(
        name: String,
        title: String? = nil,
        rows: [MenuRow],
        errors: [MenuErrorRow] = [],
        notes: [String] = [],
        showsRepository: Bool = false,
        attentionCount: Int = 0,
        isCollapsed: Bool = false,
        isLoaded: Bool = true,
        repositories: [String] = []
    ) {
        self.init(
            name: name,
            title: title,
            groups: rows.isEmpty ? [] : [RowGroup(
                id: GroupID(project: name, key: .ungrouped),
                title: "",
                rows: rows,
                attentionCount: rows.filter(\.needsAttention).count
            )],
            errors: errors,
            notes: notes,
            showsRepository: showsRepository,
            attentionCount: attentionCount,
            isCollapsed: isCollapsed,
            isLoaded: isLoaded,
            repositories: repositories
        )
    }

    public init(
        name: String,
        title: String? = nil,
        groups: [RowGroup],
        errors: [MenuErrorRow] = [],
        notes: [String] = [],
        showsRepository: Bool = false,
        attentionCount: Int = 0,
        isCollapsed: Bool = false,
        isLoaded: Bool = true,
        repositories: [String] = []
    ) {
        self.name = name
        self.title = title ?? name
        self.groups = groups
        self.errors = errors
        self.notes = notes
        self.showsRepository = showsRepository
        self.attentionCount = attentionCount
        self.isCollapsed = isCollapsed
        self.isLoaded = isLoaded
        self.repositories = repositories
    }

    /// What Return on the project's header opens: its first
    /// repository in the configuration, on GitHub; `nil` without one.
    public var repositoryURL: URL? {
        repositories.first.flatMap { URL(string: "https://github.com/\($0)") }
    }

    /// What a click on the header's count chip for `kind` offers: each
    /// repository's page for that kind on GitHub (`/pulls`, `/issues` or
    /// `/actions`), with how many of the section's rows of that kind are
    /// from it. The configured repositories come first, in order, then any
    /// other a row comes from (`anywhere`), in the order the rows have them.
    /// One link opens at once; several are a menu to choose from. Notes
    /// have one: the project's notes database in Notion, once known. Empty
    /// for pings, which have no page, and for a project without
    /// repositories.
    public func pageLinks(for kind: ItemKind) -> [PageLink] {
        let path: String
        switch kind {
        case .pullRequest: path = "pulls"
        case .issue: path = "issues"
        case .workflowRun: path = "actions"
        case .note:
            return notesDatabase.map { [PageLink(repository: name, count: rows.count { $0.kind == .note }, url: $0)] } ?? []
        case .ping: return []
        }
        let kindRows = rows.filter { $0.kind == kind && !$0.repository.isEmpty }
        var order = repositories
        for row in kindRows where !order.contains(row.repository) { order.append(row.repository) }
        return order.compactMap { repository in
            URL(string: "https://github.com/\(repository)/\(path)").map { url in
                PageLink(repository: repository, count: kindRows.count { $0.repository == repository }, url: url)
            }
        }
    }
}

/// A repository's page for one kind on GitHub, as a header's count chip
/// offers it: the repository, how many of the section's rows of that kind
/// are from it, and the page.
public struct PageLink: Equatable, Sendable {
    public var repository: String
    public var count: Int
    public var url: URL

    public init(repository: String, count: Int, url: URL) {
        self.repository = repository
        self.count = count
        self.url = url
    }
}

/// One chip of a list section's header: a kind, how many rows of it the
/// section lists (shown, behind Show more and in folded subsections), and
/// whether any of them needs attention. The count is never 0: a kind
/// without rows has no chip.
public struct HeaderCount: Equatable, Sendable, Identifiable {
    public var kind: ItemKind
    public var count: Int
    /// Whether at least one of its rows needs attention: never for notes,
    /// which `Attention` never flags.
    public var needsAttention: Bool

    public var id: ItemKind { kind }

    public init(kind: ItemKind, count: Int, needsAttention: Bool) {
        self.kind = kind
        self.count = count
        self.needsAttention = needsAttention
    }

    /// One chip per kind of `kinds` that `rows` has, in that order.
    static func counts(_ rows: [MenuRow], kinds: [ItemKind]) -> [HeaderCount] {
        kinds.compactMap { kind in
            let ofKind = rows.filter { $0.kind == kind }
            guard !ofKind.isEmpty else { return nil }
            return HeaderCount(
                kind: kind,
                count: ofKind.count,
                needsAttention: ofKind.contains(where: \.needsAttention)
            )
        }
    }
}

/// One item in a section.
public struct MenuRow: Equatable, Sendable, Identifiable {
    /// The item's URL.
    public var id: String
    public var kind: ItemKind
    public var repository: String
    public var number: Int
    public var title: String
    public var author: String
    public var authorKind: AuthorKind
    public var url: URL
    /// Open, draft, merged or closed; the app colours it the way GitHub does,
    /// by kind: a pull request open green, draft gray, merged purple, closed
    /// red; an issue (only ever open or closed) open green, closed purple. A
    /// workflow run is running, succeeded or failed.
    public var state: ItemState
    /// A workflow run's branch; `nil` for pull requests and issues. (Its
    /// `title` is the workflow's name.)
    public var branch: String?
    /// The check dot, for open (and draft) pull requests; `nil` otherwise.
    public var checks: ChecksState?
    /// What the age counts from: when it was opened (a run: started), or
    /// for a closed item (a finished run) when it was closed (finished).
    public var since: Date
    /// Whether the item needs attention (unseen, changed since seen, review
    /// requested or checks failed, as `[attention]` allows).
    public var needsAttention: Bool
    /// Why it needs attention; empty when it doesn't.
    public var attentionReasons: [Attention.Reason] = []
    /// The item as fetched: marking the row seen records this version.
    public var item: Item

    public init(_ item: Item, needsAttention: Bool = false) {
        self.item = item
        self.needsAttention = needsAttention
        id = item.id
        kind = item.kind
        repository = item.repository
        number = item.number
        title = item.title
        author = item.author
        authorKind = item.authorKind
        url = item.url
        state = item.state
        branch = item.branch
        checks = item.kind == .pullRequest && item.state.isOpen ? item.checks : nil
        since = item.state.isActive ? item.createdAt : (item.closedAt ?? item.updatedAt)
    }

    /// A ping's icon: what clicking it does (open a link, bring an app
    /// forward, or only mark it seen); `nil` for any other kind.
    public var pingIcon: PingIcon? {
        item.ping.map { $0.action?.icon ?? .noAction }
    }

    /// Who sent a ping (`--from`); `nil` for any other kind, or a ping sent
    /// without one.
    public var sender: String? { item.ping?.sender }

    /// The known agent a ping's sender names, whose logo the row shows by
    /// the sender; `nil` for an unknown sender, none, or any other kind.
    public var agent: KnownAgent? { sender.flatMap(KnownAgent.init(sender:)) }
    /// The machine a remote ping came from, by its Herdr label; `nil` for a
    /// ping sent on this Mac, or any other kind.
    public var machine: String? { item.ping?.machine }

    /// Why a ping's action failed at its last click, shown on its row
    /// until the next click, ⌥-click or dismiss; `nil` otherwise.
    public var actionError: String? { item.ping?.failure }

    /// How old the row is at `now`, never negative.
    public func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(since))
    }
}

/// What the menu bar shows next to the icon.
public enum MenuBarLabel: Equatable, Sendable {
    /// `count = "total"`: the attention count.
    case total(Int)
    /// `count = "per-kind"`: the attention count split by kind.
    case perKind(AttentionCounts)
    /// `count = "none"`, or before anything was fetched: the icon alone.
    case hidden

    public init(_ counts: AttentionCounts, style: MenuBarCount) {
        switch style {
        case .total: self = .total(counts.total)
        case .perKind: self = .perKind(counts)
        case .none: self = .hidden
        }
    }

    /// The text next to the icon, for example "3" or "2 PRs · 1 run";
    /// `nil` when nothing needs attention or the count is hidden.
    public var text: String? {
        switch self {
        case .total(let count):
            return count > 0 ? String(count) : nil
        case .perKind(let counts):
            let parts = [
                Self.part(counts.pullRequests, "PR", "PRs"),
                Self.part(counts.issues, "issue", "issues"),
                Self.part(counts.workflowRuns, "run", "runs"),
                Self.part(counts.pings, "ping", "pings"),
            ].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        case .hidden:
            return nil
        }
    }

    private static func part(_ count: Int, _ one: String, _ many: String) -> String? {
        count > 0 ? "\(count) \(count == 1 ? one : many)" : nil
    }
}

/// A repository that couldn't be fetched, shown inside its project.
public struct MenuErrorRow: Equatable, Sendable, Identifiable {
    public var repository: String
    public var kind: RepositoryError.Kind
    /// For example "yahyabedirhan/gone: not found, or no access".
    public var message: String

    public var id: String { repository }

    public init(_ error: RepositoryError) {
        repository = error.repository
        kind = error.kind
        message = switch error.kind {
        case .notFound: "\(error.repository): not found, or no access"
        case .forbidden: "\(error.repository): access denied (\(error.message))"
        case .incomplete: "\(error.repository): couldn't be read whole (\(error.message))"
        case .other: "\(error.repository): \(error.message)"
        }
    }
}
