import Foundation

/// The contrast check: each text tier of a theme must stand out enough on
/// `surface.panel` to read, in each appearance the theme draws. A shortfall
/// is a warning, not a failure: the theme still draws.
public enum ThemeContrast {
    /// The text tokens checked and the ratio each needs, after WCAG: body
    /// text 4.5:1, the tertiary tier (timestamps, hints) 3:1.
    public static let requirements: [(token: ThemeToken, minimum: Double)] = [
        (.textPrimary, 4.5),
        (.textSecondary, 4.5),
        (.textSeen, 4.5),
        (.textTertiary, 3),
    ]

    /// One text token with too little contrast on the panel.
    public struct Shortfall: Hashable, Sendable, CustomStringConvertible {
        public var appearance: ThemeAppearance
        public var token: ThemeToken
        public var ratio: Double
        public var minimum: Double

        /// "light `text.tertiary` is 2.9:1 on `surface.panel`; it needs 3:1".
        public var description: String {
            "\(appearance.rawValue) `\(token.rawValue)` is \(Self.ratio(ratio)) on `\(ThemeToken.panel.rawValue)`; it needs \(Self.ratio(minimum))"
        }

        private static func ratio(_ value: Double) -> String {
            // Rounded down, so a ratio just under the minimum never prints as it.
            let tenths = (value * 10).rounded(.down) / 10
            return (tenths == tenths.rounded() ? String(Int(tenths)) : String(format: "%.1f", tenths)) + ":1"
        }
    }

    /// Each text token of `theme` short of its minimum, in each appearance
    /// the theme fills; a theme that fills one draws it in both, so that one
    /// covers both. `system` values are `system`'s colours: by default the
    /// reference values, so the check runs without AppKit; the app's own
    /// test passes the live ones.
    public static func shortfalls(
        _ theme: Theme,
        system: (SystemShade, ThemeAppearance) -> RGBA = { $0.reference($1) }
    ) -> [Shortfall] {
        var found: [Shortfall] = []
        for appearance in theme.appearances {
            let base = appearance == .dark ? RGBA(r: 0, g: 0, b: 0) : RGBA(r: 1, g: 1, b: 1)
            let panel = theme.rgba(.panel, appearance, system: system).over(base)
            for (token, minimum) in requirements {
                let ratio = theme.rgba(token, appearance, system: system).over(panel).contrast(with: panel)
                if ratio < minimum {
                    found.append(Shortfall(appearance: appearance, token: token, ratio: ratio, minimum: minimum))
                }
            }
        }
        return found
    }
}

/// The attention check: the attention dot's two colours, `signal.attention`
/// for a new or changed row and `signal.attention-failed` while a pull
/// request's checks fail, must stand apart enough to tell which is which.
/// Too close is a warning, not a failure.
public enum ThemeSignals {
    /// The CIE76 colour difference the two need, at least.
    public static let minimumDistance: Double = 25

    /// The two signal colours too close in one appearance.
    public struct Clash: Hashable, Sendable, CustomStringConvertible {
        public var appearance: ThemeAppearance
        public var distance: Double

        /// "dark `signal.attention` and `signal.attention-failed` are ΔE 12 apart; they need 25".
        public var description: String {
            "\(appearance.rawValue) `\(ThemeToken.attention.rawValue)` and `\(ThemeToken.attentionFailed.rawValue)` are ΔE \(Int(distance.rounded(.down))) apart; they need \(Int(ThemeSignals.minimumDistance))"
        }
    }

    /// Each appearance the theme fills where its two signal colours are
    /// closer than `minimumDistance`, laid over its panel. `system` values
    /// are `system`'s colours, by default the reference values.
    public static func clashes(
        _ theme: Theme,
        system: (SystemShade, ThemeAppearance) -> RGBA = { $0.reference($1) }
    ) -> [Clash] {
        theme.appearances.compactMap { appearance in
            let base = appearance == .dark ? RGBA(r: 0, g: 0, b: 0) : RGBA(r: 1, g: 1, b: 1)
            let panel = theme.rgba(.panel, appearance, system: system).over(base)
            let attention = theme.rgba(.attention, appearance, system: system).over(panel)
            let failed = theme.rgba(.attentionFailed, appearance, system: system).over(panel)
            let distance = attention.distance(to: failed)
            return distance < minimumDistance ? Clash(appearance: appearance, distance: distance) : nil
        }
    }

    /// The deeper red the error dot takes when the accent it follows is
    /// the macOS accent and the user picked a red one, close to `failed`.
    public static let deeperRed = RGBA(hex: "#8E1622")!

    /// `failed`, or `deeperRed` when it is closer to `attention` than
    /// `minimumDistance`: what the error dot draws while the accent follows
    /// the user's choice, which no theme check can see.
    public static func failed(_ failed: RGBA, apartFrom attention: RGBA) -> RGBA {
        failed.distance(to: attention) < minimumDistance ? deeperRed : failed
    }
}

extension Theme {
    /// The appearance the theme draws in while the system is in
    /// `appearance`: that one when the theme fills it, else the one it fills.
    public func drawn(_ appearance: ThemeAppearance) -> ThemeAppearance {
        appearances.contains(appearance) ? appearance : appearances.first ?? appearance
    }

    /// The token's colour in `appearance`, with `system` values from `system`.
    public func rgba(
        _ token: ThemeToken, _ appearance: ThemeAppearance,
        system: (SystemShade, ThemeAppearance) -> RGBA = { $0.reference($1) }
    ) -> RGBA {
        switch value(token, appearance) {
        case .color(let color): color
        case .system: system(token.system(appearance), appearance)
        }
    }
}

extension SystemShade {
    /// The shade with its colour's reference value (`SystemColor.reference`).
    public func reference(_ appearance: ThemeAppearance) -> RGBA {
        color.reference(appearance).withAlpha(alpha)
    }
}

extension SystemColor {
    /// The colour as macOS 26 draws it with the default accent, in sRGB,
    /// for code with no AppKit: the contrast check in `shipyard config
    /// check`. The app draws the live colour, which follows the user's
    /// accent and the system's version; its tests check the built-in
    /// themes against the live colours too.
    public func reference(_ appearance: ThemeAppearance) -> RGBA {
        let dark = appearance == .dark
        return switch self {
        case .windowBackground: dark ? RGBA(r: 0.1176, g: 0.1176, b: 0.1176) : RGBA(r: 1, g: 1, b: 1)
        case .label: dark ? RGBA(r: 1, g: 1, b: 1, a: 0.8471) : RGBA(r: 0, g: 0, b: 0, a: 0.8471)
        case .secondaryLabel: dark ? RGBA(r: 1, g: 1, b: 1, a: 0.5490) : RGBA(r: 0, g: 0, b: 0, a: 0.4980)
        case .separator: dark ? RGBA(r: 1, g: 1, b: 1, a: 0.0980) : RGBA(r: 0, g: 0, b: 0, a: 0.0980)
        case .quaternaryFill: dark ? RGBA(r: 1, g: 1, b: 1, a: 0.0275) : RGBA(r: 0, g: 0, b: 0, a: 0.0275)
        case .tertiaryFill: dark ? RGBA(r: 1, g: 1, b: 1, a: 0.0471) : RGBA(r: 0, g: 0, b: 0, a: 0.0471)
        case .accent: RGBA(r: 0, g: 0.4784, b: 1)
        case .green: dark ? RGBA(r: 0.1882, g: 0.8196, b: 0.3451) : RGBA(r: 0.2039, g: 0.7804, b: 0.3490)
        case .purple: dark ? RGBA(r: 0.8588, g: 0.2039, b: 0.9490) : RGBA(r: 0.7961, g: 0.1882, b: 0.8784)
        case .red: dark ? RGBA(r: 1, g: 0.2588, b: 0.2706) : RGBA(r: 1, g: 0.2196, b: 0.2353)
        case .orange: dark ? RGBA(r: 1, g: 0.5725, b: 0.1882) : RGBA(r: 1, g: 0.5529, b: 0.1569)
        case .yellow: dark ? RGBA(r: 1, g: 0.8392, b: 0) : RGBA(r: 1, g: 0.8, b: 0)
        case .white: RGBA(r: 1, g: 1, b: 1)
        }
    }
}

extension RGBA {
    /// The colour laid over `base` (taken as opaque): opaque itself.
    public func over(_ base: RGBA) -> RGBA {
        RGBA(r: r * a + base.r * (1 - a), g: g * a + base.g * (1 - a), b: b * a + base.b * (1 - a))
    }

    /// The WCAG relative luminance, of the colour as opaque.
    var luminance: Double {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// The CIE76 colour difference of two colours, taken as opaque: the
    /// distance between them in CIE L*a*b* under D65.
    public func distance(to other: RGBA) -> Double {
        let (a, b) = (lab, other.lab)
        return ((a.l - b.l) * (a.l - b.l) + (a.a - b.a) * (a.a - b.a) + (a.b - b.b) * (a.b - b.b)).squareRoot()
    }

    /// The colour in CIE L*a*b*, under D65.
    private var lab: (l: Double, a: Double, b: Double) {
        func linear(_ value: Double) -> Double {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let (lr, lg, lb) = (linear(r), linear(g), linear(b))
        let x = (0.4124 * lr + 0.3576 * lg + 0.1805 * lb) / 0.95047
        let y = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb
        let z = (0.0193 * lr + 0.1192 * lg + 0.9505 * lb) / 1.08883
        func f(_ t: Double) -> Double {
            t > 216.0 / 24389 ? cbrt(t) : (24389.0 / 27 * t + 16) / 116
        }
        let (fx, fy, fz) = (f(x), f(y), f(z))
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    /// The WCAG contrast ratio of two opaque colours, from 1 to 21.
    func contrast(with other: RGBA) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
