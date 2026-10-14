import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore

final class FakeNtnRoute: HTTPTransport {
    enum State: Sendable {
        case missing
        case loggedOut
        case loggedIn
    }

    private let state: Locked<State>
    private let sent = Locked(0)
    private let notion: StubHTTP

    init(_ state: State = .missing, notion: StubHTTP) {
        self.state = Locked(state)
        self.notion = notion
    }

    var current: State { state.current }

    var runs: Int { sent.current }

    func set(_ state: State) { self.state.withValue { $0 = state } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        sent.withValue { $0 += 1 }
        switch state.current {
        case .missing:
            throw NotionError.ntnMissing
        case .loggedOut:
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!)
        case .loggedIn:
            return try await notion.send(request)
        }
    }
}
