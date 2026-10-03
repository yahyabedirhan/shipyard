import Foundation

/// The words of the banner that tops the panel while an agent holds the
/// lease: "Claude Code in shop is using shipyard · 48s · 2 waiting". Made
/// from the lease as `app status` reports it at the moment drawn, so the
/// countdown ticks with the time it's made at. The app finds the agent's
/// logo from `agent` (`KnownAgent`) and draws the parts.
public struct LeaseBanner: Equatable, Sendable {
    /// The holder's name as its request gave it (`Claude Code`), for the logo.
    public var agent: String
    /// Where it runs, short: a working folder's last component (`shop`), or
    /// `Herdr pane <id>` as it is.
    public var place: String
    /// "Claude Code in shop is using shipyard".
    public var headline: String
    /// The time left: `48s` under a minute, `4m 05s` above.
    public var timeLeft: String
    /// `2 waiting` while others queue for the lease; nil when nobody does.
    public var waiting: String?

    public init(_ lease: AppStatus.Lease) {
        agent = lease.holder
        place = lease.place.hasPrefix("/") ? URL(fileURLWithPath: lease.place).lastPathComponent : lease.place
        // A process's name may start lowercase ("codex", "an unknown agent"); the line starts a sentence.
        headline = (lease.holder.prefix(1).uppercased() + lease.holder.dropFirst()) + " in \(place) is using shipyard"
        let minutes = lease.secondsLeft / 60, seconds = lease.secondsLeft % 60
        timeLeft = minutes == 0 ? "\(seconds)s" : "\(minutes)m " + (seconds < 10 ? "0" : "") + "\(seconds)s"
        waiting = lease.waiting > 0 ? "\(lease.waiting) waiting" : nil
    }

    /// The banner as one line, for VoiceOver: its parts joined by ` · `.
    public var text: String {
        ([headline, timeLeft] + (waiting.map { [$0] } ?? [])).joined(separator: " · ")
    }
}
