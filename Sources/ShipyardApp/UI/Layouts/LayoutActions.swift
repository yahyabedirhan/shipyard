import ShipyardCore

/// What a layout can do to the menu. `AppServices` supplies the closures.
struct LayoutActions {
    var open: (MenuRow) -> Void
    var markSeen: (MenuRow) -> Void
    /// `nil` marks every project seen.
    var markAllSeen: (MenuSection?) -> Void
    var toggleCollapsed: (MenuSection) -> Void
    /// Opens the project's first repository on GitHub (Return on its header).
    var openRepository: (MenuSection) -> Void
}
