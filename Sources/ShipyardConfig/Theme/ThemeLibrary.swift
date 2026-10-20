import Foundation

/// The themes `theme = "<name>"` in `config.toml` can pick, looked up by
/// name, ignoring case. The built-in themes now; the user's theme files
/// join them as more themes, a later one replacing an earlier one with its
/// name.
public struct ThemeLibrary: Sendable {
    /// Every theme, in the order they're listed; names are unique.
    public let themes: [Theme]

    public init(_ themes: [Theme]) {
        var seen: [String: Int] = [:]
        var unique: [Theme] = []
        for theme in themes {
            if let index = seen[theme.name.lowercased()] {
                unique[index] = theme
            } else {
                seen[theme.name.lowercased()] = unique.count
                unique.append(theme)
            }
        }
        self.themes = unique
    }

    /// The six themes embedded in the app.
    public static let builtIn = ThemeLibrary(BuiltInThemes.themes)

    /// The theme a missing `theme` key picks.
    public static let defaultName = "Shipyard"

    /// The theme called `name`, ignoring case; `nil` when there's none.
    public func theme(named name: String) -> Theme? {
        themes.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// The theme a configuration's `theme` names; Shipyard when none has
    /// that name any more.
    public func theme(for configuration: Configuration) -> Theme {
        theme(named: configuration.theme) ?? theme(named: Self.defaultName) ?? BuiltInThemes.shipyard
    }

    /// Every theme's name, for a problem's hint.
    public var names: [String] { themes.map(\.name) }
}
