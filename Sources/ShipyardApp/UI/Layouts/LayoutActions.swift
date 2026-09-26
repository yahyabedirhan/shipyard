import ShipyardCore

/// What a layout can do to the menu. `AppServices` supplies the closures.
struct LayoutActions {
    var open: (MenuRow) -> Void
    var markSeen: (MenuRow) -> Void
    /// `nil` marks every project seen.
    var markAllSeen: (MenuSection?) -> Void
    var toggleCollapsed: (MenuSection) -> Void
    /// Folds a subsection, or unfolds it (a click on its subheader, ← and →).
    var toggleGroup: (RowGroup) -> Void
    /// Shows the rest of a capped group, or caps an expanded one again (a
    /// click on its Show more or Show less row, and Return there).
    var toggleShowMore: (RowGroup) -> Void
    /// Opens the project's first repository on GitHub (Return on its header).
    var openRepository: (MenuSection) -> Void
}
