import Foundation
import ShipyardCommand
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What came of posting a notice to the app machine.
public enum NoticeHTTPOutcome: Equatable, Sendable {
    case answered(status: Int, body: Data)
    case timedOut
    case unreachable(String)
}

/// Posts a notice's JSON to the app machine and waits for the answer. The
/// seam between the tailnet route and the network, so tests use a fake.
public protocol NoticeHTTP: Sendable {
    func post(_ body: Data, to url: URL, timeout: TimeInterval) -> NoticeHTTPOutcome
}

/// The real `NoticeHTTP`, one `URLSession` request: no cookies, no cache,
/// and waiting no longer than the timeout, however the request stalls.
public struct URLSessionNoticeHTTP: NoticeHTTP {
    public init() {}

    public func post(_ body: Data, to url: URL, timeout: TimeInterval) -> NoticeHTTPOutcome {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("shipyard/\(ShipyardVersion.current)", forHTTPHeaderField: "User-Agent")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration)
        let result = Answer()
        let task = session.dataTask(with: request) { data, response, error in
            if let error {
                let timedOut = (error as? URLError)?.code == .timedOut
                result.finish(timedOut ? .timedOut : .unreachable(error.localizedDescription))
            } else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                result.finish(.answered(status: status, body: data ?? Data()))
            }
        }
        task.resume()
        guard result.done.wait(timeout: .now() + timeout + 0.5) == .success, let outcome = result.outcome else {
            session.invalidateAndCancel()
            return .timedOut
        }
        session.finishTasksAndInvalidate()
        return outcome
    }

    private final class Answer: @unchecked Sendable {
        let done = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: NoticeHTTPOutcome?

        var outcome: NoticeHTTPOutcome? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func finish(_ outcome: NoticeHTTPOutcome) {
            lock.lock()
            value = outcome
            lock.unlock()
            done.signal()
        }
    }
}
