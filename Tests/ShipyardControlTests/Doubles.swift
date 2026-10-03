import Foundation
import ShipyardCommand
import ShipyardControl

/// A value several threads read and change, behind a lock.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withValue<T>(_ change: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return change(&value)
    }

    var current: Value { withValue { $0 } }
}

/// The app's end of the socket, in memory: each exchange is recorded, with
/// the socket and timeout it was sent with, and answered by `answer`.
final class FakeTransport: ControlTransport {
    struct Exchange: Equatable {
        var request: Data
        var socket: URL
        var timeout: TimeInterval
    }

    let exchanges = Locked<[Exchange]>([])
    private let answer: @Sendable (ControlRequest, Int) -> Result<Data, ControlTransportFailure>

    /// `answer` gets each request and how many came before it.
    init(answer: @escaping @Sendable (_ request: ControlRequest, _ index: Int) -> Result<Data, ControlTransportFailure>) {
        self.answer = answer
    }

    /// An app that answers every request with `reply`.
    convenience init(reply: ControlReply) {
        self.init { _, _ in .success(reply.encoded()) }
    }

    /// No app: nothing listens.
    static var nothingListens: FakeTransport { FakeTransport { _, _ in .failure(.notRunning) } }

    func exchange(_ request: Data, socket: URL, timeout: TimeInterval) throws(ControlTransportFailure) -> Data {
        let index = exchanges.withValue { list in
            list.append(Exchange(request: request, socket: socket, timeout: timeout))
            return list.count - 1
        }
        // A request the CLI sent always reads; a test that fails here broke the encoding.
        let decoded = try! ControlRequest.decode(request)
        return try answer(decoded, index).get()
    }

    /// The requests sent, decoded.
    var requests: [ControlRequest] {
        exchanges.current.map { try! ControlRequest.decode($0.request) }
    }
}

/// A launcher that records each launch and fails with `failure` when set.
final class RecordingLauncher: AppLaunching {
    struct Launch: Equatable {
        var bundleID: String
        var environment: [String: String]
    }

    let launches = Locked<[Launch]>([])
    let failure: AppLaunchFailure?

    init(failure: AppLaunchFailure? = nil) {
        self.failure = failure
    }

    func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure) {
        launches.withValue { $0.append(Launch(bundleID: bundleID, environment: environment)) }
        if let failure { throw failure }
    }
}
