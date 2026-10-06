import AppKit
import Observation
import os
import ShipyardCore
import ShipyardNotices
import UserNotifications

/// Posts the core's notifications through the system notification center.
/// It asks for permission the first time there's something to post (never
/// at launch), puts the item's URL in each notification's user info, and
/// hands a click to `onOpen` (the app routes it to
/// `Shipyard.openNotification(_:)`, which opens the item and marks it seen).
/// `onOffChange` tells the app when notifications are turned off or on,
/// for the panel's banner.
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

    private(set) var permission: Permission = .unknown {
        didSet {
            // Its first reading too, off or not, so the app learns the
            // banner's condition is known.
            if oldValue == .unknown || isOff != (oldValue == .denied) { onOffChange?(isOff) }
        }
    }

    /// True when the user turned notifications off: the panel says so.
    var isOff: Bool { permission == .denied }

    /// Called with `isOff` when the permission is first read and whenever
    /// `isOff` changes: the app hands it to
    /// `Shipyard.notificationsAreOff`, the notifications-off banner's condition.
    @ObservationIgnored var onOffChange: (@MainActor (Bool) -> Void)?

    /// Called with the item's URL when the user clicks a notification.
    @ObservationIgnored var onOpen: (@MainActor (URL) -> Void)?

    @ObservationIgnored private let center: UNUserNotificationCenter?
    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "shipyard", category: "notifications")
    /// The user info key that carries `PostedNotification.itemURL`.
    nonisolated private static let itemURLKey = "itemURL"
    /// The user info key that carries each button's URL, in order.
    nonisolated private static let buttonURLsKey = "buttonURLs"
    /// How a button's action identifier starts, before its index.
    nonisolated private static let buttonPrefix = "button "

    override init() {
        // `UNUserNotificationCenter.current()` traps outside an app bundle.
        center = Bundle.main.isAppBundle ? .current() : nil
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

    /// Whether a notification posted now could show: not when the user
    /// turned shipyard's notifications off, read afresh. Run outside a
    /// `.app` bundle, nothing shows.
    func canShow() async -> Bool {
        guard center != nil else { return false }
        await checkPermission()
        return permission != .denied
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

    /// Takes the notification `id` out of Notification Center (a withdrawn
    /// or dismissed ping's). Queued behind the deliveries, so one still
    /// waiting to be posted is posted first, then removed.
    func removeDelivered(id: String) async {
        guard let center else { return }
        let previous = delivery
        delivery = Task {
            await previous?.value
            center.removeDeliveredNotifications(withIdentifiers: [id])
            Self.log.info("removed notification \(id, privacy: .public)")
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
        if let subtitle = notification.subtitle { content.subtitle = subtitle }
        content.body = notification.body
        content.sound = switch notification.sound {
        case .default: .default
        case .silent: nil
        case .named(let name): UNNotificationSound(named: UNNotificationSoundName(name))
        }
        // Groups a project's notifications together in Notification Center,
        // or a notice's thread.
        content.threadIdentifier = notification.thread ?? notification.project
        if let level = notification.level {
            content.interruptionLevel = switch level {
            case .passive: .passive
            case .active: .active
            }
        }
        content.userInfo = [
            Self.itemURLKey: notification.itemURL.absoluteString,
            Self.buttonURLsKey: notification.buttons.map(\.url.absoluteString),
        ]
        if !notification.buttons.isEmpty {
            content.categoryIdentifier = await category(for: notification.buttons, in: center)
        }
        if let image = notification.image, let attachment = Self.attachment(image) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(identifier: notification.id, content: content, trigger: nil)
        do {
            try await center.add(request)
            Self.log.info("notified \(notification.id, privacy: .public): \(notification.title, privacy: .public)")
        } catch {
            Self.log.error("couldn't notify \(notification.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// The categories registered for buttons, by identifier: one per set of
    /// labels, since a category fixes its buttons' titles.
    @ObservationIgnored private var categories: [String: UNNotificationCategory] = [:]

    /// The category whose buttons are `buttons`' labels, in order,
    /// registered with the center first when it's new. A button's action
    /// identifier is `button <index>`, which a press hands back.
    private func category(for buttons: [PostedNotification.Button], in center: UNUserNotificationCenter) async -> String {
        let labels = buttons.map(\.label)
        let identifier = "agent.notice buttons " + labels.joined(separator: "\u{1F}")
        guard categories[identifier] == nil else { return identifier }
        categories[identifier] = UNNotificationCategory(
            identifier: identifier,
            actions: labels.enumerated().map { UNNotificationAction(identifier: Self.buttonPrefix + String($0.offset), title: $0.element) },
            intentIdentifiers: []
        )
        center.setNotificationCategories(Set(categories.values))
        // Reading them back waits until they're set, so the notification
        // posted next shows its buttons.
        _ = await center.notificationCategories()
        return identifier
    }

    /// `image` written to a file of its own and attached: macOS moves the
    /// file into its own store. `nil`, logged, when it can't be.
    private static func attachment(_ image: NoticeImage) -> UNNotificationAttachment? {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipyard-notice-\(UUID().uuidString)")
            .appendingPathExtension((image.name as NSString).pathExtension)
        do {
            try image.data.write(to: file)
            return try UNNotificationAttachment(identifier: "image", url: file)
        } catch {
            try? FileManager.default.removeItem(at: file)
            log.error("couldn't attach the notice's image \(image.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
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

    /// A click: open the item and mark it seen. A button: hand on its own
    /// URL, as a click hands the item's. Dismissing does nothing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        let text: String?
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            text = userInfo[Self.itemURLKey] as? String
        } else if response.actionIdentifier.hasPrefix(Self.buttonPrefix),
                  let index = Int(response.actionIdentifier.dropFirst(Self.buttonPrefix.count)),
                  let urls = userInfo[Self.buttonURLsKey] as? [String], urls.indices.contains(index) {
            text = urls[index]
        } else {
            text = nil
        }
        guard let text, let url = URL(string: text) else { return }
        await MainActor.run {
            Self.log.info("opened from a notification: \(text, privacy: .public)")
            onOpen?(url)
        }
    }
}
