import Foundation
import ShipyardCommand
import ShipyardCore

final class InstantSleeper: Sendable {
    typealias Hook = @Sendable (_ index: Int, _ seconds: TimeInterval) async -> Void

    let clock: ManualClock
    private let log = Locked<[TimeInterval]>([])
    private let hook = Locked<Hook?>(nil)

    init(clock: ManualClock) { self.clock = clock }

    var slept: [TimeInterval] { log.current }

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
