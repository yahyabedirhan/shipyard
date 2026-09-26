import Foundation

/// The app's verdict on `config.toml` after a reload: whether it accepted
/// the file and, when it didn't, the problems the panel's banner lists. The
/// record exists for agents, who edit the file but can't see the banner.
public struct ConfigStatus: Equatable, Sendable {
    /// When the app read the file.
    public var checked: Date
    /// The configuration file it read.
    public var config: URL
    /// The file's modification time when it was read; `nil` when there was
    /// no file (the defaults, accepted).
    public var configModified: Date?
    /// Why the file was rejected; `nil` when it was accepted.
    public var error: ConfigError?
    /// Unknown settings an accepted file has, which the app ignores, and old forms it still reads.
    public var warnings: [ConfigIssue]

    public init(checked: Date, config: URL, configModified: Date?, error: ConfigError?, warnings: [ConfigIssue]) {
        self.checked = checked
        self.config = config
        self.configModified = configModified
        self.error = error
        self.warnings = warnings
    }

    public var accepted: Bool { error == nil }
}

// `config-status.json`:
//
//     {
//       "version": 1,
//       "checked": "2026-09-25T12:05:01Z",
//       "config": "/Users/me/.config/shipyard/config.toml",
//       "configModified": "2026-09-25T12:05:00Z",
//       "accepted": false,
//       "problems": [{ "line": 1, "message": "…", "banner": "config.toml line 1: …" }],
//       "warnings": []
//     }
//
// Times are UTC in whole seconds, so an agent can compare `configModified`
// with `date -u -r <file> +%Y-%m-%dT%H:%M:%SZ` after its save. `configModified`
// is null when there was no file, a problem's `line` null when it can't be
// placed. `banner` is the problem's line in the panel's banner, word for word.
extension ConfigStatus: Encodable {
    private enum CodingKeys: String, CodingKey {
        case version, checked, config, configModified, accepted, problems, warnings
    }

    private struct Problem: Encodable {
        var line: Int?
        var message: String
        var banner: String

        init(_ issue: ConfigIssue) {
            line = issue.line
            message = issue.message
            banner = PanelText.configIssue(issue)
        }

        enum CodingKeys: String, CodingKey { case line, message, banner }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            // Explicit null rather than a missing key: easier to read for an agent.
            try container.encode(line, forKey: .line)
            try container.encode(message, forKey: .message)
            try container.encode(banner, forKey: .banner)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ConfigStatusStore.currentVersion, forKey: .version)
        try container.encode(Self.wholeSeconds(checked), forKey: .checked)
        try container.encode(config.path, forKey: .config)
        try container.encode(configModified.map(Self.wholeSeconds), forKey: .configModified)
        try container.encode(accepted, forKey: .accepted)
        try container.encode((error?.issues ?? []).map(Problem.init), forKey: .problems)
        try container.encode(warnings.map(Problem.init), forKey: .warnings)
    }

    /// `date` in UTC, truncated to the second as `date -r` prints a file's time.
    private static func wholeSeconds(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)))
    }
}

/// Writes the latest `ConfigStatus` to one JSON file, `config-status.json`,
/// in a directory the app provides (`~/Library/Application Support/Shipyard/`,
/// beside `state.json`; tests pass a temporary one). Not beside `config.toml`:
/// the app watches that directory, so writing there would reload it again.
/// The file is app-owned, rewritten after every reload, and only ever read
/// by agents; the app never reads it back.
@MainActor
public final class ConfigStatusStore {
    /// The version of the file format this build writes. Adding a field is
    /// not a new version; renaming or changing one is.
    public nonisolated static let currentVersion = 1
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
    public func record(_ status: ConfigStatus) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encode(status).write(to: url, options: .atomic)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    nonisolated static func encode(_ status: ConfigStatus) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(status)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
