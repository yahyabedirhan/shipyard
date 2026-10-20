import AppKit
import os
import ShipyardConfig
import ShipyardCore
import SwiftUI

// The token layer: views take each colour from the theme in their
// environment, resolved for the appearance they draw in. Nothing here holds
// a global active theme, so two parts of one window can draw two themes.

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = BuiltInThemes.shipyard
}

extension EnvironmentValues {
    /// The theme the views below draw with: Shipyard unless a view above sets one.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension ThemeAppearance {
    init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

/// A token of the theme in the environment, resolved when it's drawn for the
/// environment's appearance. A `ShapeStyle`: use it where a colour goes in
/// `foregroundStyle`, `fill`, `background`, `stroke` and `overlay`.
struct ThemeColor: ShapeStyle, Hashable {
    let token: ThemeToken
    var opacity: Double = 1

    init(_ token: ThemeToken, opacity: Double = 1) {
        self.token = token
        self.opacity = opacity
    }

    /// The same token at a fraction of its alpha; `opacity(0)` draws nothing.
    func opacity(_ value: Double) -> ThemeColor { ThemeColor(token, opacity: opacity * value) }

    func resolve(in environment: EnvironmentValues) -> Color {
        color(in: environment.theme, ThemeAppearance(environment.colorScheme))
    }

    /// The colour in `theme` and `appearance`, for code with no environment.
    func color(in theme: Theme, _ appearance: ThemeAppearance) -> Color {
        let base = switch theme.value(token, appearance) {
        case .color(let rgba): Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
        case .system: SystemColors.color(token.system(appearance), appearance)
        }
        return opacity == 1 ? base : base.opacity(opacity)
    }

    static let window = ThemeColor(.window)
    static let panel = ThemeColor(.panel)
    static let header = ThemeColor(.header)
    static let chrome = ThemeColor(.chrome)
    static let raised = ThemeColor(.raised)
    static let field = ThemeColor(.field)
    static let track = ThemeColor(.track)
    static let textPrimary = ThemeColor(.textPrimary)
    static let textSecondary = ThemeColor(.textSecondary)
    static let textTertiary = ThemeColor(.textTertiary)
    static let textSeen = ThemeColor(.textSeen)
    static let textOnAccent = ThemeColor(.textOnAccent)
    static let accent = ThemeColor(.accent)
    static let accentSoft = ThemeColor(.accentSoft)
    static let separator = ThemeColor(.separator)
    static let border = ThemeColor(.border)
    static let rowHover = ThemeColor(.rowHover)
    static let rowPressed = ThemeColor(.rowPressed)
    static let rowSelected = ThemeColor(.rowSelected)
    static let success = ThemeColor(.success)
    static let failure = ThemeColor(.failure)
    static let pending = ThemeColor(.pending)
    static let neutral = ThemeColor(.neutral)
    static let attention = ThemeColor(.attention)
    static let lease = ThemeColor(.lease)

    /// The rate-limit text: the tertiary text while normal, then pending, then failure.
    static func rate(_ level: RateLevel) -> ThemeColor {
        switch level {
        case .normal: textTertiary
        case .low: pending
        case .exhausted: failure
        }
    }

    /// The rate-limit bar.
    static func rateBar(_ level: RateLevel) -> ThemeColor {
        switch level {
        case .normal: success.opacity(0.65)
        case .low: pending
        case .exhausted: failure
        }
    }
}

/// What a `system` value draws: the live macOS colour for an appearance,
/// read once and kept until the system's colours change (a new accent, more
/// contrast), so drawing a row doesn't ask AppKit again.
enum SystemColors {
    private struct Key: Hashable {
        let shade: SystemShade
        let appearance: ThemeAppearance
    }

    private static let cache = OSAllocatedUnfairLock(initialState: [Key: Color]())
    nonisolated(unsafe) private static let observer: any NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: nil
    ) { _ in
        cache.withLock { $0.removeAll() }
    }

    static func color(_ shade: SystemShade, _ appearance: ThemeAppearance) -> Color {
        _ = observer
        let key = Key(shade: shade, appearance: appearance)
        if let color = cache.withLock({ $0[key] }) { return color }
        let color = Color(nsColor: resolved(shade, appearance))
        cache.withLock { $0[key] = color }
        return color
    }

    /// The shade as a fixed sRGB colour, read under `appearance`.
    private static func resolved(_ shade: SystemShade, _ appearance: ThemeAppearance) -> NSColor {
        var out = NSColor.clear
        let named = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        named.performAsCurrentDrawingAppearance {
            let base = nsColor(shade.color)
            let fixed = base.usingColorSpace(.sRGB) ?? base
            out = fixed.withAlphaComponent(fixed.alphaComponent * shade.alpha)
        }
        return out
    }

    private static func nsColor(_ color: SystemColor) -> NSColor {
        switch color {
        case .windowBackground: .windowBackgroundColor
        case .label: .labelColor
        case .secondaryLabel: .secondaryLabelColor
        case .separator: .separatorColor
        case .quaternaryFill: .quaternarySystemFill
        case .tertiaryFill: .tertiarySystemFill
        case .accent: .controlAccentColor
        case .green: .systemGreen
        case .purple: .systemPurple
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .white: .white
        }
    }
}

/// The panel's surface, by the theme's material: `glass` is the system's
/// popover material under a veil of `surface.panel`, so it reads the same over
/// any desktop; `flat` is `surface.panel` alone. One view under the whole
/// panel: rows, tabs and banners draw no material of their own.
struct PanelBackdrop: View {
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if theme.knobs.glass {
            ZStack {
                PanelMaterial(dark: scheme == .dark)
                Rectangle().fill(ThemeColor.panel.opacity(0.62))
            }
        } else {
            Rectangle().fill(ThemeColor.panel)
        }
    }
}

/// The system's popover material, blurring what's behind the window, as a
/// menu bar popover does.
private struct PanelMaterial: NSViewRepresentable {
    var dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}
