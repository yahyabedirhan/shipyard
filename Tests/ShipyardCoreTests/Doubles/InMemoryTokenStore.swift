import ShipyardCore

/// A `TokenStore` held in memory, standing in for the Keychain.
final class InMemoryTokenStore: TokenStore {
    private let stored: Locked<String?>
    private let readCount = Locked(0)

    init(token: String? = nil) { stored = Locked(token) }

    /// How many times the token was read: each read of the Keychain can ask
    /// the user's leave.
    var reads: Int { readCount.current }

    func token() throws -> String? {
        readCount.withValue { $0 += 1 }
        return stored.current
    }
    func save(_ token: String) throws { stored.withValue { $0 = token } }
    func delete() throws { stored.withValue { $0 = nil } }
}
