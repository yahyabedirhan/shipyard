import ShipyardCore

/// A `Notifying` that records what was posted, in order.
final class RecordingNotifier: Notifying {
    private let log = Locked<[PostedNotification]>([])

    var posted: [PostedNotification] { log.current }

    func post(_ notification: PostedNotification) async {
        log.withValue { $0.append(notification) }
    }
}
