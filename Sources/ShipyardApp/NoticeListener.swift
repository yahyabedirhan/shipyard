import Darwin
import Foundation
import os
import ShipyardControl
import ShipyardCore
import ShipyardNotices

/// The app's listener for notices from the user's other machines (ADR
/// 0010): an HTTP server on 127.0.0.1 only, at the port `config.toml`'s
/// `[notices]` names, which `tailscale serve` exposes to the tailnet. It's
/// started only with `[notices] listen = true`.
///
/// Each connection is one request, `POST /notify` with a notice request's
/// JSON (`TailnetWire`: a notice to show, or a withdrawal), answered with the verdict `respond` gives for it and
/// its `Tailscale-User-Login`, then closed. It checks only what HTTP
/// needs, and that a login is there at all: a request without one, or with
/// an empty or doubled one, is refused on its head, before its body is read.
/// Whether the login may post is `Shipyard.receive(_:from:)`'s to say. At
/// most `mostConnections` are served at once; one more is answered 503.
/// A request a web page could send (one with `Origin` or `Sec-Fetch-Site`)
/// is refused, so a site the user visits can't reach it through the
/// browser, even by pointing its own name at 127.0.0.1.
final class NoticeListener: @unchecked Sendable {
    typealias Respond = @Sendable (_ request: NoticeRequest, _ login: String?) async -> NoticeVerdict

    /// Why the listener couldn't start.
    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    /// The port it's bound to: the one asked for, or the system's pick for 0.
    let port: Int

    private let source: DispatchSourceRead
    private let respond: Respond
    /// The connections being served now, at most `mostConnections`.
    private let serving = OSAllocatedUnfairLock(initialState: 0)
    /// The most connections served at once, so a flood of them can't hold
    /// every thread; a request past them is refused with 503 at once.
    static let mostConnections = 8
    private static let queue = DispatchQueue(label: "shipyard.notices", attributes: .concurrent)
    /// How long a connection may wait for each read or write, and how long
    /// it may take to send its whole request, so one that stalls or trickles
    /// never holds a thread.
    private static let connectionTimeout: TimeInterval = 5
    static let requestDeadline: TimeInterval = 30
    /// The most a request's head and its body may hold: the body, a notice
    /// with the largest image (`TailnetWire.largestBody`).
    static let headLimit = 16 * 1024
    static let bodyLimit = TailnetWire.largestBody

    private init(port: Int, descriptor: Int32, respond: @escaping Respond) {
        self.port = port
        self.respond = respond
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: Self.queue)
        source.setEventHandler { [weak self] in self?.acceptAll(descriptor) }
        source.setCancelHandler { Darwin.close(descriptor) }
        source.resume()
    }

    /// Listens on 127.0.0.1 at `port` (0: any free port, for tests).
    static func start(port: Int, respond: @escaping Respond) throws(Failure) -> NoticeListener {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure(description: "couldn't open a socket: \(UnixSocket.reason())") }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        // The loopback address alone: never the Mac's other interfaces.
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(descriptor, 16) == 0, fcntl(descriptor, F_SETFL, O_NONBLOCK) == 0 else {
            let why = UnixSocket.reason()
            Darwin.close(descriptor)
            throw Failure(description: "couldn't listen on 127.0.0.1:\(port): \(why)")
        }
        guard let actual = boundPort(descriptor) else {
            Darwin.close(descriptor)
            throw Failure(description: "couldn't read the port it listens on")
        }
        return NoticeListener(port: actual, descriptor: descriptor, respond: respond)
    }

    /// The port `descriptor` is bound to, as the system says.
    private static func boundPort(_ descriptor: Int32) -> Int? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        return read == 0 ? Int(UInt16(bigEndian: address.sin_port)) : nil
    }

    /// Stops listening. A request being answered still gets its answer.
    func close() {
        source.cancel()
    }

    /// Accepts every waiting connection; the listening socket doesn't block.
    private func acceptAll(_ descriptor: Int32) {
        while true {
            let connection = accept(descriptor, nil, nil)
            guard connection >= 0 else { return }
            _ = fcntl(connection, F_SETFL, fcntl(connection, F_GETFL) & ~O_NONBLOCK)
            UnixSocket.configure(connection, timeout: Self.connectionTimeout)
            let admitted = serving.withLock { count in
                guard count < Self.mostConnections else { return false }
                count += 1
                return true
            }
            guard admitted else {
                Self.queue.async { Self.turnAway(connection) }
                continue
            }
            Self.queue.async { self.serve(connection) }
        }
    }

    /// Answers one connection: reads its request, answers, closes.
    private func serve(_ connection: Int32) {
        let request = Self.read(connection)
        let respond = respond
        let serving = serving
        Task {
            let (status, verdict) = await Self.answer(request, respond: respond)
            _ = UnixSocket.writeAll(connection, Self.response(status: status, verdict: verdict))
            Darwin.close(connection)
            serving.withLock { $0 -= 1 }
        }
    }

    /// Answers a connection past `mostConnections` with 503, unread, and closes it.
    private static func turnAway(_ connection: Int32) {
        let busy = NoticeVerdict.refused("shipyard is answering \(mostConnections) other requests; try again in a moment")
        _ = UnixSocket.writeAll(connection, response(status: 503, verdict: busy))
        Darwin.close(connection)
    }

    // MARK: - HTTP

    /// A request as far as it was read: its head and body, or the status
    /// and reason it was refused with before it was read through.
    enum Request {
        case read(Head, body: Data)
        case refused(Int, String)
    }

    /// A request's line and headers.
    struct Head {
        var method: String
        var target: String
        /// Header names lowercased; a repeated header keeps its first value.
        var headers: [String: String]
    }

    /// The verdict for `request`, and the HTTP status it's sent with.
    static func answer(_ request: Request, respond: Respond) async -> (Int, NoticeVerdict) {
        switch request {
        case .refused(let status, let why):
            return (status, .refused(why))
        case .read(let head, let body):
            guard head.target == TailnetWire.path else {
                return (404, .refused("shipyard takes notices at \(TailnetWire.path) only"))
            }
            guard head.method == "POST" else { return (405, .refused("post the notice to \(TailnetWire.path)")) }
            guard head.headers["origin"] == nil, head.headers["sec-fetch-site"] == nil else {
                return (403, .refused("shipyard takes notices from the shipyard command only, never from a web page"))
            }
            let request: NoticeRequest
            do {
                request = try JSONDecoder().decode(NoticeRequest.self, from: body)
            } catch {
                return (400, .refused("the request didn't read as a notice's JSON, so nothing was done"))
            }
            return (200, await respond(request, head.headers[TailnetWire.loginHeader.lowercased()]))
        }
    }

    /// The bytes of an answer: `status` and the verdict as JSON.
    static func response(status: Int, verdict: NoticeVerdict) -> Data {
        let body = verdict.encoded()
        let reason = reasons[status] ?? "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    /// The reason phrases of the statuses it answers with, in ASCII
    /// whatever the Mac's language.
    static let reasons = [
        200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
        408: "Request Timeout", 411: "Length Required", 413: "Content Too Large", 431: "Request Header Fields Too Large",
        503: "Service Unavailable",
    ]

    /// Reads one request off `connection`: the head up to its blank line,
    /// then the body `Content-Length` says, after a `100 Continue` when the
    /// client waits for one. A head without a login (`parseHead` refuses a
    /// doubled one) is refused before the body is read.
    static func read(_ connection: Int32) -> Request {
        let deadline = Date().addingTimeInterval(requestDeadline)
        let late = Request.refused(408, "the request took longer than \(Int(requestDeadline)) seconds to arrive")
        var data = Data()
        let separator = Data("\r\n\r\n".utf8)
        var headEnd: Range<Data.Index>?
        while headEnd == nil {
            guard data.count <= headLimit else { return .refused(431, "the request's headers are too long") }
            guard let more = receive(connection) else { return .refused(400, "the request ended before its headers did") }
            guard Date() < deadline else { return late }
            data.append(more)
            headEnd = data.range(of: separator)
        }
        guard let headEnd, let head = parseHead(data[..<headEnd.lowerBound]) else {
            return .refused(400, "the request doesn't read as HTTP")
        }
        guard let login = head.headers[TailnetWire.loginHeader.lowercased()], !login.isEmpty else {
            return .refused(403, NoticeRules.noLogin)
        }
        guard head.headers["transfer-encoding"] == nil else {
            return .refused(411, "send the notice with a Content-Length")
        }
        let length = head.headers["content-length"].flatMap { Int($0) } ?? 0
        guard length >= 0, length <= bodyLimit else { return .refused(413, "a notice is at most \(bodyLimit >> 20) MB") }
        var body = Data(data[headEnd.upperBound...])
        if body.count < length, head.headers["expect"]?.lowercased() == "100-continue" {
            _ = UnixSocket.writeAll(connection, Data("HTTP/1.1 100 Continue\r\n\r\n".utf8))
        }
        while body.count < length {
            guard let more = receive(connection) else { return .refused(400, "the request ended before its body did") }
            guard Date() < deadline else { return late }
            body.append(more)
        }
        return .read(head, body: body.prefix(length))
    }

    /// The next bytes the peer sent; `nil` when it closed, failed or timed out.
    private static func receive(_ connection: Int32) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { recv(connection, $0.baseAddress, $0.count, 0) }
            if count > 0 { return Data(buffer[0..<count]) }
            if count < 0, errno == EINTR { continue }
            return nil
        }
    }

    /// The request line and headers in `data`, read strictly: a header name
    /// with space in it, a folded line, or the login header twice doesn't
    /// read, so nothing can pass for the login `tailscale serve` set.
    static func parseHead(_ data: Data) -> Head? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(where: \.isWhitespace) else { return nil }
            if headers[name] != nil {
                guard name != TailnetWire.loginHeader.lowercased() else { return nil }
                continue
            }
            headers[name] = value
        }
        return Head(method: String(requestLine[0]), target: String(requestLine[1]), headers: headers)
    }
}
