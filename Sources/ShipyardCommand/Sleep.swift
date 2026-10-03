import Foundation

/// Waits the given number of seconds; throws `CancellationError` when
/// cancelled. `HerdrCommand`'s timeout, the device flow and the skill
/// install wait with it, so tests can pass one that returns at once.
public typealias Sleep = @Sendable (TimeInterval) async throws -> Void

/// Real waiting, for the app.
public let systemSleep: Sleep = { seconds in
    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
}
