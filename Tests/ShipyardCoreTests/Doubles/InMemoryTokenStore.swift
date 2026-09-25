import ShipyardCore

/// A `TokenStore` held in memory, standing in for the Keychain.
final class InMemoryTokenStore: TokenStore {
    private let stored: Locked<String?>

    init(token: String? = nil) { stored = Locked(token) }

    func token() throws -> String? { stored.current }
    func save(_ token: String) throws { stored.withValue { $0 = token } }
    func delete() throws { stored.withValue { $0 = nil } }
}
