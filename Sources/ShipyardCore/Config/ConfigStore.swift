import Foundation

/// Owns `config.toml`: where it is, the last valid configuration read from
/// it, and the error when the latest read failed.
///
/// The core doesn't watch the file. The app's `ConfigWatcher` watches the
/// directory and calls `reload()`; tests call it directly. A broken file
/// never replaces the last valid configuration. The store never rewrites the
/// file: `append(projects:)` only adds `[[projects]]` blocks at the end.
public final class ConfigStore: @unchecked Sendable {
    /// What a reload found.
    public enum ReloadResult: Equatable, Sendable {
        /// The file is valid and either differs from the last valid
        /// configuration or fixes the previous error.
        case changed(Configuration)
        /// The file is valid and means the same as before.
        case unchanged
        /// The file was rejected; the last valid configuration stays.
        case invalid(ConfigError)
    }

    public let url: URL

    private let lock = NSLock()
    private var _lastValid = Configuration()
    private var _error: ConfigError?
    private var _warnings: [ConfigIssue] = []
    private var handlers: [@Sendable (ReloadResult) -> Void] = []

    public init(url: URL) {
        self.url = url
    }

    /// `$XDG_CONFIG_HOME/shipyard/config.toml`, or `~/.config/shipyard/config.toml`
    /// when `XDG_CONFIG_HOME` is unset, empty or not an absolute path.
    public static func defaultURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        let base: URL
        if let xdg = environment["XDG_CONFIG_HOME"], xdg.hasPrefix("/") {
            base = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            base = home.appendingPathComponent(".config", isDirectory: true)
        }
        return base
            .appendingPathComponent("shipyard", isDirectory: true)
            .appendingPathComponent("config.toml", isDirectory: false)
    }

    /// The configuration the app runs on: the last file that read cleanly,
    /// or the defaults with no projects before any did.
    public var lastValid: Configuration { synchronized { _lastValid } }

    /// Why the latest reload failed; `nil` once a reload succeeds.
    public var error: ConfigError? { synchronized { _error } }

    /// Unknown keys found by the latest successful reload.
    public var warnings: [ConfigIssue] { synchronized { _warnings } }

    /// Calls `handler` after every reload that isn't `.unchanged`: with the
    /// new configuration after a valid change (or a fix), and with the error
    /// after a rejected edit. The orchestrator uses this to move phase,
    /// refresh and show or clear the configuration banner.
    public func onChange(_ handler: @escaping @Sendable (ReloadResult) -> Void) {
        synchronized { handlers.append(handler) }
    }

    /// Reads the file again. A missing or empty file is the defaults with no
    /// projects. A broken file keeps the last valid configuration and sets
    /// `error`; a valid one clears it.
    @discardableResult
    public func reload() -> ReloadResult {
        let outcome: Result<Configuration.Decoded, ConfigError>
        do throws(ConfigError) {
            outcome = .success(try Configuration.decode(read()))
        } catch {
            outcome = .failure(error)
        }

        let (result, toNotify): (ReloadResult, [@Sendable (ReloadResult) -> Void]) = synchronized {
            switch outcome {
            case .failure(let error):
                _error = error
                return (.invalid(error), handlers)
            case .success(let decoded):
                let hadError = _error != nil
                _error = nil
                _warnings = decoded.warnings
                guard decoded.configuration != _lastValid || hadError else { return (.unchanged, []) }
                _lastValid = decoded.configuration
                return (.changed(decoded.configuration), handlers)
            }
        }
        for handler in toNotify { handler(result) }
        return result
    }

    /// Adds `projects` as `[[projects]]` blocks at the end of the file,
    /// creating it (and its directory) with a commented header and the
    /// `#:schema` line when it's missing. Existing text is never rewritten.
    /// Rejects slugs that aren't `owner/name` and names already used, before
    /// writing anything. Returns the reload that follows.
    @discardableResult
    public func append(projects: [NewProject]) throws -> ReloadResult {
        try validate(projects)
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let text = Configuration.header + Configuration.appendText(projects: projects)
            try Data(text.utf8).write(to: url)
            return reload()
        }

        let existing = try Data(contentsOf: url)
        var addition = Configuration.appendText(projects: projects)
        if let last = existing.last, last != UInt8(ascii: "\n") { addition = "\n" + addition }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data(addition.utf8))
        return reload()
    }

    private func validate(_ projects: [NewProject]) throws(ConfigError) {
        var issues: [ConfigIssue] = []
        var names = Set(lastValid.projects.map(\.name))
        for project in projects {
            if project.name.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ConfigIssue(line: nil, message: "a project's `name` can't be empty"))
            } else if !names.insert(project.name).inserted {
                issues.append(ConfigIssue(line: nil, message: "project name `\(project.name)` is already used"))
            }
            if project.repositories.isEmpty {
                issues.append(ConfigIssue(line: nil, message: "project `\(project.name)` needs at least one repository"))
            }
            for repository in project.repositories where !ConfigurationReader.isRepositorySlug(repository) {
                issues.append(ConfigIssue(line: nil, message: "repository `\(repository)` isn't `owner/name`"))
            }
        }
        if !issues.isEmpty { throw ConfigError(issues) }
    }

    private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    /// The file's bytes; a missing file reads as empty.
    private func read() throws(ConfigError) -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { return Data() }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ConfigError([ConfigIssue(line: nil, message: "can't read \(url.path): \(error.localizedDescription)")])
        }
    }
}
