import ShipyardCore

final class RecordingNotifier: Notifying {
    private let log = Locked<[PostedNotification]>([])
    private let removals = Locked<[String]>([])
    private let permission = Locked(true)

    var posted: [PostedNotification] { log.current }
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
