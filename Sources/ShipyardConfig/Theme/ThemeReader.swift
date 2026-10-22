import Foundation
import TOMLDecoder

/// What one theme file says, before `extends` fills what it leaves out.
public struct ThemeDefinition: Sendable {
    public var file: String
    public var source: ThemeSource
    public var name: String
    public var summary: String
    public var extends: String?

    /// `both`, the tables without a prefix, sets both appearances; `light`
    /// and `dark`, the `[light.*]` and `[dark.*]` tables, override it for one.
    enum Layer: CaseIterable, Sendable {
        case both, light, dark
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
    var phases: [Layer: [ThemePhase: Entry]] = [:]
    var states: [Layer: [ThemeStateKey: Entry]] = [:]
    var knobs = KnobChanges()

    var fillsLight: Bool { fills(.light) }
    var fillsDark: Bool { fills(.dark) }
    var fillsBoth: Bool { fills(.both) }

    private func fills(_ layer: Layer) -> Bool {
        !entries(layer).isEmpty || !(palette[layer] ?? [:]).isEmpty
    }

    /// Every colour the layer writes: its tokens, phases and states.
    private func entries(_ layer: Layer) -> [Entry] {
        Array((tokens[layer] ?? [:]).values) + Array((phases[layer] ?? [:]).values) + Array((states[layer] ?? [:]).values)
    }

    /// The one appearance a theme with no `extends` fills, which it then
    /// draws in both; `nil` when it fills both or extends another. It fills
    /// one when it writes `[light.*]` or `[dark.*]` tables for that one
    /// alone, and its colours without a prefix, if any, read that
    /// appearance's own palette: Paper Light's `[surface]` and `[text]` tokens name
    /// `[light.palette]` colours, so it fills light, where tokens without a
    /// prefix and a `[dark.*]` override still set both appearances.
    var single: ThemeAppearance? {
        guard extends == nil, fillsLight != fillsDark else { return nil }
        let one: Layer = fillsLight ? .light : .dark
        let appearance: ThemeAppearance = fillsLight ? .light : .dark
        let shared = entries(.both)
        guard !shared.isEmpty else { return appearance }
        let onlyThere = Set((palette[one] ?? [:]).keys).subtracting((palette[.both] ?? [:]).keys)
        return shared.contains { onlyThere.contains($0.text) } ? appearance : nil
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

    /// The colour tables a layer writes, without a prefix or under
    /// `light` and `dark`.
    static let colourSections = ["palette"] + ThemeToken.sections + ["phase", "states"]

    static let topLevelKeys = [
        "name", "version", "extends", "description",
    ] + colourSections + [
        "light", "dark", "font", "density", "shape", "material",
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
    /// and its problems returned. `base` (the built-ins, for the user's
    /// files) is looked up by `extends` but not resolved itself.
    public static func resolve(
        _ definitions: [ThemeDefinition], extending base: [ThemeDefinition] = []
    ) -> (themes: [Theme], issues: [ThemeIssue]) {
        var library: [String: ThemeDefinition] = [:]
        for definition in base + definitions { library[definition.name.lowercased()] = definition }
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
                let names = library.values.map(\.name).sorted { $0.lowercased() < $1.lowercased() }.map { "`\($0)`" }
                return .failure(Failure(issues: [extendsIssue(
                    chain[0], "`extends` names \"\(parent)\", which isn't a theme (expected one of \(names.joined(separator: ", ")))"
                )]))
            }
            if chain.contains(where: { $0.name.lowercased() == found.name.lowercased() }) {
                let loop = ([found] + chain).map(\.name).joined(separator: " → ")
                return .failure(Failure(issues: [extendsIssue(definition, "`extends` goes in a circle: \(loop)")]))
            }
            chain.insert(found, at: 0)
        }

        var knobs = ThemeKnobs.standard
        var palette: [ThemeAppearance: [String: ThemeValue]] = [:]
        typealias Written = (entry: ThemeDefinition.Entry, file: String)
        var tokens: [ThemeAppearance: [ThemeToken: Written]] = [:]
        var phases: [ThemeAppearance: [ThemePhase: Written]] = [:]
        var states: [ThemeAppearance: [ThemeStateKey: Written]] = [:]
        for link in chain {
            link.knobs.apply(to: &knobs)
            for appearance in ThemeAppearance.allCases {
                // A root theme that fills one appearance draws it in both.
                let layer: ThemeDefinition.Layer = (link.single ?? appearance) == .dark ? .dark : .light
                for source in [ThemeDefinition.Layer.both, layer] {
                    palette[appearance, default: [:]].merge(link.palette[source] ?? [:]) { $1 }
                    for (token, entry) in link.tokens[source] ?? [:] {
                        tokens[appearance, default: [:]][token] = (entry, link.file)
                    }
                    for (phase, entry) in link.phases[source] ?? [:] {
                        phases[appearance, default: [:]][phase] = (entry, link.file)
                    }
                    for (state, entry) in link.states[source] ?? [:] {
                        states[appearance, default: [:]][state] = (entry, link.file)
                    }
                }
            }
        }

        var issues: [ThemeIssue] = []
        func problem(_ written: Written, _ message: String) {
            let found = ThemeIssue(file: written.file, line: written.entry.line, message: "`\(written.entry.path)` is \"\(written.entry.text)\", \(message)")
            if !issues.contains(found) { issues.append(found) }
        }
        // A value that is `system`, a hex colour or a palette name; `nil`
        // for any other text.
        func value(_ text: String, _ appearance: ThemeAppearance) -> ThemeValue? {
            if text == "system" { return .system }
            if let color = RGBA(hex: text) { return .color(color) }
            return palette[appearance]?[text]
        }
        func stateColor(_ value: ThemeValue, system shade: SystemShade) -> ThemeStateColor {
            switch value {
            case .system: .system(shade)
            case .color(let color): .color(color)
            }
        }

        var values: [ThemeAppearance: [ThemeToken: ThemeValue]] = [:]
        var phaseColors: [ThemeAppearance: [ThemePhase: ThemeStateColor]] = [:]
        var stateColors: [ThemeAppearance: [ThemeStateKey: ThemeStateColor]] = [:]
        for appearance in ThemeAppearance.allCases {
            for (token, written) in tokens[appearance] ?? [:] {
                if let value = value(written.entry.text, appearance) {
                    values[appearance, default: [:]][token] = value
                } else {
                    problem(written, "which isn't a palette name, a color or `system`")
                }
            }
            // A phase is a colour of its own: a phase's name is always the
            // phase, so naming one here is a problem.
            for (phase, written) in phases[appearance] ?? [:] {
                if ThemePhase(rawValue: written.entry.text) != nil {
                    problem(written, "which names a phase; a phase is a palette name, a color or `system`")
                } else if let value = value(written.entry.text, appearance) {
                    phaseColors[appearance, default: [:]][phase] = stateColor(value, system: phase.system)
                } else {
                    problem(written, "which isn't a palette name, a color or `system`")
                }
            }
            // A phase's name is always the phase, even where a palette entry
            // has that name; `system` is the macOS colour of the state's own
            // phase, or the macOS orange for a state with no phase.
            for (state, written) in states[appearance] ?? [:] {
                let text = written.entry.text
                if let phase = ThemePhase(rawValue: text) {
                    stateColors[appearance, default: [:]][state] = phaseColors[appearance]?[phase] ?? .system(phase.system)
                } else if let value = value(text, appearance) {
                    stateColors[appearance, default: [:]][state] = stateColor(value, system: state.system)
                } else {
                    problem(written, "which isn't a phase, a palette name, a color or `system`")
                }
            }
        }
        guard issues.isEmpty else { return .failure(Failure(issues: issues.sorted { ($0.line ?? 0) < ($1.line ?? 0) })) }

        // `signal.attention-failed`, when no theme in the chain sets it, is
        // the `failed` phase's colour: `system` stands for the macOS red,
        // as the phase's does.
        for appearance in ThemeAppearance.allCases where values[appearance]?[.attentionFailed] == nil {
            if case .color(let color) = phaseColors[appearance]?[.failed] {
                values[appearance, default: [:]][.attentionFailed] = .color(color)
            }
        }

        // A theme that extends another keeps the appearances its parent
        // fills, and adds the one whose `[light.*]` or `[dark.*]` tables it
        // writes: a theme that extends Shipyard Dark is dark too.
        var filled = Set<ThemeAppearance>()
        for link in chain {
            if let single = link.single {
                filled = [single]
            } else if link.extends == nil {
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
            knobs: knobs,
            phases: phaseColors,
            states: stateColors
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
            if key == "any" {
                anyPrefix(root)
            } else if key == "state" {
                // `[state]` has no tokens: reading the colour tables
                // reports each of its keys as a problem.
                continue
            } else {
                unknown(key, at: [], known: ThemeReader.topLevelKeys)
            }
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

        colours(root, sections: ThemeReader.colourSections, layer: .both, at: [], into: &definition)
        for (layer, key) in [(ThemeDefinition.Layer.light, "light"), (.dark, "dark")] {
            guard let body = table(root, key, at: []) else { continue }
            colours(body, sections: body.keys, layer: layer, at: [.key(key)], into: &definition)
        }
        definition.knobs = knobs(root)
        return definition
    }

    /// Reads one layer's colour tables, the palette, each token section,
    /// `[phase]` and `[states.*]`,
    /// from `body`: the file itself for the tables without a prefix, or its
    /// `light` or `dark` table.
    private mutating func colours(
        _ body: TOMLTable, sections: [String], layer: ThemeDefinition.Layer,
        at path: ConfigurationPath, into definition: inout ThemeDefinition
    ) {
        for section in body.keys where sections.contains(section) || section == "state" {
            let sectionPath = path + [.key(section)]
            if section == "state" {
                guard let removed = table(body, section, at: path) else { continue }
                for key in removed.keys {
                    if let moved = Self.movedStates[key] {
                        self.removed(key, moved, at: path)
                    } else {
                        fail("`\((sectionPath + [.key(key)]).dotted)` isn't a theme key; a state takes its colour from `[phase]` and `[states.<kind>]`", at: sectionPath + [.key(key)])
                    }
                }
                continue
            }
            if section == "palette" {
                guard let palette = table(body, section, at: path) else { continue }
                definition.palette[layer, default: [:]].merge(self.palette(palette, at: sectionPath)) { $1 }
                continue
            }
            if section == "phase" {
                guard let phases = table(body, section, at: path) else { continue }
                for key in phases.keys {
                    guard let phase = ThemePhase(rawValue: key) else {
                        unknown(key, at: sectionPath, known: ThemePhase.allCases.map(\.rawValue), noun: "phase")
                        continue
                    }
                    if let entry = entry(phases, key, at: sectionPath) { definition.phases[layer, default: [:]][phase] = entry }
                }
                continue
            }
            if section == "states" {
                guard let kinds = table(body, section, at: path) else { continue }
                for key in kinds.keys {
                    guard let kind = ThemeKind(rawValue: key) else {
                        unknown(key, at: sectionPath, known: ThemeKind.allCases.map(\.rawValue), noun: "kind")
                        continue
                    }
                    let kindPath = sectionPath + [.key(key)]
                    guard let states = table(kinds, key, at: sectionPath) else { continue }
                    for state in states.keys {
                        guard kind.has(state) else {
                            unknown(state, at: kindPath, known: kind.states.map(\.name), noun: "state")
                            continue
                        }
                        if let entry = entry(states, state, at: kindPath) {
                            definition.states[layer, default: [:]][ThemeStateKey(kind: kind, state: state)] = entry
                        }
                    }
                }
                continue
            }
            guard ThemeToken.sections.contains(section) else {
                unknown(section, at: path, known: ThemeReader.colourSections)
                continue
            }
            guard let tokens = table(body, section, at: path) else { continue }
            for key in tokens.keys {
                guard let token = ThemeToken(rawValue: "\(section).\(key)") else {
                    let known = ThemeToken.allCases.filter { $0.rawValue.hasPrefix(section + ".") }.map { String($0.rawValue.dropFirst(section.count + 1)) }
                    unknown(key, at: sectionPath, known: known, noun: "token")
                    continue
                }
                if let entry = entry(tokens, key, at: sectionPath) { definition.tokens[layer, default: [:]][token] = entry }
            }
        }
    }

    /// Where a removed `[state]` token went: the phase it was, and the
    /// `[states.*]` keys that set what it coloured, per kind.
    private typealias Moved = (phase: ThemePhase, keys: [(kind: ThemeKind, state: String)])

    /// The removed `state.*` tokens, which `[phase]` and `[states.*]` set
    /// instead. A token that coloured a state with no phase, as `pending`
    /// coloured the rate limit's `low`, names that state's key too.
    private static let movedStates: [String: Moved] = [
        "open": (.active, [(.pullRequest, "open"), (.issue, "open")]),
        "draft": (.quiet, [(.pullRequest, "draft")]),
        "merged": (.done, [(.pullRequest, "merged"), (.issue, "closed"), (.run, "succeeded")]),
        "closed": (.failed, [(.pullRequest, "closed"), (.run, "failed")]),
        "running": (.active, [(.run, "running")]),
        "success": (.done, [(.check, "passed"), (.review, "approved")]),
        "failure": (.failed, [(.check, "failed"), (.review, "changes-requested"), (.rate, "exhausted")]),
        "pending": (.active, [(.check, "pending"), (.review, "review-required"), (.rate, "low")]),
        "neutral": (.quiet, [(.ping, "open"), (.note, "open")]),
    ]

    /// A removed `state.*` token is an error on its line that names the
    /// keys that replace it, in the same layer.
    private mutating func removed(_ key: String, _ moved: Moved, at path: ConfigurationPath) {
        let keyPath = path + [.key("state"), .key(key)]
        let prefix = path.isEmpty ? "" : "\(path.dotted)."
        func written(_ key: (kind: ThemeKind, state: String)) -> String { "`[\(prefix)states.\(key.kind.rawValue)] \(key.state)`" }
        func list(_ keys: [String]) -> String {
            keys.count == 1 ? keys[0] : keys.dropLast().joined(separator: ", ") + " and " + keys.last!
        }
        // A state in no phase, such as the rate limit's `low`, isn't set by
        // the phase: it is named apart.
        let inPhase = moved.keys.filter { $0.kind.phase(of: $0.state) != nil }.map(written)
        let apart = moved.keys.filter { $0.kind.phase(of: $0.state) == nil }.map(written)
        let warning = apart.isEmpty ? "" : "; \(list(apart)) is in no phase, so write it too"
        fail("`\(keyPath.dotted)` was removed; write `[\(prefix)phase] \(moved.phase.rawValue)` for every \(moved.phase.rawValue) state, or \(list(inPhase))\(warning)", at: keyPath)
    }

    /// A colour as written: a quoted string, with a hex colour checked here
    /// and a name looked up once `extends` is known.
    private mutating func entry(_ table: TOMLTable, _ key: String, at path: ConfigurationPath) -> ThemeDefinition.Entry? {
        let keyPath = path + [.key(key)]
        guard let text = string(table, key, at: path) else { return nil }
        let value = text.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#"), RGBA(hex: value) == nil {
            fail("`\(keyPath.dotted)` is \"\(value)\", which isn't a color; write #rrggbb or #rrggbbaa", at: keyPath)
            return nil
        }
        return ThemeDefinition.Entry(text: value, path: keyPath.dotted, line: map.line(for: keyPath))
    }

    /// An `[any.<table>]` is an error on its own line that tells the author
    /// to remove the prefix: a table without one sets both appearances.
    private mutating func anyPrefix(_ root: TOMLTable) {
        let path: ConfigurationPath = [.key("any")]
        guard let body = try? root.table(forKey: "any"), !body.keys.isEmpty else {
            fail("`any` isn't a theme key; remove the `any.` prefix: a table without a prefix, such as `[text]`, sets light and dark", at: path)
            return
        }
        for section in body.keys {
            fail("`[any.\(section)]` has an `any.` prefix; remove it and write `[\(section)]`, which sets light and dark", at: path + [.key(section)])
        }
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
