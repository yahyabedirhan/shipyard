import Foundation

/// Onboarding's first step, as the user fills it in: the preset chosen,
/// for `incoming-contributions` whether it watches every repository the
/// account owns, and whether the repository picker comes next. Pure, so the
/// flow is tested without SwiftUI.
///
/// - `my-agents` needs repositories: the picker comes next.
/// - `incoming-contributions` watches `owned` by default and is written at
///   once; picking repositories instead brings the picker.
/// - `review-queue` needs nothing and is written at once.
public struct PresetChoice: Equatable, Sendable {
    /// Where onboarding is.
    public enum Step: Equatable, Sendable {
        /// Choosing a preset.
        case preset
        /// Picking the repositories for the chosen preset.
        case repositories
    }

    /// The chosen preset; `nil` until the user chooses one.
    public var preset: Preset?
    /// For a preset that asks `ownedOrRepositories`: watch every repository
    /// the account owns (`owned`, the default) rather than picked ones.
    public var watchesOwned = true
    public private(set) var step = Step.preset

    public init(preset: Preset? = nil) {
        self.preset = preset
    }

    /// Whether the chosen preset offers "all my repositories" or picking.
    public var offersOwned: Bool {
        preset?.asks == .ownedOrRepositories
    }

    /// Whether the chosen preset still needs the repository picker.
    public var needsRepositories: Bool {
        switch preset?.asks {
        case .repositories: true
        case .ownedOrRepositories: !watchesOwned
        case .nothing, nil: false
        }
    }

    /// Whether the preset step can go on: a preset is chosen.
    public var canContinue: Bool {
        preset != nil
    }

    /// Goes on from the preset step: to the picker when the preset needs
    /// repositories. Returns whether the preset can be written now, with
    /// no projects of its own (`projects(from: [])`).
    public mutating func proceed() -> Bool {
        guard canContinue else { return false }
        if needsRepositories {
            step = .repositories
            return false
        }
        return true
    }

    /// Back from the picker to the preset step, the choice kept.
    public mutating func back() {
        step = .preset
    }

    /// The projects to write with the preset: the picker's when it needs
    /// repositories, none otherwise (the preset watches `owned` or
    /// `anywhere` on its own).
    public func projects(from picked: [NewProject]) -> [NewProject] {
        needsRepositories ? picked : []
    }
}
