import Foundation
import ShipyardCommand

/// Owns `config.toml`: where it is, the last valid configuration read from
/// it, and the error when the latest read failed; and the theme files in the
/// `themes` folder beside it, read on every reload.
///
/// The core doesn't watch the files. The app's `ConfigurationWatcher`s watch the
/// directory and the `themes` folder and call `reload()`; tests call it directly. A broken file
/// never replaces the last valid configuration. The store never rewrites the
/// file as a whole: `append(projects:)` only adds `[[projects]]` blocks at
/// the end, `setLayout(_:)` changes or adds only `[menu] layout`,
/// `setTheme(_:)` only the top-level `theme`, and the core's
/// `writePreset(_:projects:)` writes a whole file only over one that holds
/// nothing but `version` and `theme`.
public final class ConfigurationStore: @unchecked Sendable {
    /// What a reload found.
    public enum ReloadResult: Equatable, Sendable {
        case changed(Configuration)
        case unchanged
        case invalid(ConfigurationError)
    }

    public static let fileName = "config.toml"

    public let url: URL
    /// The folder of the user's theme files: `themes` beside `url`.
    public let themesFolder: URL

    private let lock = NSLock()
    private var _lastValid = Configuration()
    private var _theme = BuiltInThemes.system
    private var _themes = ThemeLibrary.builtIn
    private var _themeFiles: [ThemeFiles.File] = []
    /// The theme each file last read, kept while the file has a problem.
    private var _lastGoodThemes: [URL: Theme] = [:]
    private var _error: ConfigurationError?
    private var _warnings: [ConfigurationIssue] = []
    private var _modified: Date?
    private var _acceptsPreset = true

    public init(url: URL) {
        self.url = url
        themesFolder = ThemeFiles.folder(beside: url)
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
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// The configuration the app runs on: the last file that read cleanly,
    /// or the defaults with no projects before any did.
    public var lastValid: Configuration { synchronized { _lastValid } }

    /// The theme `lastValid` picks, from the themes as the latest reload
    /// read them: System before any file read cleanly, and while the
    /// theme it names isn't one.
    public var theme: Theme { synchronized { _theme } }

    /// The themes `theme` may name, as the latest reload read them: the
    /// built-ins and the user's files', a file with a problem keeping the
    /// theme it last read.
    public var themes: ThemeLibrary { synchronized { _themes } }

    /// Each theme file as the latest reload read it, by file name.
    public var themeFiles: [ThemeFiles.File] { synchronized { _themeFiles } }

    /// The theme files' problems, as the latest reload found them.
    public var themeIssues: [ThemeIssue] { synchronized { _themeFiles.flatMap(\.issues) } }

    /// Why the latest reload failed; `nil` once a reload succeeds.
    public var error: ConfigurationError? { synchronized { _error } }

    /// Unknown keys found by the latest reload; empty when it failed.
    public var warnings: [ConfigurationIssue] { synchronized { _warnings } }

    /// The file's modification time as the latest reload read it; `nil`
    /// before any reload and when there was no file.
    public var modified: Date? { synchronized { _modified } }

    /// Whether the latest reload found a file onboarding may write a preset
    /// over: missing, or holding no live key but `version` (the header the
    /// app creates) and `theme`. `writePreset` checks the file again before writing.
    public var acceptsPreset: Bool { synchronized { _acceptsPreset } }

    /// Reads the theme files and the file again. A missing or empty file is
    /// the defaults with no projects. A broken file keeps the last valid
    /// configuration, sets `error` and clears `warnings`; a valid one clears
    /// the error. The theme follows the theme files on every reload, so a
    /// saved theme file applies though `config.toml` is `unchanged`.
    @discardableResult
    public func reload() -> ReloadResult {
        let themeFiles = ThemeFiles.read(themesFolder)
        let (themes, lastGoodThemes) = ThemeLibrary.with(themeFiles, keeping: synchronized { _lastGoodThemes })
        let modified = ConfigurationCheck.modificationDate(of: url)
        let outcome: Result<Configuration.Decoded, ConfigurationError>
        var acceptsPreset = false
        do throws(ConfigurationError) {
            let data = try read()
            outcome = .success(try Configuration.decode(data, themes: themes))
            acceptsPreset = String(data: data, encoding: .utf8).map { Configuration.acceptsPreset($0, themes: themes) } ?? false
        } catch {
            outcome = .failure(error)
        }

        return synchronized {
            _modified = modified
            _acceptsPreset = acceptsPreset
            _themes = themes
            _themeFiles = themeFiles
            _lastGoodThemes = lastGoodThemes
            defer { _theme = themes.theme(for: _lastValid) }
            switch outcome {
            case .failure(let error):
                _error = error
                _warnings = []
                return .invalid(error)
            case .success(let decoded):
                let hadError = _error != nil
                _error = nil
                _warnings = decoded.warnings
                guard decoded.configuration != _lastValid || hadError else { return .unchanged }
                _lastValid = decoded.configuration
                return .changed(decoded.configuration)
            }
        }
    }

    /// The latest reload's verdict, as at `checked`: what the app records
    /// in `config-status.json` and `shipyard config check` prints.
    public func check(at checked: Date) -> ConfigurationCheck {
        synchronized {
            ConfigurationCheck(
                name: ConfigurationStore.fileName,
                checked: checked,
                file: url,
                modified: _modified,
                problems: (_error?.issues ?? []).map(ConfigurationCheck.Issue.init),
                warnings: _warnings.map(ConfigurationCheck.Issue.init)
            )
        }
    }

    /// Reads the file at `url` and the theme files beside it as the app
    /// does, at `now`, for `shipyard config check`: `config.toml`'s verdict,
    /// then each theme file's, by file name.
    public static func checks(_ url: URL, at now: Date) -> [ConfigurationCheck] {
        let store = ConfigurationStore(url: url)
        store.reload()
        return [store.check(at: now)] + store.themeFiles.map { $0.check(at: now) }
    }

    /// Creates the file (and its directory) with the commented header and
    /// the `#:schema` line when it's missing: at every start, on the Refresh
    /// button, and before "Open configuration file" opens it. An existing
    /// file is never touched.
    public func createIfMissing() throws {
        let fileManager = FileManager.default
        guard !fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Configuration.header.utf8).write(to: url, options: .withoutOverwriting)
    }

    /// Adds `projects` as `[[projects]]` blocks at the end of the file,
    /// creating it (and its directory) with a commented header and the
    /// `#:schema` line when it's missing. Existing text is never rewritten.
    /// Rejects repositories that aren't `owner/name`, a repository listed
    /// twice in one project and project slugs already used, before writing
    /// anything. Returns the reload that follows.
    @discardableResult
    public func append(projects: [NewProject]) throws -> ReloadResult {
        try validate(projects, against: lastValid.projects.map(\.slug))
        try createIfMissing()
        let existing = try Data(contentsOf: url)
        var addition = Configuration.appendText(projects: projects)
        if let last = existing.last, last != UInt8(ascii: "\n") { addition = "\n" + addition }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        _ = try handle.seekToEnd()
        try handle.write(contentsOf: Data(addition.utf8))
        return reload()
    }

    /// Sets `[menu] layout` in the file, for the header's layout button:
    /// replaces the key's value, or uncomments the new-file header's
    /// `# [menu]` example, or adds a `[menu]` table before the first table,
    /// leaving every other line and comment as it was. Creates the file
    /// with its header when it's missing. Throws the file's `ConfigurationError`
    /// when it doesn't read, one saying why when the edit can't be made,
    /// or the file system's error, and then writes nothing. Returns the
    /// reload that follows.
    @discardableResult
    public func setLayout(_ layout: MenuLayout) throws -> ReloadResult {
        try createIfMissing()
        guard let text = String(data: try read(), encoding: .utf8) else {
            throw ConfigurationError([ConfigurationIssue(line: nil, message: "the file isn't UTF-8 text")])
        }
        let edited = try Configuration.settingLayout(layout, in: text, themes: themes)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(edited.utf8))
        return reload()
    }

    /// Sets the top-level `theme` in the file to `name`, for the gear menu's
    /// Theme submenu: replaces the key's value, or uncomments the new-file
    /// header's `# theme = …` example, or adds the key above the first
    /// table, leaving every other line and comment as it was
    /// (`Configuration.settingTheme`). Creates the file with its header when
    /// it's missing. Throws the file's `ConfigurationError` when it doesn't
    /// read, one saying why when `name` isn't a theme or the edit can't be
    /// made, or the file system's error, and then writes nothing. Returns
    /// the reload that follows.
    @discardableResult
    public func setTheme(_ name: String) throws -> ReloadResult {
        try createIfMissing()
        guard let text = String(data: try read(), encoding: .utf8) else {
            throw ConfigurationError([ConfigurationIssue(line: nil, message: "the file isn't UTF-8 text")])
        }
        let edited = try Configuration.settingTheme(name, in: text, themes: themes)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(edited.utf8))
        return reload()
    }

    package func validate(_ projects: [NewProject], against existing: [String]) throws(ConfigurationError) {
        var issues: [ConfigurationIssue] = []
        var slugs = Set(existing)
        for project in projects {
            if project.title.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append(ConfigurationIssue(line: nil, message: "a project's name can't be empty"))
            } else if project.slug.isEmpty {
                issues.append(ConfigurationIssue(line: nil, message: "project `\(project.title)` needs a letter or digit in its name, for its slug"))
            } else if !slugs.insert(project.slug).inserted {
                issues.append(ConfigurationIssue(line: nil, message: "project slug `\(project.slug)` is already used"))
            }
            if project.repositories.isEmpty {
                issues.append(ConfigurationIssue(line: nil, message: "project `\(project.title)` needs at least one repository"))
            }
            var repositories = Set<String>()
            for repository in project.repositories {
                if !GitRemote.isRepositorySlug(repository) {
                    issues.append(ConfigurationIssue(line: nil, message: "repository `\(repository)` isn't `owner/name`"))
                } else if !repositories.insert(repository.lowercased()).inserted {
                    issues.append(ConfigurationIssue(line: nil, message: ConfigurationReader.duplicateRepositoryMessage(repository, project: project.title)))
                }
            }
        }
        if !issues.isEmpty { throw ConfigurationError(issues) }
    }

    private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    package func read() throws(ConfigurationError) -> Data {
        guard FileManager.default.fileExists(atPath: url.path) else { return Data() }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw ConfigurationError([ConfigurationIssue(line: nil, message: "can't read \(url.path): \(error.localizedDescription)")])
        }
    }
}

extension Configuration {
    package static func acceptsPreset(_ text: String, themes: ThemeLibrary = .builtIn) -> Bool {
        guard (try? decode(text, themes: themes)) != nil else { return false }
        // `theme` may be set already: the gear menu's Theme submenu works
        // before onboarding, and the preset keeps it.
        return TOMLSourceMap(text).entries.allSatisfy { !$0.isHeader && ($0.path == [.key("version")] || $0.path == [.key("theme")]) }
    }
}

extension ConfigurationCheck.Issue {
    public init(_ issue: ConfigurationIssue) {
        self.init(line: issue.line, message: issue.message)
    }
}
