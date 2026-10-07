import Foundation
import ShipyardCommand
import TOMLDecoder

/// The `shipyard` command's own settings, read from `cli.toml` on every
/// machine. `config.toml` is the app's and `cli.toml` the command's: no
/// setting appears in both (ADR 0008). Every key is optional, so a missing
/// or empty file is the defaults. `version` is optional too: a file without
/// it is version 1, with no warning, since a warning would print on every
/// command that reads the file.
public struct CLISettings: Equatable, Sendable {
    /// The `cli.toml` format version this build reads.
    public static let supportedVersion = 1

    /// The published schema a file's `#:schema` line points at, for `taplo
    /// check`: `schema/cli.schema.json` on `main`, and that file's `$id`.
    public static let schemaURL = "https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/cli.schema.json"

    /// `[notices]`: where `shipyard notify` sends a notice.
    public var notices: NoticeSettings

    public init(notices: NoticeSettings = NoticeSettings()) {
        self.notices = notices
    }

    /// What a missing or empty `cli.toml` means.
    public static let defaults = CLISettings()
}

/// `cli.toml`'s `[notices]` table: where this machine's `shipyard notify`
/// sends a notice. With `app-machine` set, straight to the app on that Mac
/// over the user's tailnet, at `<app-scheme>://<app-machine>:<app-port>` (ADR
/// 0010). A new setting is a property, a key in
/// `CLISettings.Reader.noticesKeys` and a line in `CLISettings.Reader.notices(_:)`.
public struct NoticeSettings: Equatable, Sendable {
    /// `app-machine`: the Mac running the app, by its MagicDNS name (`my-mac`
    /// or `my-mac.tail1234.ts.net`); none by default.
    public var appMachine: String?
    /// `app-scheme`: how the request travels, as `tailscale serve` exposes
    /// the app's port on the Mac (`--http` or `--https`). `http` by default.
    public var appScheme: Scheme
    /// `app-port`: the port `tailscale serve` exposes on the Mac. The app's
    /// default listening port by default (`NoticePort.default`). Not
    /// `port`, which is `config.toml`'s: no setting appears in both files.
    public var appPort: Int

    public enum Scheme: String, Equatable, Sendable, CaseIterable {
        case http, https
    }

    public init(appMachine: String? = nil, appScheme: Scheme = .http, appPort: Int = NoticePort.default) {
        self.appMachine = appMachine
        self.appScheme = appScheme
        self.appPort = appPort
    }
}

/// One thing wrong with `cli.toml`: "line 3: unknown setting `notices.app-machin`".
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

        static let rootKeys = ["version", "notices"]
        static let noticesKeys = ["app-machine", "app-scheme", "app-port"]

        func settings(from root: TOMLTable) -> CLISettings {
            rejectUnknownKeys(in: root, path: [], known: Self.rootKeys)
            if root.contains(key: "version") {
                if let version = try? root.integer(forKey: "version") {
                    if version != CLISettings.supportedVersion {
                        issue("`version` \(version) isn't supported; this shipyard reads version \(CLISettings.supportedVersion)")
                    }
                } else {
                    issue("`version` must be a whole number")
                }
            }
            var settings = CLISettings()
            if let table = table(root, "notices", path: []) {
                settings.notices = notices(table)
            }
            return settings
        }

        func notices(_ table: TOMLTable) -> NoticeSettings {
            rejectUnknownKeys(in: table, path: ["notices"], known: Self.noticesKeys)
            var settings = NoticeSettings()
            if let raw = string(table, "app-machine", path: ["notices"]) {
                let machine = raw.trimmingCharacters(in: .whitespaces)
                if machine.isEmpty {
                    issue("`notices.app-machine` names your Mac by its MagicDNS name, such as `my-mac`; leave it out to send notices no faster way")
                } else if machine.contains("://") {
                    issue("`notices.app-machine` is your Mac's MagicDNS name alone, such as `my-mac`, not `\(machine)`: `app-scheme` and `app-port` are settings of their own")
                } else if !Self.isHostName(machine) {
                    issue("`notices.app-machine` is your Mac's MagicDNS name alone, such as `my-mac`, not `\(machine)`")
                } else {
                    settings.appMachine = machine
                }
            }
            if let raw = string(table, "app-scheme", path: ["notices"]) {
                if let scheme = NoticeSettings.Scheme(rawValue: raw) {
                    settings.appScheme = scheme
                } else {
                    issue("`notices.app-scheme` is `http` or `https`, not `\(raw)`")
                }
            }
            if table.contains(key: "app-port") {
                if let port = try? table.integer(forKey: "app-port") {
                    if NoticePort.range.contains(Int(port)) {
                        settings.appPort = Int(port)
                    } else {
                        issue("`notices.app-port` must be between \(NoticePort.range.lowerBound) and \(NoticePort.range.upperBound) (got \(port))")
                    }
                } else {
                    issue("`notices.app-port` must be a whole number")
                }
            }
            return settings
        }

        /// A name a URL can hold as its host, nothing more: letters,
        /// digits, `-` and `.` (a MagicDNS name, short or full, or an IPv4
        /// address).
        static func isHostName(_ text: String) -> Bool {
            let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")
            return !text.hasPrefix("-") && !text.hasPrefix(".") && text.unicodeScalars.allSatisfy(allowed.contains)
        }

        private func string(_ table: TOMLTable, _ key: String, path: [String]) -> String? {
            guard table.contains(key: key) else { return nil }
            guard let value = try? table.string(forKey: key) else {
                issue("`\((path + [key]).joined(separator: "."))` must be a string")
                return nil
            }
            return value
        }

        private func issue(_ message: String) {
            issues.append(CLISettingsIssue(line: nil, message: message))
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
