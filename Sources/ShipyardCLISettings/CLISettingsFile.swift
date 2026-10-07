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
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if !FileManager.default.fileExists(atPath: url.path) { return .defaults }
            throw .failed("shipyard: can't read \(url.path): \(error.localizedDescription)")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw failure([CLISettingsIssue(line: nil, message: "the file isn't UTF-8 text")])
        }
        do {
            return try CLISettings.decode(text)
        } catch {
            throw failure(error.issues)
        }
    }

    private func failure(_ issues: [CLISettingsIssue]) -> CommandResult {
        .failed("shipyard: \(url.path) doesn't read (\(issues.map(\.description).joined(separator: "; "))); fix it, then try again")
    }
}
