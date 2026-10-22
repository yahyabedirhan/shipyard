import AppKit
import Combine
import os
import ShipyardConfig
import ShipyardCore
import SwiftUI

// The token layer: views take each colour from the theme in their
// environment, resolved for the appearance they draw in. Nothing here holds
// a global active theme, so two parts of one window can draw two themes,
// each with its own sizes and type.

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = BuiltInThemes.system
}

extension EnvironmentValues {
    /// The theme the views below draw with: Shipyard unless a view above sets
    /// one. Setting it resolves its knobs into `panelScale` once, for every
    /// view below to read.
    var theme: Theme {
        get { self[ThemeKey.self] }
        set {
            self[ThemeKey.self] = newValue
            if panelScale.knobs != newValue.knobs { panelScale = PanelScale(newValue.knobs) }
        }
    }
}

extension ThemeAppearance {
    init(_ scheme: ColorScheme) {
        self = scheme == .dark ? .dark : .light
    }
}

extension ColorScheme {
    init(_ appearance: ThemeAppearance) {
        self = appearance == .dark ? .dark : .light
    }
}

extension View {
    /// Draws the views below with `theme`. A theme that fills one appearance
    /// draws it in both: the views below get that appearance, so what the
    /// theme leaves to the system (its `system` values, text and controls
    /// with no colour of their own) draws for its surfaces too.
    func theme(_ theme: Theme) -> some View {
        modifier(ThemeScope(theme: theme))
    }
}

private struct SystemColorsGenerationKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    /// Counts the system's colour changes (a new accent, more contrast), so
    /// a `system` value draws again when it changes. The panel sets it from
    /// `SystemColorsWatch`.
    var systemColorsGeneration: Int {
        get { self[SystemColorsGenerationKey.self] }
        set { self[SystemColorsGenerationKey.self] = newValue }
    }
}

extension View {
    /// Draws the views below again when the system's colours change:
    /// `NSColor.systemColorsDidChangeNotification`, which a new accent in
    /// System Settings > Appearance posts.
    func followsSystemColors() -> some View {
        modifier(SystemColorsWatch())
    }
}

private struct SystemColorsWatch: ViewModifier {
    @State private var generation = 0

    func body(content: Content) -> some View {
        content
            .environment(\.systemColorsGeneration, generation)
            .onReceive(NotificationCenter.default.publisher(for: NSColor.systemColorsDidChangeNotification).receive(on: RunLoop.main)) { _ in
                SystemColors.forget()
                generation += 1
            }
    }
}

private struct ThemeScope: ViewModifier {
    let theme: Theme
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .environment(\.theme, theme)
            .environment(\.colorScheme, ColorScheme(theme.drawn(ThemeAppearance(scheme))))
    }
}

/// A colour of the theme in the environment, a token or a state, resolved
/// when it's drawn for the environment's appearance. A `ShapeStyle`: use it
/// where a colour goes in `foregroundStyle`, `fill`, `background`, `stroke`
/// and `overlay`.
struct ThemeColor: ShapeStyle, Hashable {
    /// What the colour is looked up by.
    enum Source: Hashable {
        case token(ThemeToken)
        /// A phase, as the theme's `[phase]` table names it.
        case phase(ThemePhase)
        /// A kind's state, as its `[states.<kind>]` table names it.
        case state(ThemeKind, String)
    }

    let source: Source
    var opacity: Double = 1

    init(_ token: ThemeToken, opacity: Double = 1) {
        self.init(.token(token), opacity: opacity)
    }

    private init(_ source: Source, opacity: Double) {
        self.source = source
        self.opacity = opacity
    }

    /// The same colour at a fraction of its alpha; `opacity(0)` draws nothing.
    func opacity(_ value: Double) -> ThemeColor { ThemeColor(source, opacity: opacity * value) }

    func resolve(in environment: EnvironmentValues) -> Color {
        // Read so a change of the system's colours draws again.
        _ = environment.systemColorsGeneration
        return color(in: environment.theme, ThemeAppearance(environment.colorScheme))
    }

    /// The colour in `theme` and `appearance`, for code with no environment.
    func color(in theme: Theme, _ appearance: ThemeAppearance) -> Color {
        let base: Color = switch source {
        case .token(.attentionFailed) where theme.value(.attention, appearance) == .system:
            // The attention dot follows the user's accent, which no theme
            // check sees: a red accent pushes failed's dot to a deeper red.
            Self.color(ThemeSignals.failed(
                theme.rgba(.attentionFailed, appearance, system: SystemColors.rgba),
                apartFrom: theme.rgba(.attention, appearance, system: SystemColors.rgba)
            ))
        case .token(let token):
            switch theme.value(token, appearance) {
            case .color(let rgba): Self.color(rgba)
            case .system: SystemColors.color(token.system(appearance), appearance)
            }
        case .phase(let phase):
            Self.color(theme.color(phase, appearance), appearance)
        case .state(let kind, let state):
            // A state the kind doesn't have draws the quiet phase.
            Self.color(theme.color(kind, state, appearance) ?? theme.color(.quiet, appearance), appearance)
        }
        return opacity == 1 ? base : base.opacity(opacity)
    }

    private static func color(_ rgba: RGBA) -> Color {
        Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
    }

    private static func color(_ value: ThemeStateColor, _ appearance: ThemeAppearance) -> Color {
        switch value {
        case .color(let rgba): color(rgba)
        case .system(let shade): SystemColors.color(shade, appearance)
        }
    }

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
    static let separator = ThemeColor(.separator)
    static let border = ThemeColor(.border)
    static let rowHover = ThemeColor(.rowHover)
    static let rowPressed = ThemeColor(.rowPressed)
    static let attention = ThemeColor(.attention)
    static let attentionFailed = ThemeColor(.attentionFailed)
    static let lease = ThemeColor(.lease)

    /// The theme's phase colours, for what isn't one kind's state but is
    /// in a phase: an error is `failed`, a diff's additions `active`, a
    /// note that asks for nothing `quiet`. A status mark, such as a
    /// caught-up tick or a connected status, is the accent, not `done`,
    /// so it never reads as a merged pull request.
    static let active = ThemeColor(.phase(.active), opacity: 1)
    static let failed = ThemeColor(.phase(.failed), opacity: 1)
    static let quiet = ThemeColor(.phase(.quiet), opacity: 1)

    /// The theme's colour for `kind` in `state`, its `[states.<kind>]` value.
    static func state(_ kind: ThemeKind, _ state: String) -> ThemeColor {
        ThemeColor(.state(kind, state), opacity: 1)
    }

    /// A row's state icon. A ping or a note has one state, `open`.
    static func state(_ state: ItemState, kind: ItemKind) -> ThemeColor {
        switch kind {
        case .ping, .note: Self.state(ThemeKind(kind), "open")
        case .pullRequest, .issue, .workflowRun: Self.state(ThemeKind(kind), state.rawValue)
        }
    }

    /// A pull request's checks on its hover card; none when it has none.
    static func checks(_ checks: ChecksState) -> ThemeColor? {
        checks == .none ? nil : state(.check, checks.rawValue)
    }

    /// A review decision, as the hover card shows it.
    static func review(_ decision: ReviewDecision) -> ThemeColor {
        let name = switch decision {
        case .approved: "approved"
        case .changesRequested: "changes-requested"
        case .reviewRequired: "review-required"
        }
        return state(.review, name)
    }

    /// The rate limit's colour at `level`.
    static func rate(_ level: RateLevel) -> ThemeColor {
        let name = switch level {
        case .normal: "normal"
        case .low: "low"
        case .exhausted: "exhausted"
        }
        return state(.rate, name)
    }

    /// The rate-limit text: the tertiary text while normal, so a limit with
    /// room doesn't draw the eye; the theme's `low` or `exhausted` colour
    /// once it runs short.
    static func rateText(_ level: RateLevel) -> ThemeColor {
        level == .normal ? textTertiary : rate(level)
    }

    /// The rate-limit bar: the theme's colour for the level, lighter while
    /// normal.
    static func rateBar(_ level: RateLevel) -> ThemeColor {
        level == .normal ? rate(level).opacity(0.65) : rate(level)
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
    private static let values = OSAllocatedUnfairLock(initialState: [Key: RGBA]())
    nonisolated(unsafe) private static let observer: any NSObjectProtocol = NotificationCenter.default.addObserver(
        forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: nil
    ) { _ in
        forget()
    }

    /// The shade as an sRGB colour, read under `appearance`, for code that
    /// works on colours' values: the theme circles, the error dot's red.
    static func rgba(_ shade: SystemShade, _ appearance: ThemeAppearance) -> RGBA {
        _ = observer
        let key = Key(shade: shade, appearance: appearance)
        if let rgba = values.withLock({ $0[key] }) { return rgba }
        let color = resolved(shade, appearance)
        let rgba = RGBA(r: color.redComponent, g: color.greenComponent, b: color.blueComponent, a: color.alphaComponent)
        values.withLock { $0[key] = rgba }
        return rgba
    }

    /// Drops the colours read so far, so the next draw reads them again.
    static func forget() {
        cache.withLock { $0.removeAll() }
        values.withLock { $0.removeAll() }
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
