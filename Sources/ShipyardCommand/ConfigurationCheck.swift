import Foundation

/// The verdict on one settings file as it read at `checked`: whether it
/// was accepted and, when it wasn't, its problems; the warnings an accepted
/// file has. The app records `config.toml`'s after every reload in
/// `config-status.json`, and `shipyard config check` prints one for each
/// file the build reads, so the two say the same thing in the same fields.
/// The issues are each file's own (`ConfigurationIssue`, `CLISettingsIssue`),
/// carried here as their line and message.
public struct ConfigurationCheck: Equatable, Sendable {
    /// The version of the JSON format (`config-status.json`). Adding a
    /// field is not a new version; renaming or changing one is.
    public static let formatVersion = 1

    /// One problem or warning: 1-based `line` when it can be placed.
    public struct Issue: Hashable, Sendable {
        public var line: Int?
        public var message: String

        public init(line: Int?, message: String) {
            self.line = line
            self.message = message
        }
    }

    /// The file's name in banners and printed lines: `config.toml`, `cli.toml`.
    public var name: String
    /// When the file was read.
    public var checked: Date
    /// The file that was read.
    public var file: URL
    /// The file's modification time when it was read; `nil` when there was
    /// no file (the defaults, accepted).
    public var modified: Date?
    /// Why the file was rejected; empty when it was accepted.
    public var problems: [Issue]
    /// What an accepted file has that's ignored or read in an old form.
    public var warnings: [Issue]

    public init(name: String, checked: Date, file: URL, modified: Date?, problems: [Issue], warnings: [Issue]) {
        self.name = name
        self.checked = checked
        self.file = file
        self.modified = modified
        self.problems = problems
        self.warnings = warnings
    }

    public var accepted: Bool { problems.isEmpty }

    /// One issue's line in the panel's banner and in `config check`:
    /// "config.toml line 14: unknown event `pr.openned` …", or without the
    /// line when it can't be placed.
    public static func banner(_ issue: Issue, in name: String) -> String {
        issue.line.map { "\(name) line \($0): \(issue.message)" } ?? "\(name): \(issue.message)"
    }

    /// The modification time of the file at `url`, `nil` when there's none.
    /// Taken before the file's bytes, so it never claims a newer file than
    /// was read.
    public static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

// `config-status.json`, and each file's entry in `config check --json`:
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
extension ConfigurationCheck: Encodable {
    private enum CodingKeys: String, CodingKey {
        case version, checked, config, configModified, accepted, problems, warnings
    }

    private struct Entry: Encodable {
        var issue: Issue
        var name: String

        enum CodingKeys: String, CodingKey { case line, message, banner }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            // Explicit null rather than a missing key: easier to read for an agent.
            try container.encode(issue.line, forKey: .line)
            try container.encode(issue.message, forKey: .message)
            try container.encode(ConfigurationCheck.banner(issue, in: name), forKey: .banner)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .version)
        try container.encode(Self.wholeSeconds(checked), forKey: .checked)
        try container.encode(file.path, forKey: .config)
        try container.encode(modified.map(Self.wholeSeconds), forKey: .configModified)
        try container.encode(accepted, forKey: .accepted)
        try container.encode(problems.map { Entry(issue: $0, name: name) }, forKey: .problems)
        try container.encode(warnings.map { Entry(issue: $0, name: name) }, forKey: .warnings)
    }

    /// `date` in UTC, truncated to the second as `date -r` prints a file's time.
    private static func wholeSeconds(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)))
    }

    /// The JSON an agent reads, as `config-status.json` holds it.
    public static func json<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(UInt8(ascii: "\n"))
        return data
    }
}
