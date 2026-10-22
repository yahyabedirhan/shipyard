import Foundation

/// A theme's two colours in the gear menu's Theme submenu: its panel and its
/// accent, which its circle draws side by side.
public struct ThemeSwatch: Hashable, Sendable {
    public var panel: RGBA
    public var accent: RGBA

    public init(panel: RGBA, accent: RGBA) {
        self.panel = panel
        self.accent = accent
    }
}

extension Theme {
    /// The theme's swatch while the system is in `appearance`: the panel and
    /// the accent of the appearance it draws in, each opaque, the accent
    /// laid over the panel. A theme of one appearance shows that one in
    /// both; System follows `appearance`. `system` values are `system`'s
    /// colours: the reference values by default, the live ones in the app.
    public func swatch(
        _ appearance: ThemeAppearance,
        system: (SystemShade, ThemeAppearance) -> RGBA = { $0.reference($1) }
    ) -> ThemeSwatch {
        let drawn = drawn(appearance)
        let base = drawn == .dark ? RGBA(r: 0, g: 0, b: 0) : RGBA(r: 1, g: 1, b: 1)
        let panel = rgba(.panel, drawn, system: system).over(base)
        return ThemeSwatch(panel: panel, accent: rgba(.accent, drawn, system: system).over(panel))
    }
}
