import Darwin
import Foundation
@testable import ShipyardApp
import ShipyardCLISettings
import ShipyardCommand
import ShipyardNotices
import Testing

/// The app's listener for notices from other machines, on a real socket:
/// bound to 127.0.0.1 alone, it hands each `POST /notify` on with its
/// `Tailscale-User-Login` and answers with the verdict, reached by the
/// command's own tailnet route as `tailscale serve` would pass it on.
@Suite("The notice listener")
struct NoticeListenerTests {
    /// What the listener handed on.
    final class Handed: @unchecked Sendable {
        private let lock = NSLock()
        private var value: [(NoticeRequest, String?)] = []
        var all: [(NoticeRequest, String?)] { lock.withLock { value } }
        func add(_ request: NoticeRequest, _ login: String?) { lock.withLock { value.append((request, login)) } }
    }

    /// A listener on a free port answering `verdict`, recording into `handed`.
    func listener(_ handed: Handed, verdict: NoticeVerdict = .shown) throws -> NoticeListener {
        try NoticeListener.start(port: 0) { request, login in
            handed.add(request, login)
            return verdict
        }
    }

    /// Sends `request` to 127.0.0.1:`port` as raw bytes and reads the whole answer.
    func exchange(_ request: String, port: Int) async throws -> String {
        // Off the cooperative pool: a blocking read there could starve the
        // listener's own tasks, which answer on it.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(with: Result { try Self.blockingExchange(request, port: port) }) }
        }
    }

    /// `body`, which blocks (the command's route waits on a semaphore), run
    /// on a thread of its own rather than the cooperative pool.
    static func offPool<T: Sendable>(_ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async { continuation.resume(returning: body()) }
        }
    }

    static func blockingExchange(_ request: String, port: Int) throws -> String {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        try #require(connected == 0)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = request.withCString { send(descriptor, $0, strlen($0), 0) }
        var answer = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(descriptor, &buffer, buffer.count, 0)
            guard count > 0 else { break }
            answer.append(contentsOf: buffer[0..<count])
        }
        return String(decoding: answer, as: UTF8.self)
    }

    @Test("it binds to 127.0.0.1 only: loopback reaches it, the Mac's other addresses don't")
    func loopbackOnly() throws {
        let listener = try listener(Handed())
        defer { listener.close() }

        #expect(Self.connects(to: "127.0.0.1", port: listener.port))
        #expect(!Self.otherIPv4Addresses().isEmpty, "no other address to try")
        for other in Self.otherIPv4Addresses() {
            #expect(!Self.connects(to: other, port: listener.port), "reachable at \(other)")
        }
    }

    @Test("a notice posted by the command's tailnet route is handed on with the login tailscale serve adds, and its verdict comes back")
    func handsOn() async throws {
        let handed = Handed()
        let listener = try listener(handed, verdict: .refused("notices are off for project `shop`"))
        defer { listener.close() }
        let route = TailnetNoticeRoute(appMachine: "127.0.0.1", scheme: .http, port: listener.port)
        let notice = Notice(title: "Deployed", body: "to staging", sender: "claude", repository: "owner/shop")

        // The route waits on a semaphore, so it runs off the cooperative pool.
        let verdict = await Self.offPool { route.deliver(.show(notice), environment: CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/"), variables: [:])) }

        #expect(verdict == .refused("notices are off for project `shop`"))
        #expect(handed.all.map(\.0) == [.show(notice)])
        // The command sends no login: only tailscale serve adds one.
        #expect(handed.all.map(\.1) == [nil])

        let raw = try await exchange(
            "POST /notify HTTP/1.1\r\nHost: my-mac:47420\r\nTailscale-User-Login: me@example.com\r\n"
                + "Content-Type: application/json\r\nContent-Length: 17\r\n\r\n{\"title\":\"Done\"}\n",
            port: listener.port
        )
        #expect(raw.hasPrefix("HTTP/1.1 200 "))
        #expect(raw.hasSuffix(#"{"refused":"notices are off for project `shop`"}"#))
        #expect(handed.all.last?.1 == "me@example.com")
        #expect(handed.all.last?.0 == .show(Notice(title: "Done")))
    }

    @Test("a notice with the largest image the command sends is read whole and handed on; a withdrawal is handed on too")
    func largeAndWithdraw() async throws {
        let handed = Handed()
        let listener = try listener(handed)
        defer { listener.close() }
        let route = TailnetNoticeRoute(appMachine: "127.0.0.1", scheme: .http, port: listener.port)
        let image = NoticeImage(name: "screen.gif", data: Data(repeating: 0x47, count: Notice.largestImage))
        let notice = Notice(title: "Screenshot", project: "shop", image: image)
        let environment = CommandEnvironment(workingDirectory: URL(fileURLWithPath: "/"), variables: [:])

        let shown = await Self.offPool { route.deliver(.show(notice), environment: environment) }
        let withdrawn = await Self.offPool { route.deliver(.withdraw(id: "tests"), environment: environment) }

        #expect(shown == .shown)
        #expect(withdrawn == .shown)
        #expect(handed.all.map(\.0) == [.show(notice), .withdraw(id: "tests")])
    }

    @Test("what isn't a notice posted by the command is refused with a verdict and never handed on", arguments: [
        ("GET /notify HTTP/1.1\r\nHost: m\r\n\r\n", "405", "post the notice to /notify"),
        ("POST /other HTTP/1.1\r\nHost: m\r\nContent-Length: 2\r\n\r\n{}", "404", "shipyard takes notices at /notify only"),
        ("POST /notify HTTP/1.1\r\nHost: m\r\nOrigin: https://evil.example\r\nContent-Length: 16\r\n\r\n{\"title\":\"Done\"}",
         "403", "shipyard takes notices from the shipyard command only, never from a web page"),
        ("POST /notify HTTP/1.1\r\nHost: m\r\nSec-Fetch-Site: cross-site\r\nContent-Length: 16\r\n\r\n{\"title\":\"Done\"}",
         "403", "shipyard takes notices from the shipyard command only, never from a web page"),
        ("POST /notify HTTP/1.1\r\nHost: m\r\nContent-Length: 8\r\n\r\nnot json", "400", "the request didn't read as a notice's JSON, so nothing was done"),
        ("POST /notify HTTP/1.1\r\nHost: m\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n", "411", "send the notice with a Content-Length"),
        ("POST /notify HTTP/1.1\r\nHost: m\r\nContent-Length: 8388609\r\n\r\n", "413", "a notice is at most 8 MB"),
        // Nothing passes for the login tailscale serve sets: a second one, or a name with space in it.
        ("POST /notify HTTP/1.1\r\nTailscale-User-Login: a@x\r\nTailscale-User-Login: b@x\r\nContent-Length: 16\r\n\r\n{\"title\":\"Done\"}",
         "400", "the request doesn't read as HTTP"),
        ("POST /notify HTTP/1.1\r\nTailscale-User-Login : a@x\r\nContent-Length: 16\r\n\r\n{\"title\":\"Done\"}",
         "400", "the request doesn't read as HTTP"),
    ])
    func refused(request: String, status: String, why: String) async throws {
        let handed = Handed()
        let listener = try listener(handed)
        defer { listener.close() }

        let raw = try await exchange(request, port: listener.port)

        #expect(raw.hasPrefix("HTTP/1.1 \(status) "), "\(raw)")
        #expect(NoticeVerdict(answer: Data(raw.components(separatedBy: "\r\n\r\n").last!.utf8)) == .refused(why))
        #expect(handed.all.isEmpty)
    }

    /// This Mac's IPv4 addresses other than loopback.
    static func otherIPv4Addresses() -> [String] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var found: [String] = []
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var inet = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            guard inet.s_addr != INADDR_LOOPBACK.bigEndian else { continue }
            var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &inet, &text, socklen_t(text.count)) != nil else { continue }
            found.append(String(cString: text))
        }
        return found
    }

    /// Whether a TCP connection to `host`:`port` is accepted.
    static func connects(to host: String, port: Int) -> Bool {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        inet_pton(AF_INET, host, &address.sin_addr)
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        } == 0
    }
}
