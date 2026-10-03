import ShipyardCore

/// A `TailnetIdentity` standing in for asking Tailscale: answers with the
/// Mac's own login it holds (by default, none: Tailscale isn't set up),
/// which a scenario can change, as switching accounts would.
final class FakeTailnet: TailnetIdentity {
    private let answer = Locked<Result<String, TailnetLoginUnknown>>(.failure(TailnetLoginUnknown("Tailscale isn't set up in this test")))

    /// What the Mac's own login is from now on.
    func set(_ login: Result<String, TailnetLoginUnknown>) {
        answer.withValue { $0 = login }
    }

    func ownLogin() async -> Result<String, TailnetLoginUnknown> { answer.current }
}
