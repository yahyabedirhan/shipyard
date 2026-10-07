import Foundation
import ShipyardCommand

/// Writes the latest reload's verdict (`ConfigurationStore.check(at:)`) to
/// one JSON file, `config-status.json`, in `ConfigurationCheck`'s format,
/// which `shipyard config check --json` shares. It goes in a directory the
/// app provides (`~/Library/Application Support/Shipyard/`, beside
/// `state.json`; tests pass a temporary one). Not beside `config.toml`:
/// the app watches that directory, so writing there would reload it again.
/// The file is app-owned, rewritten after every reload, and only ever read
/// by agents; the app never reads it back.
@MainActor
public final class ConfigStatusStore {
    public nonisolated static let fileName = "config-status.json"

    /// The directory the app provides.
    public let directory: URL
    /// `config-status.json` in `directory`.
    public var url: URL { directory.appendingPathComponent(Self.fileName, isDirectory: false) }

    /// Why the latest write failed; `nil` once one succeeds.
    public private(set) var saveError: String?

    public init(directory: URL) {
        self.directory = directory
    }

    /// Writes `status`, replacing the file atomically so an agent never
    /// reads half of it.
    public func record(_ status: ConfigurationCheck) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encode(status).write(to: url, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    nonisolated static func encode(_ status: ConfigurationCheck) throws -> Data {
        try ConfigurationCheck.json(status)
    }
}
