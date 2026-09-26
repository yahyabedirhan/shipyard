import Foundation
import ShipyardCore

/// A `WallClock` that stays where a test puts it.
final class ManualClock: WallClock {
    private let time: Locked<Date>

    init(_ now: Date = Date(timeIntervalSince1970: 1_790_000_000)) { time = Locked(now) }

    var now: Date { time.current }

    func advance(by seconds: TimeInterval) { time.withValue { $0 += seconds } }
    func set(_ date: Date) { time.withValue { $0 = date } }
}
