import Foundation
import ShipyardConfig

/// A change in who holds app control's lease that the user hears of: an
/// agent started using shipyard, or is done with it. The app makes one
/// from each lease that starts or ends (never a renewal or a relaunch's
/// handover) and hands it to `Shipyard.notify(_:)`. Core doesn't link app
/// control, so it's told only the agent's name, its place and why it ended.
public enum ControlNotice: Equatable, Sendable {
    /// `agent` (`Claude Code`) in `place` (a folder, or `Herdr pane <id>`)
    /// took the lease.
    case started(agent: String, place: String)
    /// `agent`'s lease ended, for `reason`.
    case ended(agent: String, reason: Reason)

    /// Why a lease ended, as the user reads it.
    public enum Reason: Equatable, Sendable {
        /// The agent released it.
        case released
        /// It ran out: no command for a while, or its longest term reached.
        case ranOut
        /// The user stopped it from the panel's banner.
        case stopped

        /// The notification's body: "released", "its lease ran out", "you stopped it".
        public var text: String {
            switch self {
            case .released: "released"
            case .ranOut: "its lease ran out"
            case .stopped: "you stopped it"
            }
        }
    }

    /// The event a notification rule names to select it.
    public var event: EventKind {
        switch self {
        case .started: .controlStarted
        case .ended: .controlEnded
        }
    }

    /// The notification's title: "Claude Code is using shipyard", "Claude
    /// Code is done with shipyard". A process's name may start lowercase
    /// ("codex", "an unknown agent"); the title starts a sentence.
    public var headline: String {
        switch self {
        case .started(let agent, _): "\(Self.sentence(agent)) is using shipyard"
        case .ended(let agent, _): "\(Self.sentence(agent)) is done with shipyard"
        }
    }

    private static func sentence(_ agent: String) -> String {
        agent.prefix(1).uppercased() + agent.dropFirst()
    }

    /// The notification's body: where the agent runs, or why it's done.
    public var body: String {
        switch self {
        case .started(_, let place): place
        case .ended(_, let reason): reason.text
        }
    }

    /// What a lease notification carries as its item: clicking it opens
    /// the panel, where the banner shows who holds shipyard, rather than
    /// anything on GitHub.
    public static let panelURL = URL(string: "shipyard://panel")!
}
