import Foundation

/// Keeps the pings agents send, one JSON file per ping (`<id>.json`) in a
/// directory of its own: `~/Library/Application Support/Shipyard/Pings/`,
/// apart from `state.json` (app state is what shipyard remembers from use;
/// pings are data agents send). The format is private (ADR 0004): only the
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
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Shipyard", isDirectory: true)
            .appendingPathComponent("Pings", isDirectory: true)
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

    /// Records that the user saw ping `id` at `now`. A ping already seen
    /// keeps its first time; an unknown one changes nothing.
    public func markSeen(id: String, at now: Date) throws {
        guard var ping = ping(id: id), ping.seen == nil else { return }
        ping.seen = now
        try save(ping)
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
