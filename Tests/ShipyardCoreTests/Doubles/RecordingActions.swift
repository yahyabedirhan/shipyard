import Foundation
import ShipyardCore
import ShipyardPings

final class RecordingActions: ActionRunning {
    private let urls = Locked<[URL]>([])
    private let actions = Locked<[PingAction]>([])
    private let failing = Locked<String?>(nil)
    private let hook = Locked<(@Sendable () -> Void)?>(nil)

    var opened: [URL] { urls.current }
    var ran: [PingAction] { actions.current }
    var failure: String? {
        get { failing.current }
        set { failing.withValue { $0 = newValue } }
    }

    var whileRunning: (@Sendable () -> Void)? {
        get { hook.current }
        set { hook.withValue { $0 = newValue } }
    }

    func open(_ url: URL) { urls.withValue { $0.append(url) } }

    func run(_ action: PingAction) async -> ActionOutcome {
        actions.withValue { $0.append(action) }
        whileRunning?()
        return failure.map { .failed($0) } ?? .done
    }
}
