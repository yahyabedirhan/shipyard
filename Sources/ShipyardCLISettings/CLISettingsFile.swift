import Foundation
import ShipyardCommand

/// Where this machine's `cli.toml` is, and reading it. The executable
/// picks the place once, when it assembles its commands: beside
/// `config.toml` on the Mac (`beside(config:)`), in the XDG config folder
/// on a machine without the app (`withoutTheApp(environment:home:)`). A
/// command that needs a setting reads the file when it runs, so a broken
/// file stops only the commands that use it.
public struct CLISettingsFile: Equatable, Sendable {
    public static let fileName = "cli.toml"

    public var url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `cli.toml` in the folder that holds `config` (the `config.toml` the
    /// app reads, as `ConfigurationLocation.current` finds it): the Mac's.
    public static func beside(config: URL) -> CLISettingsFile {
        CLISettingsFile(url: config.deletingLastPathComponent().appendingPathComponent(fileName, isDirectory: false))
    }

    /// `$XDG_CONFIG_HOME/shipyard/cli.toml`, or `~/.config/shipyard/cli.toml`
    /// when `XDG_CONFIG_HOME` is unset, empty or not an absolute path: a
    /// machine without the app's.
    public static func withoutTheApp(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> CLISettingsFile {
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = home.appendingPathComponent(".config", isDirectory: true)
        }
        return CLISettingsFile(url: base
            .appendingPathComponent("shipyard", isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false))
    }

    /// The settings in the file, the defaults when there's no file. A file
    /// that doesn't read is the command's failure (exit 1), naming the file
    /// and what's wrong with it, so a typo never quietly changes what a
    /// command does.
    public func read() throws(CommandResult) -> CLISettings {
        switch load() {
        case .success(let settings): return settings
        case .failure(.unreadable(let reason)): throw .failed("shipyard: can't read \(url.path): \(reason)")
        case .failure(.invalid(let issues)): throw failure(issues)
        }
    }

    /// The file's verdict at `checked`, for `shipyard config check`: what
    /// `read()` would refuse, as problems. A missing file is the defaults,
    /// accepted.
    public func check(at checked: Date) -> ConfigurationCheck {
        let modified = ConfigurationCheck.modificationDate(of: url)
        let problems: [ConfigurationCheck.Issue]
        switch load() {
        case .success:
            problems = []
        case .failure(.unreadable(let reason)):
            problems = [ConfigurationCheck.Issue(line: nil, message: "can't read \(url.path): \(reason)")]
        case .failure(.invalid(let issues)):
            problems = issues.map { ConfigurationCheck.Issue(line: $0.line, message: $0.message) }
        }
        return ConfigurationCheck(name: Self.fileName, checked: checked, file: url, modified: modified, problems: problems, warnings: [])
    }

    private enum LoadFailure: Error {
        /// The file is there but its bytes don't come.
        case unreadable(String)
        /// The bytes come but don't read as settings.
        case invalid([CLISettingsIssue])
    }

    private func load() -> Result<CLISettings, LoadFailure> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) { return .success(.defaults) }
            return .failure(.unreadable(error.localizedDescription))
        }
        guard let text = String(data: data, encoding: .utf8) else {
            return .failure(.invalid([CLISettingsIssue(line: nil, message: "the file isn't UTF-8 text")]))
        }
        do {
            return .success(try CLISettings.decode(text))
        } catch {
            return .failure(.invalid(error.issues))
        }
    }

    private func failure(_ issues: [CLISettingsIssue]) -> CommandResult {
        .failed("shipyard: \(url.path) doesn't read (\(issues.map(\.description).joined(separator: "; "))); fix it, then try again")
    }
}
