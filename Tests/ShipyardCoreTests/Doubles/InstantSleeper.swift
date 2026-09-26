import Foundation
import ShipyardCore

/// Stands in for real waiting: each sleep returns at once, moves the manual
/// clock on by the time asked and records it. A hook can act during a sleep,
/// for example to look at the phase or cancel.
final class InstantSleeper: Sendable {
    typealias Hook = @Sendable (_ index: Int, _ seconds: TimeInterval) async -> Void

    let clock: ManualClock
    private let log = Locked<[TimeInterval]>([])
    private let hook = Locked<Hook?>(nil)

    init(clock: ManualClock) { self.clock = clock }

    /// Every sleep asked for, in seconds, in order.
    var slept: [TimeInterval] { log.current }

    /// Runs `body` during every sleep, with the sleep's index (from 0).
    func onSleep(_ body: @escaping Hook) { hook.withValue { $0 = body } }

    var sleep: Sleep {
        { [self] seconds in
            let index = log.withValue { log in
                log.append(seconds)
                return log.count - 1
            }
            clock.advance(by: seconds)
            if let body = hook.current { await body(index, seconds) }
            try Task.checkCancellation()
        }
    }
}
