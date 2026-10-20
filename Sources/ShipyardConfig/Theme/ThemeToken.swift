import Foundation

/// Light or dark: the two appearances a theme fills.
public enum ThemeAppearance: String, CaseIterable, Hashable, Sendable {
    case light, dark
}

/// A colour of a theme, named by what it means, never by hue. `rawValue` is
/// `section.name`, the path a theme file writes it under: `[any.surface]`
/// `panel = "..."` sets `surface.panel`.
public enum ThemeToken: String, CaseIterable, Hashable, Sendable {
    case window = "surface.window"
    case panel = "surface.panel"
    case header = "surface.header"
    case chrome = "surface.chrome"
    case raised = "surface.raised"
    case field = "surface.field"
    case track = "surface.track"
    case textPrimary = "text.primary"
    case textSecondary = "text.secondary"
    case textTertiary = "text.tertiary"
    case textSeen = "text.seen"
    case textOnAccent = "text.on-accent"
    case accent = "accent.accent"
    case accentSoft = "accent.soft"
    case separator = "line.separator"
    case border = "line.border"
    case rowHover = "row.hover"
    case rowPressed = "row.pressed"
    case rowSelected = "row.selected"
    case open = "state.open"
    case draft = "state.draft"
    case merged = "state.merged"
    case closed = "state.closed"
    case success = "state.success"
    case failure = "state.failure"
    case pending = "state.pending"
    case running = "state.running"
    case neutral = "state.neutral"
    case attention = "signal.attention"
    case lease = "signal.lease"

    /// The sections a theme file's `[any.*]`, `[light.*]` and `[dark.*]` tables hold.
    public static let sections = ["surface", "text", "accent", "line", "row", "state", "signal"]

    /// The token's place in `allCases`: its index in a theme's table of values.
    var index: Int { Self.indices[self]! }
    private static let indices = Dictionary(uniqueKeysWithValues: allCases.enumerated().map { ($1, $0) })

    /// What `system` means for this token in `appearance`: the macOS semantic
    /// colour it stands for, at a strength. The text tiers are the label
    /// colour at a strength that stays readable on the panel. The app draws
    /// the live system colour, so it follows the user's accent.
    public func system(_ appearance: ThemeAppearance) -> SystemShade {
        switch self {
        case .window, .panel, .header: SystemShade(.windowBackground)
        case .chrome: SystemShade(.label, alpha: 0.035)
        case .raised: appearance == .dark ? SystemShade(.white, alpha: 0.16) : SystemShade(.white)
        case .field, .track, .rowHover: SystemShade(.quaternaryFill)
        case .textPrimary: SystemShade(.label)
        case .textSecondary: SystemShade(.label, alpha: 0.70)
        case .textTertiary: SystemShade(.label, alpha: 0.55)
        case .textSeen: SystemShade(.label, alpha: 0.72)
        case .textOnAccent: SystemShade(.white)
        case .accent, .attention: SystemShade(.accent)
        case .accentSoft: SystemShade(.accent, alpha: 0.15)
        case .separator, .border: SystemShade(.separator)
        case .rowPressed: SystemShade(.tertiaryFill)
        case .rowSelected: SystemShade(.accent, alpha: 0.2)
        case .open, .success: SystemShade(.green)
        case .draft, .neutral: SystemShade(.secondaryLabel)
        case .merged: SystemShade(.purple)
        case .closed, .failure: SystemShade(.red)
        case .pending, .running: SystemShade(.orange)
        case .lease: SystemShade(.yellow)
        }
    }
}

/// The macOS semantic colours a theme's `system` value stands for.
public enum SystemColor: Hashable, Sendable {
    case windowBackground, label, secondaryLabel, separator, quaternaryFill, tertiaryFill
    case accent, green, purple, red, orange, yellow, white
}

/// A system colour at a strength: `alpha` multiplies the colour's own alpha.
public struct SystemShade: Hashable, Sendable {
    public var color: SystemColor
    public var alpha: Double

    public init(_ color: SystemColor, alpha: Double = 1) {
        self.color = color
        self.alpha = alpha
    }
}

/// An sRGB colour with alpha, each component from 0 to 1.
public struct RGBA: Hashable, Sendable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `#rrggbb` or `#rrggbbaa`; `nil` when it's neither.
    public init?(hex: String) {
        guard hex.hasPrefix("#") else { return nil }
        let digits = hex.dropFirst()
        guard digits.count == 6 || digits.count == 8,
              digits.allSatisfy(\.isHexDigit),
              let value = UInt64(digits, radix: 16)
        else { return nil }
        let rgb = digits.count == 6 ? value : value >> 8
        self.init(
            r: Double((rgb >> 16) & 0xFF) / 255,
            g: Double((rgb >> 8) & 0xFF) / 255,
            b: Double(rgb & 0xFF) / 255,
            a: digits.count == 6 ? 1 : Double(value & 0xFF) / 255
        )
    }

    public func withAlpha(_ alpha: Double) -> RGBA { RGBA(r: r, g: g, b: b, a: a * alpha) }
}

/// One token's value in one appearance: a colour, or the system's own colour
/// for the token (`ThemeToken.system`).
public enum ThemeValue: Hashable, Sendable {
    case system
    case color(RGBA)
}
