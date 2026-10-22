import Foundation

/// Where a state is in its life: a shared colour a theme names once in its
/// `[phase]` table, for every state in that phase to take.
public enum ThemePhase: String, CaseIterable, Hashable, Sendable {
    /// Not finished: an open pull request or issue, a running run, pending
    /// checks, a review still required, a rate limit with room.
    case active
    /// Finished as hoped: a merged pull request, a closed issue, a succeeded
    /// run, passed checks, an approval.
    case done
    /// Finished another way: a closed pull request, a failed run, failed
    /// checks, changes requested, a spent rate limit.
    case failed
    /// Not ready, or not about work: a draft pull request, a ping, a note.
    case quiet

    /// The macOS colour a phase draws when no theme in the chain sets it, or
    /// it is `system`.
    public var system: SystemShade {
        switch self {
        case .active: SystemShade(.green)
        case .done: SystemShade(.purple)
        case .failed: SystemShade(.red)
        case .quiet: SystemShade(.secondaryLabel)
        }
    }
}

/// A kind of thing a theme colours by state, as its `[states.<kind>]` table
/// names it.
public enum ThemeKind: String, CaseIterable, Hashable, Sendable {
    case pullRequest = "pull-request"
    case issue
    case run
    /// A pull request's checks: its check dot.
    case check
    /// A pull request's review decision.
    case review
    /// GitHub's rate limit: its bar and text.
    case rate
    case ping
    case note

    /// The theme's kind for an item kind.
    public init(_ kind: ItemKind) {
        switch kind {
        case .pullRequest: self = .pullRequest
        case .issue: self = .issue
        case .workflowRun: self = .run
        case .ping: self = .ping
        case .note: self = .note
        }
    }

    /// Each state the kind has, as its table names it, with the phase it
    /// takes when no theme in the chain sets it. A state with no phase, the
    /// rate limit's `low`, is a warning: it draws the macOS orange
    /// (`ThemeKind.warning`).
    public var states: [(name: String, phase: ThemePhase?)] {
        switch self {
        case .pullRequest: [("open", .active), ("draft", .quiet), ("merged", .done), ("closed", .failed)]
        case .issue: [("open", .active), ("closed", .done)]
        case .run: [("running", .active), ("succeeded", .done), ("failed", .failed)]
        case .check: [("pending", .active), ("passed", .done), ("failed", .failed)]
        case .review: [("review-required", .active), ("approved", .done), ("changes-requested", .failed)]
        case .rate: [("normal", .active), ("low", nil), ("exhausted", .failed)]
        case .ping, .note: [("open", .quiet)]
        }
    }

    /// What a state with no phase draws when no theme in the chain sets it,
    /// or it is `system`: the macOS orange.
    public static let warning = SystemShade(.orange)

    /// Whether the kind has `state`.
    public func has(_ state: String) -> Bool {
        states.contains { $0.name == state }
    }

    /// The phase `state` takes by default; `nil` when the kind has no such
    /// state, or the state has no phase.
    public func phase(of state: String) -> ThemePhase? {
        states.first { $0.name == state }?.phase
    }
}

/// One state of one kind, such as a merged pull request.
struct ThemeStateKey: Hashable, Sendable {
    var kind: ThemeKind
    var state: String

    /// The macOS colour `system` means for the state: its phase's, or the
    /// warning orange for a state with no phase.
    var system: SystemShade { kind.phase(of: state)?.system ?? ThemeKind.warning }
}

/// A resolved state or phase colour: a fixed colour, or a macOS colour the
/// app draws live.
public enum ThemeStateColor: Hashable, Sendable {
    case color(RGBA)
    case system(SystemShade)
}
