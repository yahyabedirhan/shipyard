import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore

/// ntn, as the notes go through it (`NtnCLI`), standing in for the CLI:
/// not installed until a scenario installs it; logged in, it sends each
/// request on to `notion`, the stub with Notion's recorded answers.
final class FakeNtnRoute: HTTPTransport {
    enum State: Sendable {
        /// No `ntn` where the app looks.
        case missing
        /// ntn is there, but not logged in: every request is a 401, as `NtnCLI` reads exit 4.
        case loggedOut
        /// ntn is logged in to the notes workspace.
        case loggedIn
    }

    private let state: Locked<State>
    private let sent = Locked(0)
    private let notion: StubHTTP

    init(_ state: State = .missing, notion: StubHTTP) {
        self.state = Locked(state)
        self.notion = notion
    }

    /// How ntn is now.
    var current: State { state.current }

    /// How many times the app ran ntn, whatever ntn's state: once per request.
    var runs: Int { sent.current }

    /// Installs, logs in or logs out ntn, or takes it away.
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
