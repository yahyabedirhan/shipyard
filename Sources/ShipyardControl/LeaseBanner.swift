import Foundation

/// The words of the banner that tops the panel while an agent holds the
/// lease, in two lines: the headline, why the agent took shipyard
/// ("Checking the header icons") or "Claude Code uses shipyard" when its
/// `take` didn't say; then a smaller line with what the agent is doing
/// ("Taking a screenshot…", or "Took a screenshot · 12s ago" once done) and
/// how many wait, its logo naming it; and the time left beside Stop ("4m 05s left"). Where it
/// runs is the banner's tooltip. Made from the lease as `app status`
/// reports it at the moment drawn, so the countdown ticks with the time
/// it's made at. The app finds the agent's logo from `agent` (`KnownAgent`)
/// and draws the parts.
public struct LeaseBanner: Equatable, Sendable {
    /// The holder's name as its request gave it (`Claude Code`), for the logo.
    public var agent: String
    /// Where it runs, short: a working folder's last component (`shop`), or
    /// `Herdr pane <id>` as it is.
    public var place: String
    /// The first line: the purpose, its first letter capitalized, or
    /// "Claude Code uses shipyard" when the agent didn't say why.
    public var headline: String
    /// The time left, beside Stop: `48s left` under a minute, `4m 05s left` above.
    public var timeLeft: String
    /// `2 waiting` while others queue for the lease; nil when nobody does.
    public var waiting: String?
    /// What the agent is doing, or last did and when; nil before its first step.
    public var step: String?
    /// The second line, smaller: the step and how many wait, joined by
    /// ` · `; nil when there's nothing to say. The logo names the agent.
    public var detail: String?

    public init(_ lease: AppStatus.Lease) {
        agent = lease.holder
        place = lease.place.hasPrefix("/") ? URL(fileURLWithPath: lease.place).lastPathComponent : lease.place
        // A process's name may start lowercase ("codex", "an unknown agent"); each line starts a sentence.
        headline = lease.purpose.map(Self.capitalized) ?? Self.capitalized(lease.holder) + " uses shipyard"
        let minutes = lease.secondsLeft / 60, seconds = lease.secondsLeft % 60
        timeLeft = (minutes == 0 ? "\(seconds)s" : "\(minutes)m " + (seconds < 10 ? "0" : "") + "\(seconds)s") + " left"
        waiting = lease.waiting > 0 ? "\(lease.waiting) waiting" : nil
        step = lease.step
        let parts = [step, waiting].compactMap { $0 }
        detail = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The banner's tooltip: who runs where, "Claude Code in Herdr pane w1-2".
    public var help: String {
        "\(agent) in \(place)"
    }

    /// The banner as one line, for VoiceOver: every line and the tooltip joined by ` · `.
    public var text: String {
        ([headline, detail, timeLeft, help].compactMap { $0 }).joined(separator: " · ")
    }

    private static func capitalized(_ words: String) -> String {
        words.prefix(1).uppercased() + words.dropFirst()
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
    public static let allow = "Allow again"
}
