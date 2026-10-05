import Foundation

/// What kind of thing an item is.
public enum ItemKind: String, Codable, Equatable, Hashable, Sendable {
    case pullRequest
    case issue
    case workflowRun
    /// A ping an agent sent through the `shipyard` CLI: kept by shipyard,
    /// not fetched from GitHub.
    case ping
    /// One of the user's own notes, kept in Notion: read from the
    /// project's notes database, not fetched from GitHub.
    case note
}

extension ItemKind {
    /// The kinds in the order `shipyard panel show-more` lists them, and
    /// `[menu] header-counts` names them by default.
    public static let commandOrder: [ItemKind] = [.pullRequest, .issue, .workflowRun, .ping, .note]

    /// The kind as `shipyard panel show-more` and `[menu] header-counts`
    /// name it.
    public var commandName: String {
        switch self {
        case .pullRequest: "pull-requests"
        case .issue: "issues"
        case .workflowRun: "workflow-runs"
        case .ping: "pings"
        case .note: "notes"
        }
    }

    /// The kind `name` names, as `commandName` spells it.
    public init?(commandName name: String) {
        guard let kind = Self.commandOrder.first(where: { $0.commandName == name }) else { return nil }
        self = kind
    }
}

/// The values of a kind's `states`: where its items stand, as the file
/// names them. Pull requests take `open`, `merged` and `closed`; issues
/// `open` and `closed`; workflow runs `in-progress`, `failed` and
/// `succeeded` (a timed-out run, or one that never started, is `failed`).
public enum StateGroup: String, CaseIterable, Hashable, Sendable {
    case open
    case merged
    case closed
    case inProgress = "in-progress"
    case failed
    case succeeded

    /// The states `kind` takes, in the order the file writes them: all of
    /// them is that kind's default.
    public static func all(for kind: ItemKind) -> [StateGroup] {
        switch kind {
        case .pullRequest: [.open, .merged, .closed]
        case .issue: [.open, .closed]
        case .workflowRun: [.inProgress, .failed, .succeeded]
        // A ping is always open; pings take no `states`.
        case .ping: [.open]
        // The menu lists open notes only; notes take no `states`.
        case .note: [.open]
        }
    }
}
