import Foundation

/// The panel banners the user dismissed: for each banner key
/// (`PanelBanner.id`), when its snooze ends, an hour after the dismissal.
/// A snoozed banner stays hidden until then, whatever its words become;
/// after it, the banner shows again if its condition still holds. A
/// condition that stops clears its snooze (`follow(current:at:)`), so the
/// next time it starts its banner shows at once. Pure: given the time on
/// each call.
public struct BannerSnoozes: Codable, Equatable, Sendable {
    /// How long a dismissal hides a banner.
    public static let length: TimeInterval = 3600

    /// When each snoozed banner key's snooze ends.
    public private(set) var ends: [String: Date]

    public init(ends: [String: Date] = [:]) {
        self.ends = ends
    }

    /// Hides the banner `key` for `length` from `now`.
    public mutating func snooze(_ key: String, at now: Date) {
        ends[key] = now.addingTimeInterval(Self.length)
    }

    /// Whether the banner `key` is hidden at `now`.
    private func isSnoozed(_ key: String, at now: Date) -> Bool {
        ends[key].map { now < $0 } ?? false
    }

    /// `banners` without the ones snoozed at `now`.
    public func shown(_ banners: [PanelBanner], at now: Date) -> [PanelBanner] {
        banners.filter { !isSnoozed($0.id, at: now) }
    }

    /// The snoozes that end after `now`, soonest first: when a hidden
    /// banner may show again.
    public func endsAfter(_ now: Date) -> [Date] {
        ends.values.filter { $0 > now }.sorted()
    }

    /// Drops the snooze of `key`, whose condition stopped and started again
    /// between two looks (one lease handed straight to the next).
    public mutating func clear(_ key: String) {
        ends[key] = nil
    }

    /// Drops the snooze of each key not in `current` (its condition
    /// stopped) and each that ended by `now`.
    public mutating func follow(current: Set<String>, at now: Date) {
        ends = ends.filter { current.contains($0.key) && now < $0.value }
    }
}
