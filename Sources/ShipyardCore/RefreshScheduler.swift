import Foundation

/// One refresh at a time, without losing a request that arrives meanwhile.
///
/// A refresh in flight started with the configuration of its time; a request
/// dropped while it runs (a configuration change, ⌘R) would wait for the
/// next timer tick. So a request that can't start is queued, and the running
/// refresh runs once more when it finishes. Several requests meanwhile still
/// make only one more run. (ghbar's `RefreshGate`.)
struct RefreshGate: Equatable, Sendable {
    /// Whether a refresh is running; the panel shows "Refreshing…" from it.
    private(set) var isRunning = false
    private var queued = false

    /// True when a refresh may start now; otherwise the request is queued.
    mutating func begin() -> Bool {
        guard !isRunning else {
            queued = true
            return false
        }
        isRunning = true
        return true
    }

    /// The running refresh finished. True when a request arrived meanwhile:
    /// the caller then begins again.
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
    /// Calls `fire` once after `seconds`, replacing any earlier arming.
    func arm(after seconds: TimeInterval, _ fire: @escaping @Sendable () async -> Void)
    /// Cancels the armed call, if any.
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
