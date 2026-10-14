import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ShipyardCore

final class StubHTTP: HTTPTransport {
    struct Answer: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body = Data()
        var failure: URLError?

        static func json(_ body: String, status: Int = 200, headers: [String: String] = [:]) -> Answer {
            var headers = headers
            headers["Content-Type"] = headers["Content-Type"] ?? "application/json; charset=utf-8"
            return Answer(status: status, headers: headers, body: Data(body.utf8))
        }

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

        static func status(_ status: Int, headers: [String: String] = [:]) -> Answer {
            Answer(status: status, headers: headers)
        }

        static func failure(_ code: URLError.Code = .notConnectedToInternet) -> Answer {
            Answer(failure: URLError(code))
        }
    }

    private struct Route {
        var method: String
        var url: URL
        var body: String?
        var answers: [Answer]

        func matches(_ request: URLRequest) -> Bool {
            request.httpMethod ?? "GET" == method
                && StubHTTP.matches(route: url, request: request.url)
                && body.map { request.bodyText.contains($0) } ?? true
        }
    }

    private let routes = Locked<[Route]>([])
    private let log = Locked<[URLRequest]>([])
    private let missed = Locked<[URLRequest]>([])
    private let hook = Locked<(@Sendable (URLRequest) async -> Void)?>(nil)

    var requests: [URLRequest] { log.current }
    var unmatched: [URLRequest] { missed.current }

    func requests(_ method: String, _ url: URL) -> [URLRequest] {
        requests.filter { $0.httpMethod ?? "GET" == method && Self.matches(route: url, request: $0.url) }
    }

    func on(_ url: URL, _ answers: Answer...) {
        register("GET", url, answers)
    }

    func on(_ method: String, _ url: URL, _ answers: Answer...) {
        register(method, url, answers)
    }

    func on(_ method: String, _ url: URL, answers: [Answer]) {
        register(method, url, answers)
    }

    func on(_ method: String, _ url: URL, body marker: String, answers: [Answer]) {
        register(method, url, answers, body: marker)
    }

    func requests(_ method: String, _ url: URL, body marker: String) -> [URLRequest] {
        requests(method, url).filter { $0.bodyText.contains(marker) }
    }

    func onSend(_ body: @escaping @Sendable (URLRequest) async -> Void) {
        hook.withValue { $0 = body }
    }

    private func register(_ method: String, _ url: URL, _ answers: [Answer], body: String? = nil) {
        precondition(!answers.isEmpty, "a route needs at least one answer")
        routes.withValue { routes in
            routes.removeAll { $0.method == method && $0.url == url && $0.body == body }
            routes.append(Route(method: method, url: url, body: body, answers: answers))
        }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try Task.checkCancellation()
        log.withValue { $0.append(request) }
        if let body = hook.current { await body(request) }
        let answer: Answer? = routes.withValue { routes in
            func specificity(_ route: Route) -> Int { (route.body != nil ? 2 : 0) + (route.url.query != nil ? 1 : 0) }
            let order = routes.indices.sorted { specificity(routes[$0]) > specificity(routes[$1]) }
            guard let index = order.first(where: { routes[$0].matches(request) }) else { return nil }
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

    fileprivate static func matches(route: URL, request: URL?) -> Bool {
        guard let request else { return false }
        if route.query != nil { return route.absoluteString == request.absoluteString }
        var components = URLComponents(url: request, resolvingAgainstBaseURL: false)
        components?.query = nil
        components?.fragment = nil
        return components?.url?.absoluteString == route.absoluteString
    }
}

extension URLRequest {
    var bodyText: String { httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }

    var formFields: [String: String] {
        var fields: [String: String] = [:]
        for pair in bodyText.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { String($0).removingPercentEncoding ?? String($0) }
            fields[parts[0]] = parts.count > 1 ? parts[1] : ""
        }
        return fields
    }
}
