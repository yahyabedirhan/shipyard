import Foundation
import ShipyardCore

/// A `RefreshTimer` that never fires on its own: a test reads what it was
/// armed with and fires it.
final class ManualTimer: RefreshTimer {
    private struct Arming {
        var delay: TimeInterval
        var fire: @Sendable () async -> Void
    }

    private let state = Locked<Arming?>(nil)
    private let log = Locked<[TimeInterval]>([])

    /// The delay the timer is armed with now; `nil` when disarmed.
    var armed: TimeInterval? { state.current?.delay }
    /// Every delay it was armed with, in order.
    var armings: [TimeInterval] { log.current }

    func arm(after seconds: TimeInterval, _ fire: @escaping @Sendable () async -> Void) {
        state.withValue { $0 = Arming(delay: seconds, fire: fire) }
        log.withValue { $0.append(seconds) }
    }

    func disarm() {
        state.withValue { $0 = nil }
    }

    /// Fires the armed timer as if its delay passed, and waits for what it
    /// runs. Returns false when it wasn't armed.
    @discardableResult
    func fire() async -> Bool {
        let taken = state.withValue { (state: inout Arming?) -> Arming? in
            defer { state = nil }
            return state
        }
        guard let arming = taken else { return false }
        await arming.fire()
        return true
    }
}
