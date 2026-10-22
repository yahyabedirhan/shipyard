import Foundation

extension Configuration {
    /// `text` with the top-level `theme` set to `name`, the theme's own
    /// spelling, for the gear menu's Theme submenu: replaces the key's
    /// value, or uncomments the new-file header's `# theme = …` example, or
    /// adds the key above the first table, after `version` when it's there.
    /// Every other line and comment stays as it was. Throws the file's
    /// `ConfigurationError` when it doesn't read, and one saying why when
    /// `name` is no theme of `themes` or the edit can't be made.
    package static func settingTheme(
        _ name: String, in text: String, themes: ThemeLibrary = .builtIn
    ) throws(ConfigurationError) -> String {
        let current = try decode(text, themes: themes).configuration
        guard let theme = themes.theme(named: name) else {
            let names = themes.names.map { "`\($0)`" }.joined(separator: ", ")
            throw ConfigurationError([ConfigurationIssue(line: nil, message: "can't switch the theme: `\(name)` isn't a theme (expected one of \(names))")])
        }
        let map = TOMLSourceMap(text)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let value = tomlString(theme.name)
        let key: ConfigurationPath = [.key("theme")]
        let firstTable = map.entries.first(where: \.isHeader)?.line ?? lines.count + 1

        if let entry = map.entries.first(where: { !$0.isHeader && $0.path == key }) {
            guard entry.line == entry.endLine, let replaced = replacingValue(of: lines[entry.line - 1], with: value) else {
                throw cantSetTheme(theme.name, line: entry.line)
            }
            lines[entry.line - 1] = replaced
        } else if let example = lines.indices.first(where: {
            $0 + 1 < firstTable && lines[$0].firstMatch(of: /^[ \t]*#[ \t]*theme[ \t]*=/) != nil
        }) {
            lines[example] = replacingValue(of: uncommented(lines[example]), with: value) ?? "theme = \(value)"
        } else if let version = map.entries.first(where: { !$0.isHeader && $0.path == [.key("version")] && $0.line < firstTable }) {
            lines.insert("theme = \(value)", at: version.endLine)
        } else if firstTable <= lines.count {
            var index = firstTable - 1
            while index > 0, isComment(lines[index - 1]) { index -= 1 }
            lines.insert(contentsOf: ["theme = \(value)", ""], at: index)
        } else {
            if lines.last == "" { lines.removeLast() }
            lines += ["theme = \(value)", ""]
        }

        let edited = lines.joined(separator: "\n")
        var expected = current
        expected.theme = theme.name
        guard (try? decode(edited, themes: themes))?.configuration == expected else {
            throw cantSetTheme(theme.name, line: map.entries.first { $0.path == key }?.line)
        }
        return edited
    }

    private static func cantSetTheme(_ name: String, line: Int?) -> ConfigurationError {
        ConfigurationError([ConfigurationIssue(
            line: line,
            message: "can't switch the theme: `theme` is written in a form shipyard doesn't edit; set `theme = \"\(name)\"` at the top of the file by hand"
        )])
    }
}
