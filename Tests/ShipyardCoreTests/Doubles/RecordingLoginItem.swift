import Foundation
import ShipyardCore

/// A `LoginItem` that records each time it was told to register or remove
/// shipyard as a login item.
final class RecordingLoginItem: LoginItem {
    private let log = Locked<[Bool]>([])

    /// What each `setEnabled` call asked for, in order.
    var settings: [Bool] { log.current }

    func setEnabled(_ enabled: Bool) { log.withValue { $0.append(enabled) } }
}
