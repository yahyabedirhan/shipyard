import Foundation
import TOMLDecoder

/// The `shipyard` command's own settings, read from `cli.toml` on every
/// machine. `config.toml` is the app's and `cli.toml` the command's: no
/// setting appears in both (ADR 0008). Every key is optional, so a missing
/// or empty file is the defaults.
public struct CLISettings: Equatable, Sendable {
    /// `[notify]`: where `shipyard notify` sends a notice.
    public var notify: NotifySettings

    public init(notify: NotifySettings = NotifySettings()) {
        self.notify = notify
    }

    /// What a missing or empty `cli.toml` means.
    public static let defaults = CLISettings()
}

/// `cli.toml`'s `[notify]` table. It holds no setting yet: the notice
/// commands add theirs here (`app-machine`, the Mac another machine sends
/// notices to), each one a property, a key in `CLISettings.Reader.notifyKeys`
/// and a line in `CLISettings.Reader.notify(_:)`.
public struct NotifySettings: Equatable, Sendable {
    public init() {}
}

/// One thing wrong with `cli.toml`: "line 3: unknown setting `notify.app-machin`".
public struct CLISettingsIssue: Hashable, Sendable, CustomStringConvertible {
    /// 1-based line in `cli.toml`, when the problem can be placed.
    public var line: Int?
    public var message: String

    public init(line: Int?, message: String) {
        self.line = line
        self.message = message
    }

    public var description: String {
        line.map { "line \($0): \(message)" } ?? message
    }
}

/// Why `cli.toml` doesn't read. Unlike `config.toml`, an unknown key is an
/// error, not a warning: a mistyped setting would otherwise quietly fall
/// back to its default, such as a notice sent the slow way.
public struct CLISettingsError: Error, Equatable, Sendable {
    public var issues: [CLISettingsIssue]

    public init(_ issues: [CLISettingsIssue]) {
        self.issues = issues
    }
}

extension CLISettings {
    /// Reads the text of `cli.toml`. Rejects invalid TOML, a value of the
    /// wrong type and any key or table it doesn't know.
    public static func decode(_ text: String) throws(CLISettingsError) -> CLISettings {
        let root: TOMLTable
        do {
            root = try TOMLTable(source: text)
        } catch {
            throw CLISettingsError([CLISettingsIssue(invalidTOML: error)])
        }
        let reader = Reader()
        let settings = reader.settings(from: root)
        if !reader.issues.isEmpty { throw CLISettingsError(reader.issues) }
        return settings
    }

    /// Walks the parsed file table by table, collecting every issue.
    final class Reader {
        private(set) var issues: [CLISettingsIssue] = []

        static let rootKeys = ["notify"]
        static let notifyKeys: [String] = []

        func settings(from root: TOMLTable) -> CLISettings {
            rejectUnknownKeys(in: root, path: [], known: Self.rootKeys)
            var settings = CLISettings()
            if let table = table(root, "notify", path: []) {
                settings.notify = notify(table)
            }
            return settings
        }

        func notify(_ table: TOMLTable) -> NotifySettings {
            rejectUnknownKeys(in: table, path: ["notify"], known: Self.notifyKeys)
            return NotifySettings()
        }

        private func table(_ parent: TOMLTable, _ key: String, path: [String]) -> TOMLTable? {
            guard parent.contains(key: key) else { return nil }
            do {
                return try parent.table(forKey: key)
            } catch {
                let (line, _) = CLISettingsIssue.splitLine(from: String(describing: error))
                issues.append(CLISettingsIssue(line: line, message: "`\((path + [key]).joined(separator: "."))` must be a table"))
                return nil
            }
        }

        private func rejectUnknownKeys(in table: TOMLTable, path: [String], known: [String]) {
            for key in table.keys.sorted() where !known.contains(key) {
                let dotted = (path + [key]).joined(separator: ".")
                let hint = known.isEmpty ? "" : "; known: " + known.map { "`\($0)`" }.joined(separator: ", ")
                issues.append(CLISettingsIssue(line: nil, message: "unknown setting `\(dotted)`\(hint)"))
            }
        }
    }
}

extension CLISettingsIssue {
    /// TOMLDecoder's parse errors carry the line only in their description,
    /// as "(Line 3) Syntax error: …".
    init(invalidTOML error: any Error) {
        let (line, detail) = Self.splitLine(from: String(describing: error))
        self.init(line: line, message: "invalid TOML: \(detail)")
    }

    static func splitLine(from description: String) -> (Int?, String) {
        guard description.hasPrefix("(Line "),
              let close = description.firstIndex(of: ")"),
              let line = Int(description[description.index(description.startIndex, offsetBy: 6)..<close])
        else { return (nil, description) }
        let rest = description[description.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return (line, rest)
    }
}
