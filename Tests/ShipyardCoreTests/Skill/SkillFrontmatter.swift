import Foundation

/// A strict reading of a skill's YAML frontmatter: the lines between the
/// opening and closing `---`, each `key: value` with a scalar value.
///
/// `npx skills add` parses the frontmatter as YAML and skips a skill whose
/// frontmatter isn't valid, so this reader refuses what YAML refuses rather
/// than splitting at the first colon. A plain (unquoted) value can't contain
/// `: ` or ` #`, can't end with `:`, and can't start with an indicator; a
/// quoted value must close its quotes. Anything richer than one-line scalars
/// (block scalars, lists, nested maps) is refused too: the skill doesn't
/// need it, and refusing keeps the reader small and exact.
struct SkillFrontmatter: Equatable {
    struct Invalid: Error, Equatable, CustomStringConvertible {
        let line: Int
        let reason: String
        var description: String { "frontmatter line \(line): \(reason)" }
    }

    let fields: [String: String]

    subscript(key: String) -> String? { fields[key] }

    init(document: String) throws {
        let lines = document.components(separatedBy: "\n")
        guard lines.first == "---" else { throw Invalid(line: 1, reason: "the file doesn't open with ---") }
        guard let end = lines.dropFirst().firstIndex(of: "---") else {
            throw Invalid(line: 1, reason: "the frontmatter isn't closed with ---")
        }
        var fields: [String: String] = [:]
        for index in 1..<end {
            let line = lines[index]
            let number = index + 1
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let colon = line.range(of: ": ") ?? (line.hasSuffix(":") ? line.range(of: ":", options: .backwards) : nil) else {
                throw Invalid(line: number, reason: "not a `key: value` line")
            }
            let key = String(line[..<colon.lowerBound])
            guard !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else {
                throw Invalid(line: number, reason: "`\(key)` isn't a plain key")
            }
            guard fields[key] == nil else { throw Invalid(line: number, reason: "`\(key)` appears twice") }
            let raw = String(line[colon.upperBound...]).trimmingCharacters(in: .whitespaces)
            do {
                fields[key] = try Self.scalar(raw)
            } catch let reason as Reason {
                throw Invalid(line: number, reason: "`\(key)`: \(reason.text)")
            }
        }
        self.fields = fields
    }

    private struct Reason: Error { let text: String }

    private static func scalar(_ raw: String) throws -> String {
        guard let first = raw.first else { throw Reason(text: "the value is empty") }
        switch first {
        case "\"": return try doubleQuoted(raw)
        case "'": return try singleQuoted(raw)
        case "|", ">": throw Reason(text: "block scalars aren't read here; quote the value on one line")
        default: return try plain(raw)
        }
    }

    private static func plain(_ raw: String) throws -> String {
        if let first = raw.first, "[]{},#&*!%@`".contains(first) {
            throw Reason(text: "a plain value can't start with `\(first)`; quote it")
        }
        for indicator in ["- ", "? ", ": "] where raw.hasPrefix(indicator) {
            throw Reason(text: "a plain value can't start with `\(indicator)`; quote it")
        }
        if raw.contains(": ") || raw.hasSuffix(":") {
            throw Reason(text: "a plain value can't contain `: `; quote it")
        }
        if raw.contains(" #") {
            throw Reason(text: "` #` starts a comment in a plain value; quote it")
        }
        return raw
    }

    private static func doubleQuoted(_ raw: String) throws -> String {
        var value = ""
        var characters = raw.dropFirst().makeIterator()
        while let character = characters.next() {
            switch character {
            case "\"":
                let rest = String(IteratorSequence(characters))
                guard rest.trimmingCharacters(in: .whitespaces).isEmpty || rest.hasPrefix(" #") else {
                    throw Reason(text: "text follows the closing quote")
                }
                return value
            case "\\":
                guard let escaped = characters.next() else { throw Reason(text: "the value ends in an escape") }
                switch escaped {
                case "\"", "\\", "/": value.append(escaped)
                case "n": value.append("\n")
                case "t": value.append("\t")
                default: throw Reason(text: "`\\\(escaped)` isn't an escape shipyard's frontmatter uses")
                }
            default:
                value.append(character)
            }
        }
        throw Reason(text: "the double quote isn't closed")
    }

    private static func singleQuoted(_ raw: String) throws -> String {
        var value = ""
        var characters = Array(raw.dropFirst())[...]
        while let character = characters.popFirst() {
            if character == "'" {
                if characters.first == "'" {
                    characters.removeFirst()
                    value.append("'")
                    continue
                }
                let rest = String(characters)
                guard rest.trimmingCharacters(in: .whitespaces).isEmpty || rest.hasPrefix(" #") else {
                    throw Reason(text: "text follows the closing quote")
                }
                return value
            }
            value.append(character)
        }
        throw Reason(text: "the single quote isn't closed")
    }
}
