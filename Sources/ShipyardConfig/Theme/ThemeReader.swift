import Foundation
import TOMLDecoder

/// What one theme file says, before `extends` fills what it leaves out.
public struct ThemeDefinition: Sendable {
    public var file: String
    public var source: ThemeSource
    public var name: String
    public var summary: String
    public var extends: String?

    /// `any` sets both appearances; `light` and `dark` override it for one.
    enum Layer: String, CaseIterable, Sendable {
        case any, light, dark
    }

    /// A token's value as written, with where it was written, so a value that
    /// names no palette entry is reported on its line once `extends` is known.
    struct Entry: Sendable {
        var text: String
        var path: String
        var line: Int?
    }

    /// The line of `extends`, for problems found while resolving.
    var extendsLine: Int?
    var palette: [Layer: [String: ThemeValue]] = [:]
    var tokens: [Layer: [ThemeToken: Entry]] = [:]
    var knobs = KnobChanges()

    var fillsLight: Bool { !(tokens[.light] ?? [:]).isEmpty || !(palette[.light] ?? [:]).isEmpty }
    var fillsDark: Bool { !(tokens[.dark] ?? [:]).isEmpty || !(palette[.dark] ?? [:]).isEmpty }
    var fillsAny: Bool { !(tokens[.any] ?? [:]).isEmpty || !(palette[.any] ?? [:]).isEmpty }

    /// The one appearance a theme with no `extends` and no `[any.*]` fills,
    /// which it then draws in both; `nil` when it fills both or extends another.
    var single: ThemeAppearance? {
        guard extends == nil, !fillsAny, fillsLight != fillsDark else { return nil }
        return fillsLight ? .light : .dark
    }
}

/// The knobs one file sets; the ones it leaves out come from `extends`.
struct KnobChanges: Sendable {
    var fontFamily: String?
    var fontMono: String?
    var fontSize: Double?
    var density: String?
    var row: Double?
    var header: Double?
    var bar: Double?
    var gutter: Double?
    var small: Double?
    var medium: Double?
    var large: Double?
    var glass: Bool?

    func apply(to knobs: inout ThemeKnobs) {
        if let fontFamily { knobs.fontFamily = fontFamily }
        if let fontMono { knobs.fontMono = fontMono }
        if let fontSize { knobs.fontSize = fontSize }
        if let density, let preset = ThemeKnobs.densityPresets[density] {
            knobs.density = density
            (knobs.row, knobs.header, knobs.bar, knobs.gutter) = preset
        }
        // Explicit sizes win over the file's own preset.
        if let row { knobs.row = row }
        if let header { knobs.header = header }
        if let bar { knobs.bar = bar }
        if let gutter { knobs.gutter = gutter }
        if let small { knobs.small = small }
        if let medium { knobs.medium = medium }
        if let large { knobs.large = large }
        if let glass { knobs.glass = glass }
    }
}

/// Reads theme files: parses one file's text into a `ThemeDefinition`, then
/// resolves definitions against each other (`extends`, palette names) into
/// `Theme`s. Problems are returned, not thrown, so a user sees them all.
public enum ThemeReader {
    /// The theme file format this app reads.
    public static let formatVersion = 1

    static let topLevelKeys = [
        "name", "version", "extends", "description", "palette",
        "any", "light", "dark", "font", "density", "shape", "material",
    ]

    // MARK: Parsing

    /// Parses one file's text. The definition is `nil` when any problem was found.
    public static func definition(_ text: String, file: String, source: ThemeSource) -> (definition: ThemeDefinition?, issues: [ThemeIssue]) {
        let root: TOMLTable
        do {
            root = try TOMLTable(source: text)
        } catch {
            let issue = ConfigurationIssue(invalidTOML: error)
            return (nil, [ThemeIssue(file: file, line: issue.line, message: issue.message)])
        }
        var parser = Parser(file: file, map: TOMLSourceMap(text))
        let definition = parser.definition(from: root, source: source)
        return parser.issues.isEmpty ? (definition, []) : (nil, parser.issues)
    }

    // MARK: Resolving

    /// Resolves every definition, with `extends` looked up among them. Of two
    /// with one name (names aren't case-sensitive), the later wins, so a user
    /// file replaces a built-in theme. A definition that fails is left out,
    /// and its problems returned.
    public static func resolve(_ definitions: [ThemeDefinition]) -> (themes: [Theme], issues: [ThemeIssue]) {
        var library: [String: ThemeDefinition] = [:]
        for definition in definitions { library[definition.name.lowercased()] = definition }
        var themes: [Theme] = []
        var issues: [ThemeIssue] = []
        var seen = Set<String>()
        for definition in definitions where seen.insert(definition.name.lowercased()).inserted {
            switch resolve(library[definition.name.lowercased()]!, library: library) {
            case .success(let theme): themes.append(theme)
            case .failure(let failure): issues.append(contentsOf: failure.issues)
            }
        }
        return (themes, issues)
    }

    /// Reads one file's text into a theme, its `extends` looked up in `library`.
    public static func theme(
        _ text: String, file: String, source: ThemeSource, library: [ThemeDefinition]
    ) -> (theme: Theme?, issues: [ThemeIssue]) {
        let (definition, issues) = definition(text, file: file, source: source)
        guard let definition else { return (nil, issues) }
        var byName: [String: ThemeDefinition] = [:]
        for other in library { byName[other.name.lowercased()] = other }
        byName[definition.name.lowercased()] = definition
        switch resolve(definition, library: byName) {
        case .success(let theme): return (theme, [])
        case .failure(let failure): return (nil, failure.issues)
        }
    }

    struct Failure: Error {
        var issues: [ThemeIssue]
    }

    static func resolve(_ definition: ThemeDefinition, library: [String: ThemeDefinition]) -> Result<Theme, Failure> {
        // The chain from the root theme down to this one.
        var chain: [ThemeDefinition] = [definition]
        while let parent = chain[0].extends {
            guard let found = library[parent.lowercased()] else {
                return .failure(Failure(issues: [extendsIssue(chain[0], "`extends` names \"\(parent)\", which isn't a theme")]))
            }
            if chain.contains(where: { $0.name.lowercased() == found.name.lowercased() }) {
                let loop = ([found] + chain).map(\.name).joined(separator: " → ")
                return .failure(Failure(issues: [extendsIssue(definition, "`extends` goes in a circle: \(loop)")]))
            }
            chain.insert(found, at: 0)
        }

        var knobs = ThemeKnobs.standard
        var palette: [ThemeAppearance: [String: ThemeValue]] = [:]
        var tokens: [ThemeAppearance: [ThemeToken: (entry: ThemeDefinition.Entry, file: String)]] = [:]
        for link in chain {
            link.knobs.apply(to: &knobs)
            for appearance in ThemeAppearance.allCases {
                // A root theme that fills one appearance draws it in both.
                let layer: ThemeDefinition.Layer = (link.single ?? appearance) == .dark ? .dark : .light
                for source in [ThemeDefinition.Layer.any, layer] {
                    palette[appearance, default: [:]].merge(link.palette[source] ?? [:]) { $1 }
                    for (token, entry) in link.tokens[source] ?? [:] {
                        tokens[appearance, default: [:]][token] = (entry, link.file)
                    }
                }
            }
        }

        var issues: [ThemeIssue] = []
        var values: [ThemeAppearance: [ThemeToken: ThemeValue]] = [:]
        for appearance in ThemeAppearance.allCases {
            for (token, written) in tokens[appearance] ?? [:] {
                let text = written.entry.text
                if text == "system" {
                    values[appearance, default: [:]][token] = .system
                } else if let color = RGBA(hex: text) {
                    values[appearance, default: [:]][token] = .color(color)
                } else if let named = palette[appearance]?[text] {
                    values[appearance, default: [:]][token] = named
                } else {
                    let found = ThemeIssue(
                        file: written.file, line: written.entry.line,
                        message: "`\(written.entry.path)` is \"\(text)\", which isn't a palette name, a color or `system`"
                    )
                    if !issues.contains(found) { issues.append(found) }
                }
            }
        }
        guard issues.isEmpty else { return .failure(Failure(issues: issues.sorted { ($0.line ?? 0) < ($1.line ?? 0) })) }

        var filled = Set<ThemeAppearance>()
        for link in chain {
            if let single = link.single {
                filled = [single]
            } else if link.extends == nil || link.fillsAny {
                filled = Set(ThemeAppearance.allCases)
            } else {
                if link.fillsLight { filled.insert(.light) }
                if link.fillsDark { filled.insert(.dark) }
            }
        }
        let theme = Theme(
            name: definition.name,
            summary: definition.summary,
            source: definition.source,
            appearances: ThemeAppearance.allCases.filter(filled.contains),
            knobs: knobs
        ) { token, appearance in
            values[appearance]?[token] ?? .system
        }
        return .success(theme)
    }

    private static func extendsIssue(_ definition: ThemeDefinition, _ message: String) -> ThemeIssue {
        ThemeIssue(file: definition.file, line: definition.extendsLine, message: message)
    }
}

// MARK: - The parser

/// One file's parse: the definition it builds and the problems found on the way.
private struct Parser {
    let file: String
    let map: TOMLSourceMap
    var issues: [ThemeIssue] = []

    init(file: String, map: TOMLSourceMap) {
        self.file = file
        self.map = map
    }

    mutating func definition(from root: TOMLTable, source: ThemeSource) -> ThemeDefinition {
        for key in root.keys where !ThemeReader.topLevelKeys.contains(key) {
            unknown(key, at: [], known: ThemeReader.topLevelKeys)
        }

        let name = string(root, "name", at: [])
        if !root.contains(key: "name") {
            fail("`name` is missing; write name = \"My theme\"", at: [])
        } else if let name, name.trimmingCharacters(in: .whitespaces).isEmpty {
            fail("`name` can't be empty", at: [.key("name")])
        }
        if let version = integer(root, "version", at: []) {
            if version != ThemeReader.formatVersion {
                fail("`version` \(version) isn't supported; this shipyard reads version \(ThemeReader.formatVersion)", at: [.key("version")])
            }
        } else if !root.contains(key: "version") {
            fail("`version` is missing; write version = \(ThemeReader.formatVersion)", at: [])
        }

        var definition = ThemeDefinition(
            file: file,
            source: source,
            name: name ?? "",
            summary: string(root, "description", at: []) ?? "",
            extends: string(root, "extends", at: [])
        )
        if root.contains(key: "extends") { definition.extendsLine = map.line(for: [.key("extends")]) }

        if let palette = table(root, "palette", at: []) {
            definition.palette[.any] = self.palette(palette, at: [.key("palette")])
        }
        for layer in ThemeDefinition.Layer.allCases {
            guard let body = table(root, layer.rawValue, at: []) else { continue }
            let path: ConfigurationPath = [.key(layer.rawValue)]
            for section in body.keys {
                let sectionPath = path + [.key(section)]
                if section == "palette" {
                    guard let palette = table(body, section, at: path) else { continue }
                    definition.palette[layer, default: [:]].merge(self.palette(palette, at: sectionPath)) { $1 }
                    continue
                }
                guard ThemeToken.sections.contains(section) else {
                    unknown(section, at: path, known: ThemeToken.sections + ["palette"])
                    continue
                }
                guard let tokens = table(body, section, at: path) else { continue }
                for key in tokens.keys {
                    let keyPath = sectionPath + [.key(key)]
                    guard let token = ThemeToken(rawValue: "\(section).\(key)") else {
                        let known = ThemeToken.allCases.filter { $0.rawValue.hasPrefix(section + ".") }.map { String($0.rawValue.dropFirst(section.count + 1)) }
                        unknown(key, at: sectionPath, known: known, noun: "token")
                        continue
                    }
                    guard let text = string(tokens, key, at: sectionPath) else { continue }
                    let value = text.trimmingCharacters(in: .whitespaces)
                    if value.hasPrefix("#"), RGBA(hex: value) == nil {
                        fail("`\(keyPath.dotted)` is \"\(value)\", which isn't a color; write #rrggbb or #rrggbbaa", at: keyPath)
                        continue
                    }
                    definition.tokens[layer, default: [:]][token] = ThemeDefinition.Entry(text: value, path: keyPath.dotted, line: map.line(for: keyPath))
                }
            }
        }
        definition.knobs = knobs(root)
        return definition
    }

    private mutating func palette(_ table: TOMLTable, at path: ConfigurationPath) -> [String: ThemeValue] {
        var out: [String: ThemeValue] = [:]
        for key in table.keys {
            guard let text = string(table, key, at: path) else { continue }
            let value = text.trimmingCharacters(in: .whitespaces)
            if value == "system" {
                out[key] = .system
            } else if let color = RGBA(hex: value) {
                out[key] = .color(color)
            } else {
                fail("`\((path + [.key(key)]).dotted)` is \"\(value)\", which isn't a color; write #rrggbb, #rrggbbaa or system", at: path + [.key(key)])
            }
        }
        return out
    }

    private mutating func knobs(_ root: TOMLTable) -> KnobChanges {
        var changes = KnobChanges()
        if let font = table(root, "font", at: []) {
            let path: ConfigurationPath = [.key("font")]
            known(font, ["family", "mono", "size"], at: path)
            changes.fontFamily = string(font, "family", at: path)
            changes.fontMono = string(font, "mono", at: path)
            changes.fontSize = number(font, "size", at: path, in: 9...20, "a size in points from 9 to 20")
        }
        if let density = table(root, "density", at: []) {
            let path: ConfigurationPath = [.key("density")]
            known(density, ["preset", "row", "header", "bar", "gutter"], at: path)
            if let preset = string(density, "preset", at: path) {
                if ThemeKnobs.densityPresets[preset] != nil {
                    changes.density = preset
                } else {
                    fail("`density.preset` must be `compact`, `regular` or `comfortable` (got \"\(preset)\")", at: path + [.key("preset")])
                }
            }
            changes.row = number(density, "row", at: path, in: 4...80, "a number of points from 4 to 80")
            changes.header = number(density, "header", at: path, in: 4...80, "a number of points from 4 to 80")
            changes.bar = number(density, "bar", at: path, in: 4...80, "a number of points from 4 to 80")
            changes.gutter = number(density, "gutter", at: path, in: 4...80, "a number of points from 4 to 80")
        }
        if let shape = table(root, "shape", at: []) {
            let path: ConfigurationPath = [.key("shape")]
            known(shape, ["small", "medium", "large"], at: path)
            changes.small = number(shape, "small", at: path, in: 0...30, "a radius from 0 to 30")
            changes.medium = number(shape, "medium", at: path, in: 0...30, "a radius from 0 to 30")
            changes.large = number(shape, "large", at: path, in: 0...30, "a radius from 0 to 30")
        }
        if let material = table(root, "material", at: []) {
            let path: ConfigurationPath = [.key("material")]
            known(material, ["style"], at: path)
            switch string(material, "style", at: path) {
            case nil: break
            case "glass": changes.glass = true
            case "flat": changes.glass = false
            case let other?: fail("`material.style` must be `flat` or `glass` (got \"\(other)\")", at: path + [.key("style")])
            }
        }
        return changes
    }

    // MARK: Values

    private mutating func string(_ table: TOMLTable, _ key: String, at path: ConfigurationPath) -> String? {
        guard table.contains(key: key) else { return nil }
        if let value = try? table.string(forKey: key) { return value }
        fail("`\((path + [.key(key)]).dotted)` must be a quoted string", at: path + [.key(key)])
        return nil
    }

    private mutating func integer(_ table: TOMLTable, _ key: String, at path: ConfigurationPath) -> Int? {
        guard table.contains(key: key) else { return nil }
        if let value = try? table.integer(forKey: key) { return Int(clamping: value) }
        fail("`\((path + [.key(key)]).dotted)` must be a whole number", at: path + [.key(key)])
        return nil
    }

    private mutating func number(_ table: TOMLTable, _ key: String, at path: ConfigurationPath, in range: ClosedRange<Double>, _ expected: String) -> Double? {
        guard table.contains(key: key) else { return nil }
        let keyPath = path + [.key(key)]
        let value = (try? table.integer(forKey: key)).map(Double.init) ?? (try? table.float(forKey: key))
        guard let value, range.contains(value) else {
            fail("`\(keyPath.dotted)` must be \(expected)", at: keyPath)
            return nil
        }
        return value
    }

    private mutating func table(_ table: TOMLTable, _ key: String, at path: ConfigurationPath) -> TOMLTable? {
        guard table.contains(key: key) else { return nil }
        if let value = try? table.table(forKey: key) { return value }
        fail("`\((path + [.key(key)]).dotted)` must be a table", at: path + [.key(key)])
        return nil
    }

    private mutating func known(_ table: TOMLTable, _ keys: [String], at path: ConfigurationPath) {
        for key in table.keys where !keys.contains(key) { unknown(key, at: path, known: keys) }
    }

    private mutating func unknown(_ key: String, at path: ConfigurationPath, known: [String], noun: String = "key") {
        let keyPath = path + [.key(key)]
        let hint = Suggestion.nearest(to: key, in: known).map { "; did you mean `\($0)`?" } ?? ""
        fail("unknown \(noun) `\(keyPath.dotted)`\(hint)", at: keyPath)
    }

    private mutating func fail(_ message: String, at path: ConfigurationPath) {
        issues.append(ThemeIssue(file: file, line: path.isEmpty ? nil : map.line(for: path), message: message))
    }
}
