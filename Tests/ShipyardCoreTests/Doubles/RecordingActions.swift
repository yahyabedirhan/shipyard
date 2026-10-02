import Foundation
import ShipyardCore

/// An `ActionRunning` that records the URLs it was asked to open and the
/// ping actions it was asked to run. Told to fail (`failure`), it reports
/// that reason for every action, as the app does when an app or a link won't open.
final class RecordingActions: ActionRunning {
    private let urls = Locked<[URL]>([])
    private let actions = Locked<[PingAction]>([])
    private let failing = Locked<String?>(nil)
    private let hook = Locked<(@Sendable () -> Void)?>(nil)

    var opened: [URL] { urls.current }
    /// Every ping action it was asked to run, failed ones too.
    var ran: [PingAction] { actions.current }
    /// The reason every ping action fails with from now on; `nil` (the
    /// default) runs them.
    var failure: String? {
        get { failing.current }
        set { failing.withValue { $0 = newValue } }
    }

    /// What happens while a ping action runs, before it reports back:
    /// the CLI writing to the store meanwhile, say. `nil` (the default): nothing.
    var whileRunning: (@Sendable () -> Void)? {
        get { hook.current }
        set { hook.withValue { $0 = newValue } }
    }

    func open(_ url: URL) { urls.withValue { $0.append(url) } }

    func run(_ action: PingAction) async -> ActionOutcome {
        actions.withValue { $0.append(action) }
        whileRunning?()
        return failure.map(ActionOutcome.failed) ?? .done
    }
}
