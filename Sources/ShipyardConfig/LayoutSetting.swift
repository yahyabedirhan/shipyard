import Foundation

extension Configuration {
    static func settingLayout(
        _ layout: MenuLayout, in text: String, themes: ThemeLibrary = .builtIn
    ) throws(ConfigurationError) -> String {
        let current = try decode(text, themes: themes).configuration
        let map = TOMLSourceMap(text)
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let value = tomlString(layout.rawValue)
        let menu: ConfigurationPath = [.key("menu")]

        if let key = map.entries.first(where: { !$0.isHeader && $0.path == menu + [.key("layout")] }) {
            guard key.line == key.endLine, let replaced = replacingValue(of: lines[key.line - 1], with: value) else {
                throw cantSetLayout(layout, line: key.line)
            }
            lines[key.line - 1] = replaced
        } else if let header = map.entries.first(where: { $0.isHeader && $0.path == menu }) {
            lines.insert("layout = \(value)", at: header.line)
        } else if let other = map.entries.first(where: { $0.path.first == menu.first }) {
            throw cantSetLayout(layout, line: other.line)
        } else if let uncommented = uncommentingMenuExample(in: lines, map: map, value: value) {
            lines = uncommented
        } else {
            lines = addingMenuTable(to: lines, map: map, value: value)
        }

        let edited = lines.joined(separator: "\n")
        var expected = current
        expected.menu.layout = layout
        guard (try? decode(edited, themes: themes))?.configuration == expected else {
            throw cantSetLayout(layout, line: map.entries.first { $0.path.first == menu.first }?.line)
        }
        return edited
    }

    private static func uncommentingMenuExample(in lines: [String], map: TOMLSourceMap, value: String) -> [String]? {
        let starts = lines.indices.filter { lines[$0].wholeMatch(of: /[ \t]*#[ \t]*\[[ \t]*menu[ \t]*\][ \t]*(#.*)?\r?/) != nil }
        for start in starts {
            let line = start + 1
            let nextTable = map.entries.first { $0.isHeader && $0.line > line }?.line ?? lines.count + 1
            guard !map.entries.contains(where: { !$0.isHeader && $0.line > line && $0.line < nextTable }) else { continue }
            var out = lines
            out[start] = uncommented(lines[start])
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

    private static func addingMenuTable(to lines: [String], map: TOMLSourceMap, value: String) -> [String] {
        let table = ["[menu]", "layout = \(value)"]
        var out = lines
        guard let first = map.entries.first(where: \.isHeader) else {
            if out.last == "" { out.removeLast() }
            if let last = out.last, !last.trimmingCharacters(in: .whitespaces).isEmpty { out.append("") }
            return out + table + [""]
        }
        var index = first.line - 1
        while index > 0, isComment(out[index - 1]) { index -= 1 }
        if index == 0 { index = first.line - 1 }
        var insertion = table + [""]
        if index > 0, !out[index - 1].trimmingCharacters(in: .whitespaces).isEmpty { insertion.insert("", at: 0) }
        out.insert(contentsOf: insertion, at: index)
        return out
    }

    static func isComment(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
    }

    private static func isCommentedTable(_ line: String) -> Bool {
        line.firstMatch(of: /^[ \t]*#[ \t]*\[/) != nil
    }

    static func uncommented(_ line: String) -> String {
        line.replacing(/^([ \t]*)#[ \t]?/, with: { $0.output.1 })
    }

    static func replacingValue(of line: String, with value: String) -> String? {
        guard let match = line.firstMatch(of: /^([^=]*=[ \t]*)("(?:[^"\\]|\\.)*"|'[^']*')(.*)$/) else { return nil }
        return match.output.1 + value + match.output.3
    }

    private static func cantSetLayout(_ layout: MenuLayout, line: Int?) -> ConfigurationError {
        ConfigurationError([ConfigurationIssue(
            line: line,
            message: "can't switch the layout: `[menu]` is written in a form shipyard doesn't edit; set `layout = \"\(layout.rawValue)\"` under `[menu]` by hand"
        )])
    }
}
