import Foundation
import ShipyardConfig

/// The gear menu's Theme submenu: the built-in themes in their order, then
/// the user's theme files' themes after a separator, the current one
/// checked. A theme file named after a built-in theme replaces it in place.
public struct ThemeMenu: Equatable, Sendable {
    public struct Entry: Equatable, Sendable, Identifiable {
        public var theme: Theme
        /// Whether the panel draws this theme now.
        public var isCurrent: Bool
        public var id: String { theme.name }
    }

    /// The built-in themes, or the files that replace them.
    public var builtIn: [Entry]
    /// The themes of the user's theme files, by file name.
    public var files: [Entry]

    public init(builtIn: [Entry] = [], files: [Entry] = []) {
        self.builtIn = builtIn
        self.files = files
    }

    /// The submenu for the themes `library` holds, `current` checked.
    public init(_ library: ThemeLibrary, current: Theme) {
        let builtInNames = Set(BuiltInThemes.themes.map { $0.name.lowercased() })
        let entries = library.themes.map { Entry(theme: $0, isCurrent: $0.name.caseInsensitiveCompare(current.name) == .orderedSame) }
        builtIn = entries.filter { builtInNames.contains($0.theme.name.lowercased()) }
        files = entries.filter { !builtInNames.contains($0.theme.name.lowercased()) }
    }
}
