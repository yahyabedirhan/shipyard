import ShipyardCore

final class FakeTailnet: TailnetIdentity {
    private let answer = Locked<Result<String, TailnetLoginUnknown>>(.failure(TailnetLoginUnknown("Tailscale isn't set up in this test")))

    func set(_ login: Result<String, TailnetLoginUnknown>) {
        answer.withValue { $0 = login }
    }

    func ownLogin() async -> Result<String, TailnetLoginUnknown> { answer.current }
}
