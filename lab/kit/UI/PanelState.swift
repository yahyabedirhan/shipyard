import Observation

/// Copied from `Sources/ShipyardApp/Control/PanelState.swift`, trimmed to
/// the tabs layout's selected tab: the lab has no app control, no status
/// views and no menu bar window to open or close.
@MainActor
@Observable
final class PanelState {
    /// The tabs layout's selected tab.
    private(set) var selectedTab: MenuTab = .all
    /// Whether the latest tab change moved right in `tabs`, so the list
    /// slides that way.
    private(set) var movedForward = true

    init(selectedTab: MenuTab = .all) {
        self.selectedTab = selectedTab
    }

    /// Selects `next`, recording which way it moved from the tab shown
    /// (`shown`) among `tabs`.
    func select(_ next: MenuTab, from shown: MenuTab, in tabs: [MenuTab]) {
        movedForward = (tabs.firstIndex(of: next) ?? 0) >= (tabs.firstIndex(of: shown) ?? 0)
        selectedTab = next
    }
}
