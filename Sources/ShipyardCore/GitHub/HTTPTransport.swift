import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Sends one HTTP request and returns the body with the response. Every
/// request shipyard makes to GitHub goes through this, so tests replace the
/// network with recorded responses at this one layer.
public protocol HTTPTransport: Sendable {
    /// Transport failures (offline, timeout) throw; any HTTP status returns.
    /// A cancelled task throws `CancellationError`.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The real transport, over a `URLSession`.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let running = RunningTask()
        do {
            return try await perform(request, running: running)
        } catch let error as URLError where error.code == .cancelled && Task.isCancelled {
            throw CancellationError()
        }
    }

    private func perform(_ request: URLRequest, running: RunningTask) async throws -> (Data, HTTPURLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let response = response as? HTTPURLResponse {
                        continuation.resume(returning: (data ?? Data(), response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                running.start(task)
            }
        } onCancel: {
            running.cancel()
        }
    }
}

/// Holds the data task so a task cancelled before or after it starts still
/// cancels it.
private final class RunningTask: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    func start(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let cancelled = self.cancelled
        lock.unlock()
        task.resume()
        if cancelled { task.cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
