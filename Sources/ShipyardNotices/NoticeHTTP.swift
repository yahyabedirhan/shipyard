import Foundation
import ShipyardCommand
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// What came of posting a notice to the app machine.
public enum NoticeHTTPOutcome: Equatable, Sendable {
    /// Something answered, with this status and body: the app's verdict,
    /// or a proxy's page when the app isn't behind it.
    case answered(status: Int, body: Data)
    /// Nothing answered within the timeout.
    case timedOut
    /// The request couldn't be made: the name didn't resolve, nothing
    /// listens, the network is down. Why, in the system's words.
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
        // A little past the request's own timeout, so its error usually
        // says why; past that, it's given up here.
        guard result.done.wait(timeout: .now() + timeout + 0.5) == .success, let outcome = result.outcome else {
            session.invalidateAndCancel()
            return .timedOut
        }
        session.finishTasksAndInvalidate()
        return outcome
    }

    /// The request's outcome, handed from URLSession's queue to the waiting caller.
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
