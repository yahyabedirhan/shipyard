import Foundation
import ShipyardConfig

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

    /// The model for the projects' `listings` (from `Listing.listings`, by
    /// project name) under `configuration` and what the user has seen and
    /// collapsed; `snapshot` gives the error rows and when it was fetched.
    /// Without a snapshot (no refresh has succeeded yet) every configured
    /// project still gets a section, empty and not loaded yet; so does a
    /// project without a listing (added since the snapshot was fetched).
    /// `expanded` holds the groups Show more revealed past their cap.
    /// `notes` says why a project's notes couldn't be read or a note
    /// couldn't be started (error rows after its others, loaded or not),
    /// and gives each project showing notes its new-note icon once Notion
    /// is connected.
    public static func build(
        listings: [String: [Item]],
        snapshot: Snapshot?,
        configuration: Configuration,
        state: AppState,
        expanded: Set<GroupID> = [],
        notes: NotesMenuState = NotesMenuState(),
        now: Date
    ) -> MenuModel {
        guard let snapshot else {
            // Not loaded yet, but its pings (the listing's only items) show.
            let sections = configuration.projects.map { project in
                MenuSection(
                    name: project.name,
                    groups: Arrangement.groups(
                        listings[project.name] ?? [],
                        project: project.name,
                        settings: configuration.settings(for: project).arrangement,
                        layout: configuration.menu.layout,
                        folded: state.collapsedGroups,
                        expanded: expanded,
                        now: now
                    ),
                    errors: noteErrorRows(notes, project: project.name, configuration: configuration),
                    showsRepository: project.repositories.count > 1,
                    isLoaded: false,
                    repositories: project.repositories.compactMap(\.slug)
                )
            }
            var model = MenuModel(
                sections: newNoteIcons(sections, notes, configuration: configuration) + machineSections(listings, configuration: configuration, state: state, expanded: expanded, now: now),
                layout: configuration.menu.layout
            )
            model.applyAttention(state, configuration: configuration)
            return model
        }
        let sections = configuration.projects.map { project in
            let settings = configuration.settings(for: project)
            let items = listings[project.name] ?? []
            // What the refresh watched for it: its groups and wildcards resolved.
            let repositories = snapshot.repositories[project.name] ?? settings.repositorySlugs
            return MenuSection(
                name: project.name,
                groups: Arrangement.groups(
                    items,
                    project: project.name,
                    settings: settings.arrangement,
                    layout: configuration.menu.layout,
                    folded: state.collapsedGroups,
                    expanded: expanded,
                    now: now
                ),
                // One row per selector that couldn't be resolved, then one
                // per repository, for a kind this project shows: a runs
                // failure isn't an error where runs are off.
                errors: (snapshot.selectorErrors[project.name] ?? []).map(MenuErrorRow.init)
                    + repositories.compactMap { repository in
                        settings.fetchedKinds.lazy
                            .compactMap { snapshot.errors[ItemSource(repository: repository, kind: $0)] }
                            .first
                            .map(MenuErrorRow.init)
                    } + reviewSearchErrors(snapshot, settings: settings)
                    + noteErrorRows(notes, project: project.name, configuration: configuration),
                notes: reviewSearchNotes(snapshot, settings: settings),
                // `anywhere` brings in pull requests from any repository.
                showsRepository: repositories.count > 1 || settings.usesAnywhere,
                // A project added since the snapshot was fetched isn't in it yet.
                isLoaded: snapshot.items[project.name] != nil,
                repositories: repositories
            )
        }
        var model = MenuModel(
            sections: newNoteIcons(sections, notes, configuration: configuration) + machineSections(listings, configuration: configuration, state: state, expanded: expanded, now: now),
            layout: configuration.menu.layout,
            lastUpdated: snapshot.fetchedAt
        )
        model.applyAttention(state, configuration: configuration)
        return model
    }

    /// A section per remote machine whose listing has rows (its pings
    /// filed under no project), after the projects, in the order of
    /// `[remote] machines`. It's named after the machine's label, and
    /// arranged with the defaults.
    private static func machineSections(
        _ listings: [String: [Item]],
        configuration: Configuration,
        state: AppState,
        expanded: Set<GroupID>,
        now: Date
    ) -> [MenuSection] {
        configuration.remote.machines.compactMap { label in
            guard let items = listings[label], !items.isEmpty else { return nil }
            var section = MenuSection(
                name: label,
                groups: Arrangement.groups(
                    items,
                    project: label,
                    settings: configuration.settings(forMachine: label).arrangement,
                    layout: configuration.menu.layout,
                    folded: state.collapsedGroups,
                    expanded: expanded,
                    now: now
                ),
                showsRepository: false
            )
            section.machine = label
            return section
        }
    }

    /// Sets each row's attention flag, each section's count and collapsed
    /// flag, each subsection's fold, the totals and the menu bar label from
    /// `state`, keeping the rows. Clicks, "mark all seen", collapsing and
    /// folding come here without a refresh.
    public mutating func applyAttention(_ state: AppState, configuration: Configuration) {
        let toggles = configuration.attention
        foldedGroups = state.collapsedGroups
        for index in sections.indices {
            for group in sections[index].groups.indices {
                let id = sections[index].groups[group].id
                sections[index].groups[group].isFolded = sections[index].groups[group].showsHeader && state.collapsedGroups.contains(id)
                Self.flagAttention(&sections[index].groups[group].rows, attention: state.attention, toggles: toggles)
                Self.flagAttention(&sections[index].groups[group].hiddenRows, attention: state.attention, toggles: toggles)
                sections[index].groups[group].attentionCount = sections[index].groups[group].allRows.filter(\.needsAttention).count
            }
            sections[index].attentionCount = sections[index].rows.filter(\.needsAttention).count
            sections[index].isCollapsed = state.collapsed.contains(sections[index].name)
        }
        let kinds = Self.headerCountKinds(configuration.menu)
        for index in sections.indices {
            sections[index].headerCounts = HeaderCount.counts(sections[index].rows, kinds: kinds)
        }
        attention = state.attention.counts(sections.flatMap(\.rows).map(\.item), toggles: toggles)
        menuBarLabel = MenuBarLabel(attention, style: configuration.menuBar.count)
    }

    /// Sets each of `rows`' attention flag from `attention`, shown rows and
    /// the rows behind a Show more alike.
    private static func flagAttention(_ rows: inout [MenuRow], attention: Attention, toggles: Configuration.AttentionToggles) {
        for row in rows.indices {
            rows[row].attentionReasons = attention.reasons(rows[row].item, toggles: toggles)
            rows[row].needsAttention = !rows[row].attentionReasons.isEmpty
        }
    }

    /// Caps each project's groups at its `show-first` again, showing every
    /// row of the groups in `expanded`, without a refresh: Show more and
    /// Show less come here, and closing the menu, which caps every group.
    public mutating func applyExpansions(_ expanded: Set<GroupID>, configuration: Configuration) {
        for index in sections.indices {
            let settings: ProjectSettings
            if let machine = sections[index].machine {
                settings = configuration.settings(forMachine: machine)
            } else if let project = configuration.projects.first(where: { $0.name == sections[index].name }) {
                settings = configuration.settings(for: project)
            } else {
                continue
            }
            let showFirst = settings.arrangement.showFirst
            sections[index].groups = sections[index].groups.map { $0.capped(at: showFirst, expanded: expanded.contains($0.id)) }
        }
    }

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

    /// The review search's error row, in a project that needed the search:
    /// one listing only pull requests waiting on the user.
    private static func reviewSearchErrors(_ snapshot: Snapshot, settings: ProjectSettings) -> [MenuErrorRow] {
        guard let error = snapshot.reviewSearchError, settings.pullRequests.show, settings.pullRequests.reviewRequested else { return [] }
        return [MenuErrorRow(error)]
    }

    /// The rows saying why `project`'s notes couldn't be read ("notes:
    /// can't reach Notion (…)") and why a note couldn't be started there
    /// ("new note: …"), while it shows notes.
    private static func noteErrorRows(_ notes: NotesMenuState, project: String, configuration: Configuration) -> [MenuErrorRow] {
        guard showsNotes(project, configuration: configuration) else { return [] }
        return (notes.readErrors[project].map { [MenuErrorRow(.notes($0))] } ?? [])
            + (notes.startErrors[project].map { [MenuErrorRow(.newNote($0))] } ?? [])
    }

    /// `sections` with the new-note icon on each project that shows notes,
    /// while Notion is connected: starting while a note is being started there.
    private static func newNoteIcons(_ sections: [MenuSection], _ notes: NotesMenuState, configuration: Configuration) -> [MenuSection] {
        guard notes.connected else { return sections }
        return sections.map { section in
            guard showsNotes(section.name, configuration: configuration) else { return section }
            var section = section
            section.newNote = notes.starting.contains(section.name) ? .starting : .ready
            return section
        }
    }

    /// Whether the project named `project` lists notes.
    private static func showsNotes(_ project: String, configuration: Configuration) -> Bool {
        configuration.projects.first { $0.name == project }.map { configuration.settings(for: $0).notes.show } ?? false
    }

    /// The note in a project using `anywhere` when the review search
    /// matched more pull requests than its one page holds.
    private static func reviewSearchNotes(_ snapshot: Snapshot, settings: ProjectSettings) -> [String] {
        let shown = snapshot.searchPullRequests.count
        guard settings.usesAnywhere, snapshot.reviewSearchTotal > shown else { return [] }
        return [PanelText.reviewSearchLimit(shown: shown, total: snapshot.reviewSearchTotal)]
    }

    /// The order kinds appear in within a section.
    static let kindOrder: [ItemKind] = [.pullRequest, .ping, .issue, .workflowRun, .note]

    /// The order of the chips in a list section's header. It is the same
    /// list as `ItemKind.commandOrder` on purpose, kept apart so the chips'
    /// order stays fixed whatever that list becomes. The `[menu]
    /// header-counts` default (`Configuration.Menu`) and the schema list
    /// the same order; `ConfigSchemaTests` checks the three agree.
    static let headerCountOrder: [ItemKind] = [.pullRequest, .issue, .workflowRun, .ping, .note]

    /// The kinds a list section's header may count: those `[menu]
    /// header-counts` lists, always in `headerCountOrder`, whatever order
    /// the file lists them in. A section shows a chip only for the ones it
    /// has rows of (`HeaderCount.counts`).
    static func headerCountKinds(_ menu: Configuration.Menu) -> [ItemKind] {
        headerCountOrder.filter { menu.headerCounts.contains($0) }
    }
}

/// One project in the panel.
public struct MenuSection: Equatable, Sendable, Identifiable {
    /// The project's name, unique in the configuration.
    public var name: String
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
    /// Notion is connected (`MenuModel.build`'s `notes`); `nil` hides it.
    public var newNote: NewNoteButton?

    public var id: String { name }

    /// Every row of every group, in order, the ones a cap hides too: what
    /// the counts, "Mark all seen" and the All tab read.
    public var rows: [MenuRow] { groups.flatMap(\.allRows) }

    /// A section whose rows are one group, as `group-by = "none"` makes.
    public init(
        name: String,
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
    /// One link opens at once; several are a menu to choose from. Empty for
    /// pings and notes, which have no page, and for a project without
    /// repositories.
    public func pageLinks(for kind: ItemKind) -> [PageLink] {
        let path: String
        switch kind {
        case .pullRequest: path = "pulls"
        case .issue: path = "issues"
        case .workflowRun: path = "actions"
        case .ping, .note: return []
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
        case .other: "\(error.repository): \(error.message)"
        }
    }
}
