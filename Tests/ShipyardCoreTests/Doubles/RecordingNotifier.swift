import ShipyardCore

/// A `Notifying` that records what was posted, and which delivered
/// notifications were removed, in order. `allowed` is whether the user
/// lets shipyard's notifications show.
final class RecordingNotifier: Notifying {
    private let log = Locked<[PostedNotification]>([])
    private let removals = Locked<[String]>([])
    private let permission = Locked(true)

    var posted: [PostedNotification] { log.current }
    /// The ids of the notifications asked to leave Notification Center.
    var removed: [String] { removals.current }
    var allowed: Bool {
        get { permission.current }
        set { permission.withValue { $0 = newValue } }
    }

    func post(_ notification: PostedNotification) async {
        log.withValue { $0.append(notification) }
    }

    func removeDelivered(id: String) async {
        removals.withValue { $0.append(id) }
    }

    func canShow() async -> Bool { allowed }
}
