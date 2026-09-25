import Foundation
import os
import ShipyardCore

// Stand-ins for ports later tickets make real. With them the app signs in
// with `gh`'s token and shows pull requests.

/// Keeps a token only while the app runs. The Keychain replaces it (#14);
/// until then nothing is stored, so sign-in always falls back to `gh`.
final class SessionTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?

    func token() throws -> String? {
        lock.withLock { stored }
    }

    func save(_ token: String) throws {
        lock.withLock { stored = token }
    }

    func delete() throws {
        lock.withLock { stored = nil }
    }
}

/// Logs what it would post. The system notification center replaces it (#16).
struct LoggingNotifier: Notifying {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "shipyard", category: "notifications")

    func post(_ notification: PostedNotification) async {
        Self.log.info("would notify: \(notification.title, privacy: .public) · \(notification.body, privacy: .public)")
    }
}
