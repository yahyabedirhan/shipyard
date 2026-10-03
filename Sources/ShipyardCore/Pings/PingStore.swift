import Foundation

/// Keeps the pings agents send, one JSON file per ping (`<id>.json`) in a
/// directory of its own: on the Mac `~/Library/Application Support/Shipyard/Pings/`,
/// apart from `state.json` (app state is what shipyard remembers from use;
/// pings are data agents send); on Linux, a machine without the app,
/// `~/.local/share/shipyard/pings` (`defaultDirectory(platform:)`). The format is private (ADR 0004): only the
/// `shipyard` CLI and the app read and write it.
///
/// The CLI and the running app may write at the same time. Each write
/// replaces one ping's file atomically, so a reader sees a whole ping or
/// none, and writes to two pings never meet. A file that doesn't read is
/// skipped, never fatal.
public struct PingStore: Sendable {
    /// The directory the pings live in.
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/Shipyard/Pings/`, beside `state.json`.
    public static var defaultDirectory: URL {
        ResolvedRepositoriesStore.defaultDirectory.appendingPathComponent("Pings", isDirectory: true)
    }

    /// Where the `shipyard` command keeps pings on `platform`: on macOS
    /// `defaultDirectory`, where the app reads them; on Linux
    /// `$XDG_DATA_HOME/shipyard/pings`, or `~/.local/share/shipyard/pings`
    /// when `XDG_DATA_HOME` is unset, empty or not an absolute path.
    public static func defaultDirectory(
        platform: CommandPlatform,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        switch platform {
        case .macOS:
            return defaultDirectory
        case .linux:
            let base: URL
            if let xdg = environment["XDG_DATA_HOME"], xdg.hasPrefix("/") {
                base = URL(fileURLWithPath: xdg, isDirectory: true)
            } else {
                base = home.appendingPathComponent(".local/share", isDirectory: true)
            }
            return base
                .appendingPathComponent("shipyard", isDirectory: true)
                .appendingPathComponent("pings", isDirectory: true)
        }
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

    /// Every ping that reads, oldest first (then by id); none when the
    /// directory doesn't exist yet.
    public func all() -> [Ping] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(Ping.self, from: Data(contentsOf: $0)) }
            .sorted { ($0.sent, $0.id) < ($1.sent, $1.id) }
    }

    /// The ping `id` names, if it's stored.
    public func ping(id: String) -> Ping? {
        guard let data = try? Data(contentsOf: url(id: id)) else { return nil }
        return try? Self.decoder.decode(Ping.self, from: data)
    }

    /// Writes `ping`, replacing the one with its id, atomically.
    public func save(_ ping: Ping) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(ping).write(to: url(id: ping.id), options: .atomic)
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
        guard let stored = self.ping(id: ping.id) else { return true }
        guard stored == ping else { return false }
        try remove(id: ping.id)
        return true
    }

    /// Removes every ping that has expired by `now` (`Ping.isLive(at:)`),
    /// each only as it was read (`removeIfUnchanged`), so one replaced
    /// meanwhile stays. A file that can't be removed is left; readers
    /// still leave it out by its expiry.
    public func removeExpired(at now: Date) {
        for ping in all() where !ping.isLive(at: now) {
            _ = try? removeIfUnchanged(ping)
        }
    }

    /// Removes ping `id` (a dismiss, or a seen ping whose window has
    /// passed). An id that isn't stored changes nothing.
    public func remove(id: String) throws {
        let file = url(id: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }

    private func url(id: String) -> URL {
        directory.appendingPathComponent("\(id).json", isDirectory: false)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
