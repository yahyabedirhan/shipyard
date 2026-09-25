import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ShipyardCore

/// An `HTTPTransport` that answers from recorded responses instead of the
/// network, and records every request it was sent.
///
/// Register answers per method and URL with `on`. A URL without a query
/// matches any query on the same path; one with a query matches only that
/// query. Answers are given in order and the last one repeats. A request
/// nothing matches fails with `URLError(.unsupportedURL)` and is listed in
/// `unmatched`.
final class StubHTTP: HTTPTransport {
    /// One recorded answer: a response, or a transport failure.
    struct Answer: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body = Data()
        var failure: URLError?

        /// A JSON body.
        static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Answer {
            var headers = headers
            headers["Content-Type"] = headers["Content-Type"] ?? "application/json; charset=utf-8"
            return Answer(status: status, headers: headers, body: Data(body.utf8))
        }

        /// A JSON body read from `Tests/ShipyardCoreTests/Fixtures/<name>`.
        static func fixture(_ name: String, status: Int = 200, headers: [String: String] = [:]) throws -> Answer {
            let url = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures")
                .appendingPathComponent(name)
            var answer = Answer.json("", status: status, headers: headers)
            answer.body = try Data(contentsOf: url)
            return answer
        }

        /// A bare status, for example a 401 or a 500.
        static func status(_ status: Int, headers: [String: String] = [:]) -> Answer {
            Answer(status: status, headers: headers)
        }

        /// The request never reaches the server.
        static func failure(_ code: URLError.Code = .notConnectedToInternet) -> Answer {
            Answer(failure: URLError(code))
        }
    }

    private struct Route {
        var method: String
        var url: URL
        var answers: [Answer]
    }

    private let routes = Locked<[Route]>([])
    private let log = Locked<[URLRequest]>([])
    private let missed = Locked<[URLRequest]>([])

    /// Every request sent, in order.
    var requests: [URLRequest] { log.current }
    /// Requests no route matched.
    var unmatched: [URLRequest] { missed.current }

    /// Requests sent to `url` (any query) with `method`.
    func requests(_ method: String, _ url: URL) -> [URLRequest] {
        requests.filter { $0.httpMethod ?? "GET" == method && Self.matches(route: url, request: $0.url) }
    }

    /// Answers `GET url` with `answers` in order, the last repeating.
    func on(_ url: URL, _ answers: Answer...) {
        register("GET", url, answers)
    }

    /// Answers `method url` with `answers` in order, the last repeating.
    /// Replaces an earlier registration for the same method and URL.
    func on(_ method: String, _ url: URL, _ answers: Answer...) {
        register(method, url, answers)
    }

    private func register(_ method: String, _ url: URL, _ answers: [Answer]) {
        precondition(!answers.isEmpty, "a route needs at least one answer")
        routes.withValue { routes in
            routes.removeAll { $0.method == method && $0.url == url }
            routes.append(Route(method: method, url: url, answers: answers))
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        log.withValue { $0.append(request) }
        let method = request.httpMethod ?? "GET"
        let answer: Answer? = routes.withValue { routes in
            // A route with a query is more specific, so it's tried first.
            let order = routes.indices.sorted { (routes[$0].url.query != nil) && (routes[$1].url.query == nil) }
            guard let index = order.first(where: {
                routes[$0].method == method && Self.matches(route: routes[$0].url, request: request.url)
            }) else { return nil }
            let answers = routes[index].answers
            if answers.count > 1 { routes[index].answers.removeFirst() }
            return answers[0]
        }
        guard let answer, let url = request.url else {
            missed.withValue { $0.append(request) }
            throw URLError(.unsupportedURL)
        }
        if let failure = answer.failure { throw failure }
        let response = HTTPURLResponse(url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers)!
        return (answer.body, response)
    }

    private static func matches(route: URL, request: URL?) -> Bool {
        guard let request else { return false }
        if route.query != nil { return route.absoluteString == request.absoluteString }
        var components = URLComponents(url: request, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString == route.absoluteString
    }
}

extension URLRequest {
    /// The body as text, for asserting on what was sent.
    var bodyText: String { httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }

    /// The form fields of an `application/x-www-form-urlencoded` body.
    var formFields: [String: String] {
        var fields: [String: String] = [:]
        for pair in bodyText.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            fields[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return fields
    }
}
