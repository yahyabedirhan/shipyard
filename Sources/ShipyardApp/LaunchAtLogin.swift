import Foundation
import os
import ServiceManagement
import ShipyardCore

/// The `LoginItem` port on `SMAppService.mainApp`: registers the running
/// `.app` as a login item, or removes it. The work runs in order on a queue
/// of its own, off the main thread.
///
/// Registering when the item is already enabled, or waiting for the user's
/// approval (they turned it off in System Settings > General > Login Items),
/// changes nothing, so a relaunch never overrides that switch; removing
/// covers both. Outside a `.app` bundle (`make run`) there's no app to
/// register, and it only logs.
final class LaunchAtLogin: LoginItem {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "shipyard", category: "login-item")
    private let queue = DispatchQueue(label: "shipyard.login-item")

    func setEnabled(_ enabled: Bool) {
        guard Bundle.main.isAppBundle else {
            Self.log.info("not in an app bundle: launch at login (\(enabled, privacy: .public)) not applied")
            return
        }
        queue.async { Self.apply(enabled) }
    }

    private static func apply(_ enabled: Bool) {
        let service = SMAppService.mainApp
        let status = service.status
        let registered = status == .enabled || status == .requiresApproval
        guard enabled != registered else { return }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            log.info("launch at login \(enabled ? "registered" : "removed", privacy: .public): \(String(describing: service.status), privacy: .public)")
        } catch {
            log.error("launch at login (\(enabled, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
