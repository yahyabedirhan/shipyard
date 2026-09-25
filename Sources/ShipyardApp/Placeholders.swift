import Foundation
import ShipyardCore

// A stand-in for a port a later effort makes real (#22).

/// Keeps a token only while the app runs. 0.0.x connects through `gh` only
/// and never starts the device flow, so nothing is ever saved here and
/// sign-in always uses `gh`'s token. The Keychain replaces it with sign-in
/// without `gh` (#22).
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
