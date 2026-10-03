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
    private let answer: @Sendable (ControlRequest, URL, Int) -> Result<Data, ControlTransportFailure>

    /// `answer` gets each request and how many came before it.
    convenience init(answer: @escaping @Sendable (_ request: ControlRequest, _ index: Int) -> Result<Data, ControlTransportFailure>) {
        self.init { request, _, index in answer(request, index) }
    }

    /// `answer` gets each request, the socket it was sent to and how many
    /// came before it: apps at several sockets.
    init(answer: @escaping @Sendable (_ request: ControlRequest, _ socket: URL, _ index: Int) -> Result<Data, ControlTransportFailure>) {
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
        let decoded = try! ControlMessage.decode(request)
        return try answer(decoded.request, socket, index).get()
    }

    /// The messages sent, decoded.
    var messages: [ControlMessage] {
        exchanges.current.map { try! ControlMessage.decode($0.request) }
    }

    /// The requests sent, decoded.
    var requests: [ControlRequest] { messages.map(\.request) }
}

/// A process table in memory: the `shipyard` command is `currentPID`, and
/// `processes` its ancestors and anything else.
struct FakeProcessTable: ProcessTable {
    var currentPID: Int32
    var processes: [ProcessRecord]

    func process(_ pid: Int32) -> ProcessRecord? {
        processes.first { $0.pid == pid }
    }

    /// The tree the command tests run in: `shipyard` (500), run by `zsh`
    /// (400) under the agent `claude` (300), under `launchd` (1).
    static let agent = FakeProcessTable(currentPID: 500, processes: [
        ProcessRecord(pid: 500, parent: 400, started: Date(timeIntervalSince1970: 1_000), name: "shipyard"),
        ProcessRecord(pid: 400, parent: 300, started: Date(timeIntervalSince1970: 900), name: "zsh"),
        ProcessRecord(pid: 300, parent: 1, started: Date(timeIntervalSince1970: 800.25), name: "claude"),
        ProcessRecord(pid: 1, parent: 0, started: Date(timeIntervalSince1970: 0), name: "launchd"),
    ])

    /// The holder `agent`'s tree gives a command run in `place` with no
    /// session variable, as it reads in a request on the wire.
    static func wire(place: String = "/work") -> String {
        #""holder":{"key":"process:300@800250000","name":"claude","place":"\#(place.replacingOccurrences(of: "/", with: #"\/"#))"}"#
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
