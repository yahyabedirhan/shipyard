import Foundation

struct RefreshGate: Equatable, Sendable {
    private(set) var isRunning = false
    private var queued = false

    mutating func begin() -> Bool {
        guard !isRunning else {
            queued = true
            return false
        }
        isRunning = true
        return true
    }

    mutating func finish() -> Bool {
        isRunning = false
        guard queued else { return false }
        queued = false
        return true
    }
}

/// The refresh timer. Shipyard arms it after every refresh with the delay
/// to the next one, and disarms it when refreshes stop (signed out, no
/// projects). Tests fire it by hand.
public protocol RefreshTimer: Sendable {
    func arm(after seconds: TimeInterval, _ fire: @escaping @Sendable () async -> Void)
    func disarm()
}

/// The real timer: a task that sleeps. `fire` runs in a task of its own, so
/// re-arming from inside it (as every refresh does) doesn't cancel the
/// refresh that's running.
public final class TaskRefreshTimer: RefreshTimer, @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    public init() {}

    public func arm(after seconds: TimeInterval, _ fire: @escaping @Sendable () async -> Void) {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        let next = Task {
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            Task { await fire() }
        }
        replace(with: next)
    }

    public func disarm() {
        replace(with: nil)
    }

    private func replace(with next: Task<Void, Never>?) {
        lock.lock()
        let previous = task
        task = next
        lock.unlock()
        previous?.cancel()
    }
}
