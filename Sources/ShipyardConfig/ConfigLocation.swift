import Foundation

/// Which `config.toml` the `shipyard` command files pings against: the one
/// the app reads. The app, started from Finder, may not see the
/// `XDG_CONFIG_HOME` an agent's shell sets, so it records the path it reads
/// in one JSON file, `config-location.json`, in its support folder beside
/// `repositories.json`, and the command reads that path. Before the app has
/// ever run there's no record, and the command looks the file up itself,
/// as `ConfigStore.defaultURL` does. The format is private (ADR 0004): only
/// the app writes it, only the command reads it.
///
/// It fails safe: a missing file, one that doesn't read, one a newer build
/// wrote or one whose path isn't absolute reads as no record. Each write
/// replaces the file atomically, so the command reads a whole file or none.
public enum ConfigLocation {
    /// The version of the file format this build writes. A file with a
    /// newer one reads as no record.
    public static let currentVersion = 1
    public static let fileName = "config-location.json"

    /// The configuration file the command uses: the path the app recorded
    /// in `support` (`SupportFolder.app`; tests pass a temporary folder),
    /// or `ConfigStore.defaultURL(environment:home:)` when it never has.
    public static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        support: URL
    ) -> URL {
        recorded(in: support) ?? ConfigStore.defaultURL(environment: environment, home: home)
    }

    /// The path the app last recorded in `support`, if any reads.
    public static func recorded(in support: URL) -> URL? {
        guard let data = try? Data(contentsOf: url(in: support)),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version <= currentVersion,
              file.path.hasPrefix("/")
        else { return nil }
        return URL(fileURLWithPath: file.path, isDirectory: false)
    }

    /// Records `config` as the file the app reads, in `support`; writes
    /// nothing when that's what's recorded already.
    public static func record(_ config: URL, in support: URL) throws {
        guard recorded(in: support)?.path != config.path else { return }
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(File(version: currentVersion, path: config.path)).write(to: url(in: support), options: .atomic)
    }

    /// `config-location.json` in `support`.
    public static func url(in support: URL) -> URL {
        support.appendingPathComponent(fileName, isDirectory: false)
    }

    // `config-location.json`:
    //
    //     { "path": "/Users/me/.config/shipyard/config.toml", "version": 1 }
    private struct File: Codable {
        var version: Int
        var path: String
    }
}
