import ShipyardCore

final class FakeGhLookup: GhTokenLookup {
    private let value: Locked<String?>
    private let asks = Locked(0)

    init(token: String? = nil) { value = Locked(token) }

    var lookups: Int { asks.current }

    func set(_ token: String?) {
        value.withValue { $0 = token }
    }

    func token() -> String? {
        asks.withValue { $0 += 1 }
        return value.current
    }
}
