import Foundation

/// What the panel draws: one section per project, in configuration order,
/// and when the list was last brought up to date. Every display rule (what
/// the closed window keeps, drafts, hidden authors, order, state and check
/// dot) lives here, so tests reach them without SwiftUI.
public struct MenuModel: Equatable, Sendable {
    public var sections: [MenuSection]
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
        lastUpdated: Date? = nil,
        fetchError: GitHubError? = nil,
        refreshDelay: RefreshDelay? = nil,
        rateIndicator: RateIndicator? = nil
    ) {
        self.sections = sections
        self.lastUpdated = lastUpdated
        self.fetchError = fetchError
        self.refreshDelay = refreshDelay
        self.rateIndicator = rateIndicator
    }

    /// Whether ⌘R and the Refresh button work: not while paused.
    public var canRefreshNow: Bool { !(refreshDelay?.isPaused ?? false) }

    /// Before anything was fetched.
    public static let empty = MenuModel()

    /// The model for `snapshot` under `configuration`, as of `now` (which
    /// the closed window counts back from).
    public static func build(snapshot: Snapshot, configuration: Configuration, now: Date) -> MenuModel {
        let hidden = Set(configuration.hideAuthors.map { $0.lowercased() })
        let sections = configuration.projects.map { project in
            let settings = configuration.settings(for: project)
            let items = (snapshot.items[project.name] ?? []).filter {
                shows($0, settings: settings, hiddenAuthors: hidden, now: now)
            }
            let open = items.filter(\.state.isOpen).sorted { $0.updatedAt > $1.updatedAt }
            let closed = items.filter { !$0.state.isOpen }.sorted { ($0.closedAt ?? $0.updatedAt) > ($1.closedAt ?? $1.updatedAt) }
            return MenuSection(
                name: project.name,
                rows: (open + closed).map(MenuRow.init),
                errors: project.repositories.compactMap { snapshot.errors[$0].map(MenuErrorRow.init) }
            )
        }
        return MenuModel(sections: sections, lastUpdated: snapshot.fetchedAt)
    }

    private static func shows(_ item: Item, settings: ProjectSettings, hiddenAuthors: Set<String>, now: Date) -> Bool {
        guard item.kind == .pullRequest, settings.pullRequests.show else { return false }
        if hiddenAuthors.contains(item.author.lowercased()) { return false }
        if item.state == .draft, !settings.pullRequests.drafts { return false }
        if !item.state.isOpen {
            let days = settings.pullRequests.closedWindowDays
            guard days > 0, let closedAt = item.closedAt else { return false }
            return closedAt >= now.addingTimeInterval(-TimeInterval(days) * 86_400)
        }
        return true
    }
}

/// One project in the panel.
public struct MenuSection: Equatable, Sendable, Identifiable {
    /// The project's name, unique in the configuration.
    public var name: String
    /// Open items first (most recently updated first), then closed ones
    /// (most recently closed first).
    public var rows: [MenuRow]
    /// One per repository of this project that couldn't be fetched.
    public var errors: [MenuErrorRow]

    public var id: String { name }

    public init(name: String, rows: [MenuRow], errors: [MenuErrorRow] = []) {
        self.name = name
        self.rows = rows
        self.errors = errors
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
    /// Open, draft, merged or closed; the app colours it the way GitHub does.
    public var state: ItemState
    /// The check dot, for open (and draft) pull requests; `nil` otherwise.
    public var checks: ChecksState?
    /// What the age counts from: when it was opened, or for a closed item
    /// when it was closed.
    public var since: Date

    public init(_ item: Item) {
        id = item.id
        kind = item.kind
        repository = item.repository
        number = item.number
        title = item.title
        author = item.author
        authorKind = item.authorKind
        url = item.url
        state = item.state
        checks = item.kind == .pullRequest && item.state.isOpen ? item.checks : nil
        since = item.state.isOpen ? item.createdAt : (item.closedAt ?? item.updatedAt)
    }

    /// How old the row is at `now`, never negative.
    public func age(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(since))
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
