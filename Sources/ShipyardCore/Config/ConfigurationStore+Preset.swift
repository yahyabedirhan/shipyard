import Foundation
import ShipyardConfig

// The third writer (ADR 0001, amended): presets are the app's, so writing
// one is the core's, over the store ShipyardConfig owns (ADR 0006).
extension ConfigurationStore {
    /// Writes `preset`'s whole file, with `projects` as its picked
    /// repositories, for onboarding's first step: only when the file is
    /// missing or its only live key is `version`. Creates the directory when
    /// it's missing. Throws a `ConfigurationError` (and writes nothing) when the
    /// file holds anything else or doesn't read, when a project is invalid
    /// (as for `append(projects:)`), or when the preset's file wouldn't read
    /// with these projects; throws the file system's error when it can't
    /// write. Returns the reload that follows.
    @discardableResult
    public func writePreset(_ preset: Preset, projects: [NewProject] = []) throws -> ReloadResult {
        try validate(projects, against: [])
        let text = preset.text(projects: projects)
        _ = try Configuration.decode(text)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) {
            guard let current = String(data: try read(), encoding: .utf8), Configuration.acceptsPreset(current) else {
                throw Configuration.presetRefused
            }
            // In place, as `setLayout`: a symlinked file stays a symlink.
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.truncate(atOffset: 0)
            try handle.write(contentsOf: Data(text.utf8))
        } else {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // `withoutOverwriting`: a file an editor wrote meanwhile wins.
            try Data(text.utf8).write(to: url, options: .withoutOverwriting)
        }
        return reload()
    }
}
