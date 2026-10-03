import Foundation
import ShipyardCommand

/// Keeps the pings agents send, one JSON file per ping (`<id>.json`) in a
/// directory of its own (a `RecordStore`): on the Mac
/// `~/Library/Application Support/Shipyard/Pings/` (`appDirectory`), apart
/// from `state.json` (app state is what shipyard remembers from use; pings
/// are data agents send); on a machine without the app
/// `~/.local/share/shipyard/pings` (`directoryWithoutTheApp`). The format
/// is private (ADR 0004): only the `shipyard` CLI and the app read and
/// write it.
///
/// The CLI and the running app may write at the same time. Each write
/// replaces one ping's file atomically, so a reader sees a whole ping or
/// none, and writes to two pings never meet. A file that doesn't read is
/// skipped, never fatal.
///
/// A ping past its `expires` is gone: reads leave it out and remove its
/// file (only as it was read, so one replaced meanwhile stays). Only a
/// ping filed `Unfiled` has an expiry, so on the Mac nothing expires.
public struct PingStore: Sendable {
    /// The directory the pings live in.
    public var directory: URL { records.directory }
    private let records: RecordStore<Ping>
    /// The time a read checks expiry against.
    private let now: @Sendable () -> Date

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) {
        records = RecordStore(directory: directory)
        self.now = now
    }

    /// The same store, reading as at `now`: what a command run at `now`
    /// sees.
    public func at(_ now: Date) -> PingStore {
        PingStore(directory: directory, now: { now })
    }

    /// `~/Library/Application Support/Shipyard/Pings/`, beside `state.json`.
    public static var appDirectory: URL {
        SupportFolder.app.appendingPathComponent("Pings", isDirectory: true)
    }

    /// Where the `shipyard` command keeps pings on a machine without the
    /// app: `pings` in `SupportFolder.withoutTheApp`.
    public static func directoryWithoutTheApp(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        SupportFolder.withoutTheApp(environment: environment, home: home)
            .appendingPathComponent("pings", isDirectory: true)
    }

    /// The folder the app watches to see a ping sent, replaced or
    /// withdrawn: `directory` itself, whose entries change with every one
    /// and with nothing else (`state.json` is saved in its parent). While
    /// `directory` doesn't exist yet, its nearest existing ancestor, so
    /// creating it is seen; the watch is opened again after each change.
    public var watchedDirectory: URL {
        var candidate = directory.standardizedFileURL
        while !FileManager.default.fileExists(atPath: candidate.path), candidate.path != "/" {
            candidate.deleteLastPathComponent()
        }
        return candidate
    }

    /// Every live ping that reads, oldest first (then by id); none when the
    /// directory doesn't exist yet. Expired ones are removed.
    public func all() -> [Ping] {
        records.all()
            .filter(isLive)
            .sorted { ($0.sent, $0.id) < ($1.sent, $1.id) }
    }

    /// The ping `id` names, if it's stored and live; an expired one is
    /// removed.
    public func ping(id: String) -> Ping? {
        records.record(id: id).flatMap { isLive($0) ? $0 : nil }
    }

    /// Writes `ping`, replacing the one with its id, atomically.
    public func save(_ ping: Ping) throws {
        try records.save(ping, id: ping.id)
    }

    /// Records that the user saw `ping` at `now`, clearing its action's
    /// failure. A ping already seen keeps its first time. It's read again
    /// just before the write, and changes nothing unless the store still
    /// holds the same sending of it (`isSameSending(as:)`): one withdrawn
    /// meanwhile stays gone, and one replaced or sent anew under its id
    /// stays unseen.
    public func markSeen(_ ping: Ping, at now: Date) throws {
        guard var stored = self.ping(id: ping.id), stored.isSameSending(as: ping),
              stored.seen == nil || stored.failure != nil else { return }
        stored.seen = stored.seen ?? now
        stored.failure = nil
        stored.failureDetail = nil
        try save(stored)
    }

    /// Records why `ping`'s action failed, in short for its row and whole
    /// (`detail`) for its hover card; it stays as seen or unseen as it was. Read again just before the write, as
    /// `markSeen(_:at:)` is: a ping withdrawn, replaced or sent anew since
    /// changes nothing.
    public func recordFailure(_ ping: Ping, reason: String, detail: String? = nil) throws {
        guard var stored = self.ping(id: ping.id), stored.isSameSending(as: ping),
              stored.failure != reason || stored.failureDetail != detail else { return }
        stored.failure = reason
        stored.failureDetail = detail
        try save(stored)
    }

    /// Removes `ping` (a seen ping whose window has passed) only while the
    /// store holds it exactly as given, read again just before: a ping
    /// replaced, sent anew or marked seen again since stays. Returns
    /// whether it's gone.
    @discardableResult
    public func removeIfUnchanged(_ ping: Ping) throws -> Bool {
        try records.removeIfUnchanged(ping, id: ping.id)
    }

    /// Removes ping `id` (a dismiss, or a seen ping whose window has
    /// passed). An id that isn't stored changes nothing.
    public func remove(id: String) throws {
        try records.remove(id: id)
    }

    /// Whether `ping` is still live now (`Ping.isLive(at:)`); when it isn't,
    /// its file is removed as it was read. A file that can't be removed
    /// stays, and every read leaves it out by its expiry.
    private func isLive(_ ping: Ping) -> Bool {
        guard !ping.isLive(at: now()) else { return true }
        _ = try? records.removeIfUnchanged(ping, id: ping.id)
        return false
    }
}
