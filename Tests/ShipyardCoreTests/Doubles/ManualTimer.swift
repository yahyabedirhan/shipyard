import Foundation
import ShipyardCore

final class ManualTimer: RefreshTimer {
    private struct Arming {
        var delay: TimeInterval
        var fire: @Sendable () async -> Void
    }

    private let state = Locked<Arming?>(nil)

    var armed: TimeInterval? { state.current?.delay }

    func arm(after seconds: TimeInterval, _ fire: @escaping @Sendable () async -> Void) {
        state.withValue { $0 = Arming(delay: seconds, fire: fire) }
    }

    func disarm() {
        state.withValue { $0 = nil }
    }

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
