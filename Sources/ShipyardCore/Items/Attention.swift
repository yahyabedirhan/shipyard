import Foundation

/// Owns the needs-attention rule next to the data it reads: which version of
/// each item the user has seen.
///
/// An item needs attention when it's open and unseen, or changed since it
/// was seen, or requests the viewer's review, or has failed checks, each
/// switchable in `[attention]`. Seeing an item clears all of them until its
/// fingerprint changes again, whoever made the change (the user's own pushes,
/// made by their agents, count). Closed and merged items never need attention.
/// A workflow run needs attention only once it failed (its `checks` are
/// failed too, so `checks-failed` covers it); running and succeeded runs never do.
///
/// The rule is keyed on `Item`, so pull requests, issues and workflow runs
/// share it; `counts` splits by kind.
public struct Attention: Equatable, Sendable {
    /// The version of an item the user saw, and when shipyard last found the
    /// item on GitHub (for pruning records of items that are gone).
    public struct SeenRecord: Codable, Equatable, Sendable {
        /// `Item.fingerprint` when it was seen.
        public var fingerprint: String
        /// When it was seen, or later, the last refresh that still listed it
        /// (bumped at most once a day, so the file isn't rewritten every refresh).
        public var present: Date

        public init(fingerprint: String, present: Date) {
            self.fingerprint = fingerprint
            self.present = present
        }
    }

    /// How long a seen record outlives its item's last appearance.
    public static let retention: TimeInterval = 30 * 86_400
    /// How stale `present` may get before a refresh bumps it.
    static let presenceResolution: TimeInterval = 86_400

    /// Seen records by item id (the item's URL).
    public private(set) var seen: [String: SeenRecord]

    public init(seen: [String: SeenRecord] = [:]) {
        self.seen = seen
    }

    /// Whether `item` needs attention under `toggles`.
    public func needsAttention(_ item: Item, toggles: Configuration.AttentionToggles) -> Bool {
        guard Self.canNeedAttention(item) else { return false }
        let seenPrint = seen[item.id]?.fingerprint
        if seenPrint == item.fingerprint { return false }
        let standing = (toggles.reviewRequested && item.reviewRequestedFromViewer)
            || (toggles.checksFailed && item.checks == .failed)
        if seenPrint == nil { return toggles.unseen || standing }
        return toggles.changed || standing
    }

    /// Whether an item in this state may need attention at all: open ones
    /// (drafts included) and failed workflow runs. Closed, merged, running
    /// and succeeded never do.
    static func canNeedAttention(_ item: Item) -> Bool {
        item.state.isOpen || item.state == .failed
    }

    /// Records the version of `item` the user has seen now.
    public mutating func markSeen(_ item: Item, at now: Date) {
        markSeen(id: item.id, fingerprint: item.fingerprint, at: now)
    }

    /// Records that the user saw the version of item `id` with `fingerprint`,
    /// for when only what's known about the item is at hand (a notification
    /// clicked before a refresh listed it again).
    public mutating func markSeen(id: String, fingerprint: String, at now: Date) {
        seen[id] = SeenRecord(fingerprint: fingerprint, present: now)
    }

    /// How many of `items` need attention, per kind. An item listed twice
    /// (a repository in two projects) counts once.
    public func counts(_ items: some Sequence<Item>, toggles: Configuration.AttentionToggles) -> AttentionCounts {
        var counts = AttentionCounts()
        var counted = Set<String>()
        for item in items where needsAttention(item, toggles: toggles) && counted.insert(item.id).inserted {
            counts.add(item.kind)
        }
        return counts
    }

    /// Notes which items a refresh found and drops the records of items
    /// missing for longer than `retention`. Returns whether anything changed,
    /// so the caller saves only then.
    @discardableResult
    public mutating func prune(present items: some Sequence<Item>, at now: Date) -> Bool {
        var changed = false
        for item in items {
            guard let record = seen[item.id], now.timeIntervalSince(record.present) >= Self.presenceResolution else { continue }
            seen[item.id]?.present = now
            changed = true
        }
        let cutoff = now.addingTimeInterval(-Self.retention)
        let before = seen.count
        seen = seen.filter { $0.value.present >= cutoff }
        return changed || seen.count != before
    }
}

/// Items needing attention, per kind, and in total.
public struct AttentionCounts: Equatable, Sendable {
    public var pullRequests: Int
    public var issues: Int
    public var workflowRuns: Int

    public init(pullRequests: Int = 0, issues: Int = 0, workflowRuns: Int = 0) {
        self.pullRequests = pullRequests
        self.issues = issues
        self.workflowRuns = workflowRuns
    }

    /// The attention count.
    public var total: Int { pullRequests + issues + workflowRuns }

    public subscript(kind: ItemKind) -> Int {
        switch kind {
        case .pullRequest: pullRequests
        case .issue: issues
        case .workflowRun: workflowRuns
        }
    }

    mutating func add(_ kind: ItemKind) {
        switch kind {
        case .pullRequest: pullRequests += 1
        case .issue: issues += 1
        case .workflowRun: workflowRuns += 1
        }
    }
}
