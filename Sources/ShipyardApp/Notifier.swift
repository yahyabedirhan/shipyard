import AppKit
import Observation
import os
import ShipyardCore
import UserNotifications

/// Posts the core's notifications through the system notification center.
/// It asks for permission the first time there's something to post (never
/// at launch), puts the item's URL in each notification's user info, and
/// hands a click to `onOpen` (the app routes it to
/// `Shipyard.openNotification(_:)`, which opens the item and marks it seen).
/// The panel reads `isOff` to say when notifications are turned off.
///
/// Run outside a `.app` bundle (`make run`), there is no notification
/// center to post to, so it only logs.
@MainActor
@Observable
final class Notifier: NSObject, Notifying {
    /// Whether macOS lets shipyard post, as far as shipyard knows.
    enum Permission {
        /// Not checked yet.
        case unknown
        /// Never asked: the first notification asks.
        case notAsked
        /// Allowed, provisionally or for good.
        case allowed
        /// The user said no, or turned shipyard's notifications off.
        case denied
    }

    private(set) var permission: Permission = .unknown

    /// True when the user turned notifications off: the panel says so.
    var isOff: Bool { permission == .denied }

    /// Called with the item's URL when the user clicks a notification.
    @ObservationIgnored var onOpen: (@MainActor (URL) -> Void)?

    @ObservationIgnored private let center: UNUserNotificationCenter?
    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "shipyard", category: "notifications")
    /// The user info key that carries `PostedNotification.itemURL`.
    nonisolated private static let itemURLKey = "itemURL"

    override init() {
        // `UNUserNotificationCenter.current()` traps outside an app bundle.
        center = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
        super.init()
        // Set before launch finishes, so a click that launched the app arrives.
        center?.delegate = self
    }

    /// Reads the permission without asking for it: at launch, and when the
    /// panel opens (the user may have changed it in System Settings).
    func checkPermission() async {
        guard let center else { return }
        permission = Self.permission(await center.notificationSettings().authorizationStatus)
    }

    /// Queues the notification and returns at once: the first one waits
    /// for the user to answer the permission prompt, which must not hold up
    /// the refresh that posted it. Notifications are delivered in order.
    func post(_ notification: PostedNotification) async {
        guard let center else {
            Self.log.info("no notification center; would notify: \(notification.title, privacy: .public) · \(notification.body, privacy: .public)")
            return
        }
        let previous = delivery
        delivery = Task {
            await previous?.value
            await deliver(notification, to: center)
        }
    }

    /// The last queued delivery; the next one waits for it.
    @ObservationIgnored private var delivery: Task<Void, Never>?

    private func deliver(_ notification: PostedNotification, to center: UNUserNotificationCenter) async {
        guard await isAllowed(center) else {
            Self.log.info("notifications are off; dropped \(notification.id, privacy: .public)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        // Groups a project's notifications together in Notification Center.
        content.threadIdentifier = notification.project
        content.userInfo = [Self.itemURLKey: notification.itemURL.absoluteString]
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
        do {
            try await center.add(request)
            Self.log.info("notified \(notification.id, privacy: .public): \(notification.title, privacy: .public)")
        } catch {
            Self.log.error("couldn't notify \(notification.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether shipyard may post, asking the user the first time.
    private func isAllowed(_ center: UNUserNotificationCenter) async -> Bool {
        await checkPermission()
        if permission == .notAsked {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            Self.log.info("asked for notification permission: \(granted ? "allowed" : "denied", privacy: .public)")
            await checkPermission()
        }
        return permission == .allowed
    }

    private static func permission(_ status: UNAuthorizationStatus) -> Permission {
        switch status {
        case .notDetermined: .notAsked
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        // A status added later: try to post; the center refuses harmlessly.
        @unknown default: .allowed
        }
    }

    /// Opens System Settings at shipyard's notification settings.
    func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    /// Shows the banner even while shipyard's panel is open (the app is
    /// then frontmost, and macOS would otherwise stay quiet).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// A click: open the item and mark it seen. Dismissing does nothing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let text = response.notification.request.content.userInfo[Self.itemURLKey] as? String,
              let url = URL(string: text)
        else { return }
        await MainActor.run {
            Self.log.info("opened from a notification: \(text, privacy: .public)")
            onOpen?(url)
        }
    }
}
