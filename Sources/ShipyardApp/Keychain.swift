import Foundation
import Security
import ShipyardCore

struct Keychain: TokenStore {
    static let service = "com.yahyabedirhan.shipyard"

    static let github = Keychain(account: "github-token", label: "Shipyard GitHub token")
    static let oldNotion = Keychain(account: "notion-token", label: "Shipyard Notion token")

    static let oldNotionRemovedKey = "removedOldNotionToken"

    let account: String
    let label: String

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

    static func removeOldNotionToken(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: oldNotionRemovedKey) else { return }
        defaults.set(true, forKey: oldNotionRemovedKey)
        guard oldNotion.exists() else { return }
        try? oldNotion.delete()
    }

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
