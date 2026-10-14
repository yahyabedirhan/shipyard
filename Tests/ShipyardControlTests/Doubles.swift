import Foundation
import ShipyardCommand
import ShipyardControl

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

final class FakeTransport: ControlTransport {
    struct Exchange: Equatable {
        var request: Data
        var socket: URL
        var timeout: TimeInterval
    }

    let exchanges = Locked<[Exchange]>([])
    private let answer: @Sendable (ControlRequest, URL, Int) -> Result<Data, ControlTransportFailure>

    convenience init(answer: @escaping @Sendable (_ request: ControlRequest, _ index: Int) -> Result<Data, ControlTransportFailure>) {
        self.init { request, _, index in answer(request, index) }
    }

    init(answer: @escaping @Sendable (_ request: ControlRequest, _ socket: URL, _ index: Int) -> Result<Data, ControlTransportFailure>) {
        self.answer = answer
    }

    convenience init(reply: ControlReply) {
        self.init { _, _ in .success(reply.encoded()) }
    }

    static var nothingListens: FakeTransport { FakeTransport { _, _ in .failure(.notRunning) } }

    func exchange(_ request: Data, socket: URL, timeout: TimeInterval) throws(ControlTransportFailure) -> Data {
        let index = exchanges.withValue { list in
            list.append(Exchange(request: request, socket: socket, timeout: timeout))
            return list.count - 1
        }
        let decoded = try! ControlMessage.decode(request)
        return try answer(decoded.request, socket, index).get()
    }

    var messages: [ControlMessage] {
        exchanges.current.map { try! ControlMessage.decode($0.request) }
    }

    var requests: [ControlRequest] { messages.map(\.request) }
}

struct FakeProcessTable: ProcessTable {
    var currentPID: Int32
    var processes: [ProcessRecord]

    func process(_ pid: Int32) -> ProcessRecord? {
        processes.first { $0.pid == pid }
    }

    static let agent = FakeProcessTable(currentPID: 500, processes: [
        ProcessRecord(pid: 500, parent: 400, started: Date(timeIntervalSince1970: 1_000), name: "shipyard"),
        ProcessRecord(pid: 400, parent: 300, started: Date(timeIntervalSince1970: 900), name: "zsh"),
        ProcessRecord(pid: 300, parent: 1, started: Date(timeIntervalSince1970: 800.25), name: "claude"),
        ProcessRecord(pid: 1, parent: 0, started: Date(timeIntervalSince1970: 0), name: "launchd"),
    ])

    static func wire(place: String = "/work") -> String {
        #""holder":{"key":"process:300@800250000","name":"claude","place":"\#(place.replacingOccurrences(of: "/", with: #"\/"#))"}"#
    }
}

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
