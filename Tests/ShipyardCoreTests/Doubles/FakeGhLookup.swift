import ShipyardCore

/// A `GhTokenLookup` standing in for spawning `gh auth token`: returns the
/// token it was given (`nil` for "gh missing or signed out") and counts asks.
final class FakeGhLookup: GhTokenLookup {
    private let value: String?
    private let asks = Locked(0)

    init(token: String? = nil) { value = token }

    var lookups: Int { asks.current }

    func token() -> String? {
        asks.withValue { $0 += 1 }
        return value
    }
}
