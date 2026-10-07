import Foundation

/// Keeps each project's repositories as the app last resolved them, groups
/// and `owner/*` looked up, in one JSON file, `repositories.json`, beside
/// `state.json` (`~/Library/Application Support/Shipyard/`; tests pass a
/// temporary directory). The `shipyard` CLI reads it to file a ping by its
/// repository without calling GitHub itself. The format is private (ADR
/// 0004): only the app writes it, only the CLI reads it.
///
/// It fails safe: a missing file, one that doesn't read, or one a newer
/// build wrote reads as no lists, so a ping still matches the
/// configuration's `owner/name` selectors. The next refresh that resolves
/// writes it again. Each write replaces the file atomically, so the CLI
/// reads a whole file or none.
public struct ResolvedRepositoriesStore: Sendable {
    /// The version of the file format this build writes. A file with a
    /// newer one reads as no lists.
    public static let currentVersion = 1
    public static let fileName = "repositories.json"

    /// The directory the app provides.
    public let directory: URL
    /// `repositories.json` in `directory`.
    public var url: URL { directory.appendingPathComponent(Self.fileName, isDirectory: false) }

    public init(directory: URL) {
        self.directory = directory
    }

    /// Each project's repositories (`owner/name`) by project slug, as last
    /// recorded; empty when there's nothing that reads.
    public func load() -> [String: [String]] {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data),
              file.version <= Self.currentVersion
        else { return [:] }
        return file.projects
    }

    /// Records `projects`, each project's repositories by its slug, replacing
    /// what was there; writes nothing when it's what the file already holds.
    public func record(_ projects: [String: [String]]) throws {
        guard projects != load() else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(File(version: Self.currentVersion, projects: projects)).write(to: url, options: .atomic)
    }

    // `repositories.json`:
    //
    //     { "version": 1, "projects": { "shop": ["yahyabedirhan/shop", "yahyabedirhan/shop-api"] } }
    private struct File: Codable {
        var version: Int
        var projects: [String: [String]]
    }
}
