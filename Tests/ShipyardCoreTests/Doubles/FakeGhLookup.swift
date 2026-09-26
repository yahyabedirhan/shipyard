import ShipyardCore

/// A `GhTokenLookup` standing in for spawning `gh auth token`: returns the
/// token it holds (`nil` for "gh missing or signed out") and counts asks.
/// `token` can be changed, as `gh auth login` and `gh auth logout` would.
final class FakeGhLookup: GhTokenLookup {
    private let value: Locked<String?>
    private let asks = Locked(0)

    init(token: String? = nil) { value = Locked(token) }

    var lookups: Int { asks.current }

    /// What `gh auth token` answers from now on.
    func set(_ token: String?) {
        value.withValue { $0 = token }
    }

    func token() -> String? {
        asks.withValue { $0 += 1 }
        return value.current
    }
}
