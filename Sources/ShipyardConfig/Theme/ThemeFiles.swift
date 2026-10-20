import Foundation
import ShipyardCommand

/// The user's theme files: every `*.toml` in the `themes` folder beside
/// `config.toml`, such as `~/.config/shipyard/themes/Sunset.toml`. Each file
/// is one theme; its `extends` may name a built-in theme or another file's.
public enum ThemeFiles {
    public static let folderName = "themes"

    /// One theme file as it read: its theme, or the problems that kept it out.
    public struct File: Equatable, Sendable {
        public var url: URL
        /// The file's name in banners and in `config check`: `themes/Sunset.toml`.
        public var name: String
        /// The modification time, taken before the bytes.
        public var modified: Date?
        /// `nil` when the file has a problem.
        public var theme: Theme?
        public var issues: [ThemeIssue]

        /// The file's verdict, in the shape `shipyard config check` prints.
        public func check(at checked: Date) -> ConfigurationCheck {
            ConfigurationCheck(
                name: name, checked: checked, file: url, modified: modified,
                problems: issues.map { ConfigurationCheck.Issue(line: $0.line, message: $0.message) },
                warnings: []
            )
        }
    }

    /// The `themes` folder beside the configuration file at `config`.
    public static func folder(beside config: URL) -> URL {
        config.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
    }

    /// The `*.toml` files in `folder`, by file name; none when there's no folder.
    public static func urls(in folder: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .map { folder.appendingPathComponent($0, isDirectory: false) }
            .filter { $0.pathExtension.lowercased() == "toml" }
    }

    /// Reads every theme file in `folder`, by file name, each resolved
    /// against the built-in themes and the other files. Of two files with
    /// one theme name the later wins, and the earlier has a problem saying so.
    public static func read(_ folder: URL) -> [File] {
        var files: [File] = []
        var definitions: [ThemeDefinition] = []
        for url in urls(in: folder) {
            let name = "\(folderName)/\(url.lastPathComponent)"
            let modified = ConfigurationCheck.modificationDate(of: url)
            var file = File(url: url, name: name, modified: modified, theme: nil, issues: [])
            if let data = try? Data(contentsOf: url) {
                if let text = String(data: data, encoding: .utf8) {
                    let parsed = ThemeReader.definition(text, file: name, source: .file(url))
                    if let definition = parsed.definition { definitions.append(definition) }
                    file.issues = parsed.issues
                } else {
                    file.issues = [ThemeIssue(file: name, line: nil, message: "the file isn't UTF-8 text")]
                }
            } else {
                file.issues = [ThemeIssue(file: name, line: nil, message: "can't read \(url.path)")]
            }
            files.append(file)
        }

        let resolved = ThemeReader.resolve(definitions, extending: BuiltInThemes.definitions)
        for index in files.indices {
            let url = files[index].url
            files[index].theme = resolved.themes.first { $0.source == .file(url) }
            files[index].issues += resolved.issues.filter { $0.file == files[index].name }
        }
        for (position, definition) in definitions.enumerated() {
            guard let later = definitions[(position + 1)...].last(where: {
                      $0.name.caseInsensitiveCompare(definition.name) == .orderedSame
                  }),
                  let index = files.firstIndex(where: { $0.name == definition.file })
            else { continue }
            files[index].issues.append(ThemeIssue(
                file: definition.file, line: nil,
                message: "theme `\(definition.name)` is also in \(later.file), which replaces this one"
            ))
        }
        return files
    }
}

extension ThemeLibrary {
    /// The built-in themes and the user's files' themes, the files' after
    /// them so a file replaces a built-in theme with its name. A file that
    /// has a problem keeps the theme it last read (`lastGood`, by file);
    /// one that never read is `unread`. Returns the library and the
    /// last good themes to keep for the next read.
    public static func with(
        _ files: [ThemeFiles.File], keeping lastGood: [URL: Theme] = [:]
    ) -> (library: ThemeLibrary, lastGood: [URL: Theme]) {
        var kept: [URL: Theme] = [:]
        var themes = BuiltInThemes.themes
        var unread: [String] = []
        for file in files {
            if let theme = file.theme ?? lastGood[file.url] {
                kept[file.url] = theme
                themes.append(theme)
            } else {
                unread.append(file.name)
            }
        }
        return (ThemeLibrary(themes, unread: unread), kept)
    }

    /// The built-in themes and the theme files beside the configuration
    /// file at `config`, as they read now.
    public static func beside(config: URL) -> ThemeLibrary {
        with(ThemeFiles.read(ThemeFiles.folder(beside: config))).library
    }
}
