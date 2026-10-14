import Darwin
import Foundation
import os
import ShipyardControl
import ShipyardCore
import ShipyardNotices

final class NoticeListener: @unchecked Sendable {
    typealias Respond = @Sendable (_ request: NoticeRequest, _ login: String?) async -> NoticeVerdict

    struct Failure: Error, CustomStringConvertible {
        var description: String
    }

    let port: Int

    private let source: DispatchSourceRead
    private let respond: Respond
    private let serving = OSAllocatedUnfairLock(initialState: 0)
    static let mostConnections = 8
    private static let queue = DispatchQueue(label: "shipyard.notices", attributes: .concurrent)
    private static let connectionTimeout: TimeInterval = 5
    static let requestDeadline: TimeInterval = 30
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

    static func start(port: Int, respond: @escaping Respond) throws(Failure) -> NoticeListener {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw Failure(description: "couldn't open a socket: \(UnixSocket.reason())") }
        var reuse: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
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

    private static func boundPort(_ descriptor: Int32) -> Int? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        return read == 0 ? Int(UInt16(bigEndian: address.sin_port)) : nil
    }

    func close() {
        source.cancel()
    }

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

    private static func turnAway(_ connection: Int32) {
        let busy = NoticeVerdict.refused("shipyard is answering \(mostConnections) other requests; try again in a moment")
        _ = UnixSocket.writeAll(connection, response(status: 503, verdict: busy))
        Darwin.close(connection)
    }

    enum Request {
        case read(Head, body: Data)
        case refused(Int, String)
    }

    struct Head {
        var method: String
        var target: String
        var headers: [String: String]
    }

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

    static func response(status: Int, verdict: NoticeVerdict) -> Data {
        let body = verdict.encoded()
        let reason = reasons[status] ?? "Error"
        let head = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\n"
            + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    static let reasons = [
        200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed",
        408: "Request Timeout", 411: "Length Required", 413: "Content Too Large", 431: "Request Header Fields Too Large",
        503: "Service Unavailable",
    ]

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

    private static func receive(_ connection: Int32) -> Data? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = buffer.withUnsafeMutableBytes { recv(connection, $0.baseAddress, $0.count, 0) }
            if count > 0 { return Data(buffer[0..<count]) }
            if count < 0, errno == EINTR { continue }
            return nil
        }
    }

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
