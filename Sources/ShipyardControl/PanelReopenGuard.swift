import Foundation

/// Keeps app control from opening the panel against the user: once the
/// panel closes by anything but app control (the user clicked elsewhere,
/// pressed Escape, clicked the icon or a row), app control can't open it
/// again for `cooldown`. An agent that opens the panel in a loop would
/// otherwise reopen it each time the user's click closes it. A close by
/// app control (`shipyard panel close`) starts no wait.
public struct PanelReopenGuard: Equatable, Sendable {
    /// How long after the user's close app control waits to open the panel.
    public static let cooldown: TimeInterval = 30

    /// When the user last closed the panel; nil once app control closed it.
    private var userClosed: Date?

    public init() {}

    /// The panel closed at `time`, by app control or not.
    public mutating func panelClosed(byControl: Bool, at time: Date) {
        userClosed = byControl ? nil : time
    }

    /// Why app control can't open the panel at `now`, as the agent reads it
    /// in `timeZone`; nil when it can. "you closed the panel 5 seconds ago;
    /// app control can open it again at 15:42:10".
    public func refusal(at now: Date, timeZone: TimeZone) -> String? {
        guard let userClosed else { return nil }
        let reopens = userClosed.addingTimeInterval(Self.cooldown)
        guard now < reopens else { return nil }
        let ago = max(Int(now.timeIntervalSince(userClosed)), 0)
        return "you closed the panel \(ago) second\(ago == 1 ? "" : "s") ago; "
            + "app control can open it again at \(ControlLease.clock(reopens, timeZone))"
    }
}
