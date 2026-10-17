import Foundation

/// Copied from `Sources/ShipyardCore/Items/Attention.swift`, trimmed to what
/// the panel's views read: the reasons a row needs attention. The rule itself
/// (seen records, `[attention]` toggles) stays in the app; fixtures set each
/// row's reasons directly.
public enum Attention {
    /// One of the reasons an item needs attention, as `[attention]` names them.
    public enum Reason: Equatable, Hashable, Sendable {
        /// Never seen.
        case unseen
        /// Changed since it was seen.
        case changed
        /// Waits on the viewer's review.
        case reviewRequested
        /// Its checks failed (a workflow run: it failed).
        case checksFailed
    }
}

/// Items needing attention, per kind, and in total.
public struct AttentionCounts: Equatable, Sendable {
    public var pullRequests: Int
    public var issues: Int
    public var workflowRuns: Int
    public var pings: Int

    public init(pullRequests: Int = 0, issues: Int = 0, workflowRuns: Int = 0, pings: Int = 0) {
        self.pullRequests = pullRequests
        self.issues = issues
        self.workflowRuns = workflowRuns
        self.pings = pings
    }

    /// The attention count.
    public var total: Int { pullRequests + issues + workflowRuns + pings }

    mutating func add(_ kind: ItemKind) {
        switch kind {
        case .pullRequest: pullRequests += 1
        case .issue: issues += 1
        case .workflowRun: workflowRuns += 1
        case .ping: pings += 1
        // Never: a note doesn't need attention.
        case .note: break
        }
    }
}
