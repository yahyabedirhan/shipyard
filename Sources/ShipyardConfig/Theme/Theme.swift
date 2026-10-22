import Foundation
import ShipyardCommand

/// The knobs both appearances of a theme share: font, density, shape and
/// material. The defaults are the Shipyard theme's.
public struct ThemeKnobs: Hashable, Sendable {
    /// `system`, `rounded`, `mono` or a font's name.
    public var fontFamily = "system"
    /// `system` or a font's name, for code.
    public var fontMono = "system"
    /// The body size in points; every other size derives from it.
    public var fontSize: Double = 12
    /// `compact`, `regular` or `comfortable`: the preset the sizes below start from.
    public var density = "regular"
    /// A list or tab row.
    public var row: Double = 24
    /// A project's header.
    public var header: Double = 26
    /// The panel's title bar.
    public var bar: Double = 38
    /// The panel's side padding.
    public var gutter: Double = 12
    /// Corner radii: small controls, cards and banners, the panel.
    public var small: Double = 6
    public var medium: Double = 8
    public var large: Double = 10
    /// `true` draws the panel on the system's material under a veil of
    /// `surface.panel`; `false` paints it with `surface.panel` alone.
    public var glass = true

    public init() {}

    public static let standard = ThemeKnobs()

    /// Each density preset's row, header, bar and gutter, in points.
    static let densityPresets: [String: (row: Double, header: Double, bar: Double, gutter: Double)] = [
        "compact": (22, 24, 34, 10),
        "regular": (24, 26, 38, 12),
        "comfortable": (28, 30, 42, 14),
    ]
}

/// Where a theme came from.
public enum ThemeSource: Hashable, Sendable {
    /// Embedded in the app.
    case builtIn
    /// A theme file at this path.
    case file(URL)
}

/// A theme ready to draw with: every token, phase and state colour resolved
/// for both appearances.
public struct Theme: Identifiable, Hashable, Sendable {
    public var id: String { name }
    /// The name `config.toml` picks the theme by.
    public let name: String
    /// The file's `description`: one line about the theme.
    public let summary: String
    public let source: ThemeSource
    /// The appearances the theme fills itself. A theme that fills only one
    /// draws it in both.
    public let appearances: [ThemeAppearance]
    public let knobs: ThemeKnobs
    private let light: [ThemeValue]
    private let dark: [ThemeValue]
    private let phases: [ThemeAppearance: [ThemePhase: ThemeStateColor]]
    private let states: [ThemeAppearance: [ThemeStateKey: ThemeStateColor]]

    public init(
        name: String,
        summary: String = "",
        source: ThemeSource = .builtIn,
        appearances: [ThemeAppearance] = ThemeAppearance.allCases,
        knobs: ThemeKnobs = .standard,
        value: (ThemeToken, ThemeAppearance) -> ThemeValue
    ) {
        self.init(name: name, summary: summary, source: source, appearances: appearances, knobs: knobs, phases: [:], states: [:], value: value)
    }

    /// A theme with its phase and state colours; one left out takes its
    /// default: a state its phase (a state with no phase the macOS orange),
    /// a phase its macOS colour.
    init(
        name: String,
        summary: String,
        source: ThemeSource,
        appearances: [ThemeAppearance],
        knobs: ThemeKnobs,
        phases: [ThemeAppearance: [ThemePhase: ThemeStateColor]],
        states: [ThemeAppearance: [ThemeStateKey: ThemeStateColor]],
        value: (ThemeToken, ThemeAppearance) -> ThemeValue
    ) {
        self.name = name
        self.summary = summary
        self.source = source
        self.appearances = appearances
        self.knobs = knobs
        light = ThemeToken.allCases.map { value($0, .light) }
        dark = ThemeToken.allCases.map { value($0, .dark) }
        self.phases = phases
        self.states = states
    }

    /// The token's value in `appearance`.
    public func value(_ token: ThemeToken, _ appearance: ThemeAppearance) -> ThemeValue {
        (appearance == .dark ? dark : light)[token.index]
    }

    /// The phase's colour in `appearance`.
    public func color(_ phase: ThemePhase, _ appearance: ThemeAppearance) -> ThemeStateColor {
        phases[appearance]?[phase] ?? .system(phase.system)
    }

    /// The colour of `kind` in `state`, in `appearance`: the one lookup the
    /// app colours a state with. `nil` when the kind has no such state.
    public func color(_ kind: ThemeKind, _ state: String, _ appearance: ThemeAppearance) -> ThemeStateColor? {
        guard kind.has(state) else { return nil }
        if let set = states[appearance]?[ThemeStateKey(kind: kind, state: state)] { return set }
        return kind.phase(of: state).map { color($0, appearance) } ?? .system(ThemeKind.warning)
    }
}

/// A problem in a theme file: the file's name, the 1-based line when it can
/// be placed, and what's wrong.
public struct ThemeIssue: Hashable, Sendable, CustomStringConvertible {
    /// The file's name, such as `Harbor.toml`.
    public var file: String
    public var line: Int?
    public var message: String

    public init(file: String, line: Int?, message: String) {
        self.file = file
        self.line = line
        self.message = message
    }

    /// "Harbor.toml line 12: …", in the form of the configuration banner.
    public var description: String {
        ConfigurationCheck.banner(ConfigurationCheck.Issue(line: line, message: message), in: file)
    }
}
