import Foundation

/// Setting `[menu] layout` in the text of `config.toml` for the header's
/// layout button: one line changes (or a `[menu]` table is added), and
/// every other line and comment stays as it was.
extension Configuration {
    /// `text` with `[menu] layout` set to `layout`.
    ///
    /// Throws the file's own `ConfigError` when `text` doesn't read, and a
    /// `ConfigError` saying so when the edit wouldn't read back as the same
    /// configuration with only the layout changed (a `[menu]` written in a
    /// form this doesn't edit, such as an inline table).
    static func settingLayout(_ layout: MenuLayout, in text: String) throws(ConfigError) -> String {
        let current = try decode(text).configuration
        let map = TOMLSourceMap(text)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let value = tomlString(layout.rawValue)
        let menu: ConfigPath = [.key("menu")]

        if let key = map.entries.first(where: { !$0.isHeader && $0.path == menu + [.key("layout")] }) {
            guard key.line == key.endLine, let replaced = replacingValue(of: lines[key.line - 1], with: value) else {
                throw cantSetLayout(layout, line: key.line)
            }
            lines[key.line - 1] = replaced
        } else if let header = map.entries.first(where: { $0.isHeader && $0.path == menu }) {
            lines.insert("layout = \(value)", at: header.line)
        } else if let other = map.entries.first(where: { $0.path.first == menu.first }) {
            // `menu = { … }`, `menu.layout`-less dotted keys, `[menu.x]`.
            throw cantSetLayout(layout, line: other.line)
        } else if let uncommented = uncommentingMenuExample(in: lines, map: map, value: value) {
            lines = uncommented
        } else {
            lines = addingMenuTable(to: lines, map: map, value: value)
        }

        let edited = lines.joined(separator: "\n")
        var expected = current
        expected.menu.layout = layout
        guard (try? decode(edited))?.configuration == expected else {
            throw cantSetLayout(layout, line: map.entries.first { $0.path.first == menu.first }?.line)
        }
        return edited
    }

    /// `lines` with a commented-out `# [menu]` (the new-file header's
    /// example) uncommented and its `# layout = …` line, when the comment
    /// block under it has one, uncommented with `value`; otherwise `layout`
    /// goes under the header. `nil` when there's no such comment, or when
    /// live settings follow it before the next table, which uncommenting
    /// would move into `[menu]`.
    private static func uncommentingMenuExample(in lines: [String], map: TOMLSourceMap, value: String) -> [String]? {
        let starts = lines.indices.filter { lines[$0].wholeMatch(of: /[ \t]*#[ \t]*\[[ \t]*menu[ \t]*\][ \t]*(#.*)?\r?/) != nil }
        for start in starts {
            let line = start + 1 // 1-based
            let nextTable = map.entries.first { $0.isHeader && $0.line > line }?.line ?? lines.count + 1
            guard !map.entries.contains(where: { !$0.isHeader && $0.line > line && $0.line < nextTable }) else { continue }
            var out = lines
            out[start] = uncommented(lines[start])
            // The example's own lines: the comments right under it, up to a
            // blank line or the next commented table.
            var index = start + 1
            while index < out.count, isComment(out[index]), !isCommentedTable(out[index]) {
                if out[index].firstMatch(of: /^[ \t]*#[ \t]*layout[ \t]*=/) != nil {
                    out[index] = replacingValue(of: uncommented(out[index]), with: value) ?? "layout = \(value)"
                    return out
                }
                index += 1
            }
            out.insert("layout = \(value)", at: start + 1)
            return out
        }
        return nil
    }

    /// `lines` with a `[menu]` table added before the first table (above the
    /// comments right over it), or at the end when there's no table: top-
    /// level keys stay above every table, so none moves into `[menu]`.
    private static func addingMenuTable(to lines: [String], map: TOMLSourceMap, value: String) -> [String] {
        let table = ["[menu]", "layout = \(value)"]
        var out = lines
        guard let first = map.entries.first(where: \.isHeader) else {
            // Drop the final newline's empty piece, then end with one again.
            if out.last == "" { out.removeLast() }
            if let last = out.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { out.append("") }
            return out + table + [""]
        }
        var index = first.line - 1
        while index > 0, isComment(out[index - 1]) { index -= 1 }
        // Never above the `#:schema` line or the file's opening comments.
        if index == 0 { index = first.line - 1 }
        var insertion = table + [""]
        if index > 0, !out[index - 1].trimmingCharacters(in: .whitespaces).isEmpty { insertion.insert("", at: 0) }
        out.insert(contentsOf: insertion, at: index)
        return out
    }

    private static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }

    private static func isCommentedTable(_ line: String) -> Bool {
        line.firstMatch(of: /^[ \t]*#[ \t]*\[/) != nil
    }

    /// `line` without its leading `#` and the space after it.
    private static func uncommented(_ line: String) -> String {
        line.replacing(/^([ \t]*)#[ \t]?/, with: { $0.output.1 })
    }

    /// `line` (`key = "value"  # comment`) with its string value replaced;
    /// `nil` when the value isn't a one-line string.
    private static func replacingValue(of line: String, with value: String) -> String? {
        guard let match = line.firstMatch(of: /^([^=]*=[ \t]*)("(?:[^"\\]|\\.)*"|'[^']*')(.*)$/) else { return nil }
        return match.output.1 + value + match.output.3
    }

    private static func cantSetLayout(_ layout: MenuLayout, line: Int?) -> ConfigError {
        ConfigError([ConfigIssue(
            line: line,
            message: "can't switch the layout: `[menu]` is written in a form shipyard doesn't edit; set `layout = \"\(layout.rawValue)\"` under `[menu]` by hand"
        )])
    }
}
