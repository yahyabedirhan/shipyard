import Foundation

/// Where a state is in its life: a shared colour a theme names once in its
/// `[phase]` table, for every state in that phase to take.
public enum ThemePhase: String, CaseIterable, Hashable, Sendable {
    /// Not finished: an open pull request or issue, a running run.
    case active
    /// Finished as hoped: a merged pull request, a closed issue, a succeeded run.
    case done
    /// Finished another way: a closed pull request, a failed run.
    case failed
    /// Not ready: a draft pull request.
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

/// A kind of item a theme colours by state, as its `[states.<kind>]` table
/// names it.
public enum ThemeKind: String, CaseIterable, Hashable, Sendable {
    case pullRequest = "pull-request"
    case issue
    case run

    /// The theme's kind for an item kind; `nil` for a kind the theme doesn't
    /// colour by state.
    public init?(_ kind: ItemKind) {
        switch kind {
        case .pullRequest: self = .pullRequest
        case .issue: self = .issue
        case .workflowRun: self = .run
        case .ping, .note: return nil
        }
    }

    /// Each state the kind has, as its table names it, with the phase it
    /// takes when no theme in the chain sets it.
    public var states: [(name: String, phase: ThemePhase)] {
        switch self {
        case .pullRequest: [("open", .active), ("draft", .quiet), ("merged", .done), ("closed", .failed)]
        case .issue: [("open", .active), ("closed", .done)]
        case .run: [("running", .active), ("succeeded", .done), ("failed", .failed)]
        }
    }

    /// The phase `state` takes by default; `nil` when the kind has no such state.
    public func phase(of state: String) -> ThemePhase? {
        states.first { $0.name == state }?.phase
    }
}

/// One state of one kind, such as a merged pull request.
struct ThemeStateKey: Hashable, Sendable {
    var kind: ThemeKind
    var state: String

    /// The phase the state takes by default. The reader makes a key only
    /// for a state its kind has.
    var phase: ThemePhase { kind.phase(of: state)! }
}

/// A resolved state or phase colour: a fixed colour, or a macOS colour the
/// app draws live.
public enum ThemeStateColor: Hashable, Sendable {
    case color(RGBA)
    case system(SystemShade)
}
