import Foundation

/// Keeps records one JSON file each (`<id>.json`) in a folder of their
/// own. The `shipyard` command and the app may write at the same time:
/// each write replaces one record's file atomically, so a reader sees a
/// whole record or none, and writes to two records never meet. A file that
/// doesn't read is skipped, never fatal. Dates are ISO 8601.
///
/// The ping store keeps pings in one; another agent-side store can keep
/// its records the same way.
public struct RecordStore<Record: Codable & Equatable & Sendable>: Sendable {
    /// The folder the records live in.
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Every record that reads, in no particular order; none when the
    /// folder doesn't exist yet.
    public func all() -> [Record] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(Record.self, from: Data(contentsOf: $0)) }
    }

    /// The record `id` names, if it's stored and reads.
    public func record(id: String) -> Record? {
        guard let data = try? Data(contentsOf: url(id: id)) else { return nil }
        return try? Self.decoder.decode(Record.self, from: data)
    }

    /// Writes `record` as `id`, replacing the one there, atomically;
    /// creates the folder when it's missing.
    public func save(_ record: Record, id: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(record).write(to: url(id: id), options: .atomic)
    }

    /// Removes `id` only while the store holds it exactly as `record`,
    /// read again just before: one changed since stays. Returns whether
    /// it's gone.
    @discardableResult
    public func removeIfUnchanged(_ record: Record, id: String) throws -> Bool {
        guard let stored = self.record(id: id) else { return true }
        guard stored == record else { return false }
        try remove(id: id)
        return true
    }

    /// Removes `id`. An id that isn't stored changes nothing.
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
