import Foundation
import Security
import ShipyardCore

/// The app's token store: a generic password in the login Keychain, so a
/// token survives restarts. The GitHub one (`.github`) holds the token
/// from Sign in with GitHub: `TokenProvider` reads it before asking `gh`;
/// Sign out and a rejected token delete it. The notes keep no token: they
/// go through ntn's own login (ADR 0012).
struct Keychain: TokenStore {
    /// The items' service: what Keychain Access lists them under.
    static let service = "com.yahyabedirhan.shipyard"

    /// The GitHub token's item.
    static let github = Keychain(account: "github-token", label: "Shipyard GitHub token")
    /// The Notion token's item, which builds before ADR 0012 kept: only
    /// ever deleted now (`removeOldNotionToken`).
    static let oldNotion = Keychain(account: "notion-token", label: "Shipyard Notion token")

    /// Whether `removeOldNotionToken` has run on this Mac, in the app's defaults.
    static let oldNotionRemovedKey = "removedOldNotionToken"

    /// The item's account, under the service.
    let account: String
    /// The item's name in Keychain Access.
    let label: String

    /// A Keychain call failed with this `OSStatus`.
    struct Failure: Error, Equatable {
        let status: OSStatus
    }

    private var item: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
    }

    func token() throws -> String? {
        var query = item
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Failure(status: status)
        }
    }

    func save(_ token: String) throws {
        let data = Data(token.utf8)
        let updated = SecItemUpdate(item as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        switch updated {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var attributes = item
            attributes[kSecValueData as String] = data
            attributes[kSecAttrLabel as String] = label
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let added = SecItemAdd(attributes as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(status: added) }
        default:
            throw Failure(status: updated)
        }
    }

    /// Deletes the Notion token builds before ADR 0012 kept, once: the
    /// first launch looks for the item by its attributes alone, which
    /// reads no secret and asks nothing, and deletes it when it's there.
    /// Later launches don't look again, so a delete macOS asked about and
    /// the user refused isn't asked again.
    static func removeOldNotionToken(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: oldNotionRemovedKey) else { return }
        defaults.set(true, forKey: oldNotionRemovedKey)
        guard oldNotion.exists() else { return }
        try? oldNotion.delete()
    }

    /// Whether the item is there, from its attributes alone.
    func exists() -> Bool {
        var query = item
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    func delete() throws {
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
