import AppKit
import Observation
import os
import ShipyardCore
import ShipyardNotices
import UserNotifications

@MainActor
@Observable
final class Notifier: NSObject, Notifying {
    enum Permission {
        case unknown
        case notAsked
        case allowed
        case denied
    }

    private(set) var permission: Permission = .unknown {
        didSet {
            if oldValue == .unknown || isOff != (oldValue == .denied) { onOffChange?(isOff) }
        }
    }

    var isOff: Bool { permission == .denied }

    @ObservationIgnored var onOffChange: (@MainActor (Bool) -> Void)?

    @ObservationIgnored var onOpen: (@MainActor (URL) -> Void)?

    @ObservationIgnored private let center: UNUserNotificationCenter?
    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "shipyard", category: "notifications")
    nonisolated private static let itemURLKey = "itemURL"
    nonisolated private static let buttonURLsKey = "buttonURLs"
    nonisolated private static let buttonPrefix = "button "

    override init() {
        center = Bundle.main.isAppBundle ? .current() : nil
        super.init()
        center?.delegate = self
    }

    func checkPermission() async {
        guard let center else { return }
        permission = Self.permission(await center.notificationSettings().authorizationStatus)
    }

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

    func removeDelivered(id: String) async {
        guard let center else { return }
        let previous = delivery
        delivery = Task {
            await previous?.value
            center.removeDeliveredNotifications(withIdentifiers: [id])
            Self.log.info("removed notification \(id, privacy: .public)")
        }
    }

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

    @ObservationIgnored private var categories: [String: UNNotificationCategory] = [:]

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
        _ = await center.notificationCategories()
        return identifier
    }

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
        @unknown default: .allowed
        }
    }

    func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension Notifier: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

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
