import Foundation
import ShipyardCore

final class RecordingLoginItem: LoginItem {
    private let log = Locked<[Bool]>([])

    var settings: [Bool] { log.current }

    func setEnabled(_ enabled: Bool) { log.withValue { $0.append(enabled) } }
}
