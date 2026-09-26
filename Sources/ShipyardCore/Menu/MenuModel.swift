import Foundation

/// What the panel draws: one section per project, in configuration order,
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

    public init(
        sections: [MenuSection] = [],
        attention: AttentionCounts = AttentionCounts(),
        menuBarLabel: MenuBarLabel = .hidden,
        layout: MenuLayout = .list,
        lastUpdated: Date? = nil,
        fetchError: GitHubError? = nil,
        refreshDelay: RefreshDelay? = nil,
        rateIndicator: RateIndicator? = nil
    ) {
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
    public static func build(listings: [String: [Item]], snapshot: Snapshot?, configuration: Configuration, state: AppState) -> MenuModel {
        guard let snapshot else {
            let sections = configuration.projects.map { project in
                MenuSection(
                    name: project.name,
                    rows: [],
                    showsRepository: project.repositories.count > 1,
                    isLoaded: false,
                    repositories: project.repositories
                )
            }
            var model = MenuModel(sections: sections, layout: configuration.menu.layout)
            model.applyAttention(state, configuration: configuration)
            return model
        }
        let sections = configuration.projects.map { project in
            let settings = configuration.settings(for: project)
            let items = listings[project.name] ?? []
            // Pull requests, then issues, then runs; each kind open (or
            // running) first, then closed (or finished).
            let rows = kindOrder.flatMap { kind -> [Item] in
                let ofKind = items.filter { $0.kind == kind }
                let open = ofKind.filter(\.state.isActive).sorted { $0.updatedAt > $1.updatedAt }
                let closed = ofKind.filter { !$0.state.isActive }
                    .sorted { ($0.closedAt ?? $0.updatedAt) > ($1.closedAt ?? $1.updatedAt) }
                return open + closed
            }
            return MenuSection(
                name: project.name,
                rows: rows.map { MenuRow($0) },
                // One row per repository, for a kind this project shows: a
                // runs failure isn't an error where runs are off.
                errors: project.repositories.compactMap { repository in
                    settings.fetchedKinds.lazy
                        .compactMap { snapshot.errors[ItemSource(repository: repository, kind: $0)] }
                        .first
                        .map(MenuErrorRow.init)
                } + reviewSearchErrors(snapshot, settings: settings),
                showsRepository: project.repositories.count > 1,
                // A project added since the snapshot was fetched has no listing yet.
                isLoaded: listings[project.name] != nil,
                repositories: project.repositories
            )
        }
        var model = MenuModel(sections: sections, layout: configuration.menu.layout, lastUpdated: snapshot.fetchedAt)
        model.applyAttention(state, configuration: configuration)
        return model
    }

    /// Sets each row's attention flag, each section's count and collapsed
    /// flag, the totals and the menu bar label from `state`, keeping the
    /// rows. Clicks, "mark all seen" and collapsing come here without a refresh.
    public mutating func applyAttention(_ state: AppState, configuration: Configuration) {
        let toggles = configuration.attention
        for index in sections.indices {
            for row in sections[index].rows.indices {
                sections[index].rows[row].needsAttention = state.attention.needsAttention(sections[index].rows[row].item, toggles: toggles)
            }
            sections[index].attentionCount = sections[index].rows.filter(\.needsAttention).count
            sections[index].isCollapsed = state.collapsed.contains(sections[index].name)
        }
        attention = state.attention.counts(sections.flatMap(\.rows).map(\.item), toggles: toggles)
        menuBarLabel = MenuBarLabel(attention, style: configuration.menuBar.count)
    }

    /// The review search's error row, in a project that needed the search:
    /// one listing only pull requests waiting on the user.
    private static func reviewSearchErrors(_ snapshot: Snapshot, settings: ProjectSettings) -> [MenuErrorRow] {
        guard let error = snapshot.reviewSearchError, settings.pullRequests.show, settings.pullRequests.reviewRequested else { return [] }
        return [MenuErrorRow(error)]
    }

    /// The order kinds appear in within a section.
    static let kindOrder: [ItemKind] = [.pullRequest, .issue, .workflowRun]
}

/// One project in the panel.
public struct MenuSection: Equatable, Sendable, Identifiable {
    /// The project's name, unique in the configuration.
    public var name: String
    /// Pull requests, then issues, then workflow runs; within each kind, open
    /// (or running) items first (most recently updated first), then closed
    /// (or finished) ones (most recently closed first), each kind within its
    /// own window.
    public var rows: [MenuRow]
    /// One per repository of this project that couldn't be fetched.
    public var errors: [MenuErrorRow]
    /// Whether a row's second line names its repository: only when the
    /// project has more than one.
    public var showsRepository: Bool
    /// Rows in this section needing attention, for its header.
    public var attentionCount: Int
    /// Whether the user collapsed it. Its rows are still here, and still
    /// count towards the attention count.
    public var isCollapsed: Bool
    /// Whether its rows were fetched: `false` before the first refresh
    /// succeeded, when the section is listed without rows.
    public var isLoaded: Bool
    /// The project's repositories (`owner/name`), in configuration order.
    public var repositories: [String]

    public var id: String { name }

    public init(
        name: String,
        rows: [MenuRow],
        errors: [MenuErrorRow] = [],
        showsRepository: Bool = false,
        attentionCount: Int = 0,
        isCollapsed: Bool = false,
        isLoaded: Bool = true,
        repositories: [String] = []
    ) {
        self.name = name
        self.rows = rows
        self.errors = errors
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
