import ShipyardCore

struct LayoutActions {
    var open: (MenuRow) -> Void
    var markSeen: (MenuRow) -> Void
    var dismiss: (MenuRow) -> Void
    var markAllSeen: (MenuSection?) -> Void
    var toggleCollapsed: (MenuSection) -> Void
    var toggleGroup: (RowGroup) -> Void
    var toggleShowMore: (RowGroup) -> Void
    var openRepository: (MenuSection) -> Void
    var openPage: (PageLink) -> Void
    var startNote: (MenuSection) -> Void
}
