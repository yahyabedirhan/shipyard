import Foundation
import Security
import ShipyardCore

/// The app's token stores: one generic password each in the login
/// Keychain, so a token survives restarts. The GitHub one (`.github`) holds
/// the token from Sign in with GitHub: `TokenProvider` reads it before
/// asking `gh`; Sign out and a rejected token delete it. The Notion one
/// (`.notion`) holds the token the settings menu's Notion card takes;
/// Disconnect Notion deletes it.
struct Keychain: TokenStore {
    /// The items' service: what Keychain Access lists them under.
    static let service = "com.yahyabedirhan.shipyard"

    /// The GitHub token's item.
    static let github = Keychain(account: "github-token", label: "Shipyard GitHub token")
    /// The Notion token's item.
    static let notion = Keychain(account: "notion-token", label: "Shipyard Notion token")

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

    func delete() throws {
        let status = SecItemDelete(item as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status: status) }
    }
}
