import Foundation

/// A change in an item that shipyard can notify about, such as `pr.opened`,
/// found by comparing the known items with a new snapshot.
public struct Event: Equatable, Hashable, Sendable {
    public var kind: EventKind
    /// The project the item was listed in. An item in two projects makes an
    /// event in each; the pipeline notifies it once.
    public var project: String
    /// The item as the snapshot has it.
    public var item: Item
    /// Tells this occurrence apart from others of the same event on the same
    /// item: empty for events that happen once in an item's life (opened,
    /// merged), the item's fingerprint for ones that can recur (a second
    /// failure, another comment, closing again after a reopen).
    public var occurrence: String

    public init(kind: EventKind, project: String, item: Item, occurrence: String = "") {
        self.kind = kind
        self.project = project
        self.item = item
        self.occurrence = occurrence
    }

    /// Unique per occurrence and the same in every project, so it's notified
    /// at most once: `pr.opened https://github.com/o/r/pull/57`, or with the
    /// occurrence after it.
    public var id: String {
        occurrence.isEmpty ? "\(kind.rawValue) \(item.id)" : "\(kind.rawValue) \(item.id) \(occurrence)"
    }

    /// What the notification says, for example "New PR #57".
    public var headline: String { kind.headline(number: item.number) }
}

/// What happened to an item between two refreshes, whatever its kind. The
/// detector finds changes; `EventKind.of(_:for:)` names them per kind, so a
/// new kind of item only adds names (and, for its own states, changes).
public enum ItemChange: Equatable, Hashable, Sendable {
    /// First listed, open (drafts included).
    case opened
    /// Open before, merged now.
    case merged
    /// Open before, closed (without merging) now.
    case closed
    /// Closed before, open again.
    case reopened
    /// Now asks for the viewer's review, and didn't before.
    case reviewRequested
    /// Checks failed now, and hadn't before.
    case checksFailed
    /// More comments and reviews than before.
    case commented
    /// A workflow run failed: found failed, or failed after it wasn't (a re-run).
    case failed
    /// A workflow run succeeded: found succeeded, or succeeded after it wasn't.
    case succeeded

    /// Whether it can happen only once in an item's life.
    var happensOnce: Bool { self == .opened || self == .merged }
}

extension EventKind {
    /// The event a change makes for an item of `kind`; `nil` when there's
    /// no such event (an issue can't be merged).
    public static func of(_ change: ItemChange, for kind: ItemKind) -> EventKind? {
        switch (kind, change) {
        case (.pullRequest, .opened): .prOpened
        case (.pullRequest, .merged): .prMerged
        case (.pullRequest, .closed): .prClosed
        case (.pullRequest, .reopened): .prReopened
        case (.pullRequest, .reviewRequested): .prReviewRequested
        case (.pullRequest, .checksFailed): .prChecksFailed
        case (.pullRequest, .commented): .prCommented
        case (.issue, .opened): .issueOpened
        case (.issue, .closed): .issueClosed
        case (.issue, .commented): .issueCommented
        case (.workflowRun, .failed): .runFailed
        case (.workflowRun, .succeeded): .runSucceeded
        // An issue reopened is no event (the spec lists none); its next
        // close is `issue.closed` again, as a new occurrence.
        default: nil
        }
    }

    /// A notification's title text for the item numbered `number`, such as
    /// "New PR #57".
    public func headline(number: Int) -> String {
        switch self {
        case .prOpened: "New PR #\(number)"
        case .prMerged: "Merged PR #\(number)"
        case .prClosed: "Closed PR #\(number)"
        case .prReopened: "Reopened PR #\(number)"
        case .prReviewRequested: "Review requested on PR #\(number)"
        case .prChecksFailed: "Checks failed on PR #\(number)"
        case .prCommented: "New comment on PR #\(number)"
        case .issueOpened: "New issue #\(number)"
        case .issueClosed: "Closed issue #\(number)"
        case .issueCommented: "New comment on issue #\(number)"
        case .runFailed: "Run #\(number) failed"
        case .runSucceeded: "Run #\(number) succeeded"
        }
    }
}

/// Where a project's items of one kind come from: one of its repositories.
/// The first refresh that fetches a source for a project is silent.
public struct ItemSource: Codable, Equatable, Hashable, Sendable, Comparable {
    public var repository: String
    public var kind: ItemKind

    public init(repository: String, kind: ItemKind) {
        self.repository = repository
        self.kind = kind
    }

    /// The review search, for a project using `anywhere`: where its pull
    /// requests from repositories it doesn't watch come from. It isn't
    /// `owner/name`, so no repository shares it.
    public static let anywhere = ItemSource(repository: RepositorySelector.anywhereName, kind: .pullRequest)

    public static func < (lhs: ItemSource, rhs: ItemSource) -> Bool {
        (lhs.kind.rawValue, lhs.repository) < (rhs.kind.rawValue, rhs.repository)
    }
}

/// The last version of an item a refresh found: what the detector compares
/// the next snapshot with.
public struct KnownItem: Codable, Equatable, Sendable {
    /// `owner/name`, as the project lists it.
    public var repository: String
    public var state: ItemState
    public var checks: ChecksState
    public var reviewRequested: Bool
    public var activity: Int
    /// `Item.fingerprint`, so a notification's item can be marked seen
    /// before a refresh has listed it again.
    public var fingerprint: String
    /// When a refresh last listed the item, bumped at most once a day (like
    /// `Attention.SeenRecord.present`). An item missing from a snapshot is
    /// kept until it's been gone for `Attention.retention`.
    public var present: Date

    public init(_ item: Item, present: Date) {
        repository = item.repository
        state = item.state
        checks = item.checks
        reviewRequested = item.reviewRequestedFromViewer
        activity = item.activity
        fingerprint = item.fingerprint
        self.present = present
    }

    private enum CodingKeys: String, CodingKey {
        case repository, state, checks, reviewRequested, activity, fingerprint, present
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        repository = try container.decode(String.self, forKey: .repository)
        state = try container.decode(ItemState.self, forKey: .state)
        checks = try container.decode(ChecksState.self, forKey: .checks)
        reviewRequested = try container.decode(Bool.self, forKey: .reviewRequested)
        activity = try container.decode(Int.self, forKey: .activity)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        // A file from before `present` was kept: the item is kept while
        // it's listed, and dropped the first time it isn't, as it was then.
        present = try container.decodeIfPresent(Date.self, forKey: .present) ?? .distantPast
    }
}

/// What the refreshes so far have found: every item's last version, and
/// which sources each project has been fetched from. App state.
public struct KnownItems: Equatable, Sendable {
    /// By item id (its URL).
    public var items: [String: KnownItem]
    /// By project name: the sources fetched for it at least once.
    public var sources: [String: Set<ItemSource>]

    public init(items: [String: KnownItem] = [:], sources: [String: Set<ItemSource>] = [:]) {
        self.items = items
        self.sources = sources
    }

    /// Whether the project's items from `source` were fetched before, so
    /// changes in them are events.
    public func knows(_ source: ItemSource, in project: String) -> Bool {
        sources[project]?.contains(source) ?? false
    }

    /// What's known after `snapshot`, fetched for `projects`: the snapshot's
    /// items and the sources it fetched. A source that failed keeps its
    /// sources from before, so its return isn't a burst of events. An item
    /// missing from the snapshot (it fell out of the most recent 50, or its
    /// repository failed) is kept for `Attention.retention`, and while its
    /// repository fails, so when it comes back it's compared with its last
    /// version rather than announced as new. A project, repository or kind
    /// no longer fetched is forgotten, so adding it again is a first sight.
    public func updated(with snapshot: Snapshot, projects: [ProjectSettings]) -> KnownItems {
        var next = KnownItems()
        var failed = Set(snapshot.errors.keys)
        // A failed search answered with the last one's pull requests (none
        // after a launch): its first answer is still a first sight.
        if snapshot.reviewSearchError != nil { failed.insert(.anywhere) }
        // The search's pull requests can be in any repository, so while a
        // project uses it, items of repositories no project watches are kept too.
        let keepsAnyRepository = projects.contains(where: \.usesAnywhere)
        var fetched = Set<String>()
        for project in projects {
            var sources = Set<ItemSource>()
            for source in project.fetchedSources {
                fetched.insert(source.repository.lowercased())
                if !failed.contains(source) || knows(source, in: project.name) {
                    sources.insert(source)
                }
            }
            if !sources.isEmpty { next.sources[project.name] = sources }
        }
        let now = snapshot.fetchedAt
        let cutoff = now.addingTimeInterval(-Attention.retention)
        let failedRepositories = Set(failed.map { $0.repository.lowercased() })
        for (id, item) in items {
            let repository = item.repository.lowercased()
            guard fetched.contains(repository) || keepsAnyRepository else { continue }
            if item.present >= cutoff || failedRepositories.contains(repository) {
                next.items[id] = item
            }
        }
        for item in snapshot.items.values.joined() {
            let before = items[item.id]?.present
            let present = before.map { now.timeIntervalSince($0) < Attention.presenceResolution ? $0 : now } ?? now
            var known = KnownItem(item, present: present)
            // The review search sees only open pull requests: a closed one
            // keeps the request it had, so reopening it isn't a new request.
            if item.kind == .pullRequest, !item.state.isOpen, let earlier = items[item.id] {
                known.reviewRequested = earlier.reviewRequested
            }
            next.items[item.id] = known
        }
        return next
    }
}

extension ProjectSettings {
    /// The sources a refresh fetches for this project: each repository, for
    /// each kind the project shows.
    var fetchedSources: [ItemSource] {
        repositorySlugs.flatMap { repository in fetchedKinds.map { ItemSource(repository: repository, kind: $0) } }
            + (usesAnywhere ? [.anywhere] : [])
    }

    /// Where the project's `item` came from: its repository, or the review
    /// search for a pull request `anywhere` found in a repository the
    /// project doesn't watch.
    func source(of item: Item) -> ItemSource {
        let watched = !usesAnywhere || item.kind != .pullRequest
            || repositorySlugs.contains { $0.caseInsensitiveCompare(item.repository) == .orderedSame }
        return watched ? ItemSource(repository: item.repository, kind: item.kind) : .anywhere
    }

    /// The kinds this project shows, in the menu's order.
    var fetchedKinds: [ItemKind] {
        [ItemKind.pullRequest, .issue, .workflowRun].filter { shows($0) }
    }
}

/// Finds events by comparing the known items with a new snapshot. Pure.
///
/// Items from a source a project hasn't been fetched from before (the first
/// refresh ever, a project or repository just added, a kind just shown)
/// make no events: they're recorded, not announced. Every event is found
/// whether or not a rule selects it, so a rule added later behaves the same.
public enum EventDetector {
    /// The events in `snapshot`, per project in `projects`' order, then in
    /// the snapshot's order.
    public static func events(known: KnownItems, snapshot: Snapshot, projects: [ProjectSettings]) -> [Event] {
        projects.flatMap { project in
            (snapshot.items[project.name] ?? []).flatMap { item -> [Event] in
                let source = project.source(of: item)
                guard known.knows(source, in: project.name) else { return [] }
                let before = known.items[item.id]
                var found = changes(from: before, to: item)
                // A pull request the search finds for the first time is a
                // review request that just arrived, as well as a new item.
                if source == .anywhere, before == nil, item.state.isOpen, item.reviewRequestedFromViewer {
                    found.append(.reviewRequested)
                }
                return found.compactMap { change in
                    EventKind.of(change, for: item.kind).map {
                        Event(kind: $0, project: project.name, item: item, occurrence: change.happensOnce ? "" : item.fingerprint)
                    }
                }
            }
        }
    }

    /// What changed from `before` (`nil` when the item wasn't known) to `item`.
    /// An item first found already closed makes nothing: it may be an old
    /// one coming back into the closed list. A workflow run is different: one
    /// first found finished ran between two refreshes (the runs asked for are
    /// only recent ones), so it failed or succeeded now.
    static func changes(from before: KnownItem?, to item: Item) -> [ItemChange] {
        if item.kind == .workflowRun {
            if item.state == .failed, before?.state != .failed { return [.failed] }
            if item.state == .succeeded, before?.state != .succeeded { return [.succeeded] }
            return []
        }
        guard let before else { return item.state.isOpen ? [.opened] : [] }
        var changes: [ItemChange] = []
        if before.state.isOpen {
            if item.state == .merged { changes.append(.merged) }
            if item.state == .closed { changes.append(.closed) }
        } else if item.state.isOpen {
            changes.append(.reopened)
        }
        if item.state.isOpen {
            if item.reviewRequestedFromViewer, !before.reviewRequested { changes.append(.reviewRequested) }
            if item.checks == .failed, before.checks != .failed { changes.append(.checksFailed) }
        }
        if item.activity > before.activity { changes.append(.commented) }
        return changes
    }
}
