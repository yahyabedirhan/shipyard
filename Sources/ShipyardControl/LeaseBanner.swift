import Foundation

/// The words of the banner that tops the panel while an agent holds the
/// lease: "Claude Code uses shipyard", then why ("Checking the header
/// icons") when its `take` said, what it's doing ("Taking a screenshot…",
/// or "Took a screenshot · 12s ago" once done), and "shop · 48s · 2
/// waiting". Made
/// from the lease as `app status` reports it at the moment drawn, so the
/// countdown ticks with the time it's made at. The app finds the agent's
/// logo from `agent` (`KnownAgent`) and draws the parts.
public struct LeaseBanner: Equatable, Sendable {
    /// The holder's name as its request gave it (`Claude Code`), for the logo.
    public var agent: String
    /// Where it runs, short: a working folder's last component (`shop`), or
    /// `Herdr pane <id>` as it is.
    public var place: String
    /// The banner's first line, "Claude Code uses shipyard".
    public var title: String
    /// The time left: `48s` under a minute, `4m 05s` above.
    public var timeLeft: String
    /// `2 waiting` while others queue for the lease; nil when nobody does.
    public var waiting: String?
    /// Why the agent took shipyard, its first letter capitalized; nil when
    /// it didn't say.
    public var purpose: String?
    /// What the agent is doing, or last did and when; nil before its first step.
    public var step: String?

    public init(_ lease: AppStatus.Lease) {
        agent = lease.holder
        place = lease.place.hasPrefix("/") ? URL(fileURLWithPath: lease.place).lastPathComponent : lease.place
        // A process's name may start lowercase ("codex", "an unknown agent"); the line starts a sentence.
        title = (lease.holder.prefix(1).uppercased() + lease.holder.dropFirst()) + " uses shipyard"
        let minutes = lease.secondsLeft / 60, seconds = lease.secondsLeft % 60
        timeLeft = minutes == 0 ? "\(seconds)s" : "\(minutes)m " + (seconds < 10 ? "0" : "") + "\(seconds)s"
        waiting = lease.waiting > 0 ? "\(lease.waiting) waiting" : nil
        purpose = lease.purpose.map { $0.prefix(1).uppercased() + $0.dropFirst() }
        step = lease.step
    }

    /// The banner's second line, smaller: the place, the time left and how
    /// many wait, joined by ` · `, so a Herdr pane's whole id shows.
    public var detail: String {
        ([place, timeLeft] + (waiting.map { [$0] } ?? [])).joined(separator: " · ")
    }

    /// The banner as one line, for VoiceOver: every line joined by ` · `.
    public var text: String {
        ([title] + [purpose, step].compactMap { $0 } + [detail]).joined(separator: " · ")
    }

    /// The banner's button, which takes shipyard back from the holder.
    public static let stop = "Stop"

    /// The quiet line while a holder the maintainer stopped is barred,
    /// "You took shipyard back from Claude Code", the agent's name as its
    /// requests gave it; `allow`, its button, lets it back.
    public static func tookBack(from agent: String) -> String {
        "You took shipyard back from \(agent)"
    }

    /// The quiet line's button, which lets the stopped holder back.
    public static let allow = "Allow"
}
