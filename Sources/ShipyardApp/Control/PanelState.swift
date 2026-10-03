import Observation
import ShipyardCore

/// The panel's own state, which the app owns rather than a view, so a
/// click in the panel and the `shipyard panel` command change the same
/// value: whether the panel is on screen, and the tabs layout's selected
/// tab. The tab is kept across the panel's closing and opening, so a tab
/// chosen while it's closed is the one it opens on; the layout shows All
/// while the tab's project isn't there (`MenuModel.resolved`).
@MainActor
@Observable
final class PanelState {
    /// Whether the panel's window is on screen: its appearing and
    /// disappearing set it.
    var isOpen = false
    /// The tabs layout's selected tab.
    private(set) var selectedTab: MenuTab = .all
    /// Whether the latest tab change moved right in `tabs`, so the list
    /// slides that way.
    private(set) var movedForward = true

    /// Selects `next`, recording which way it moved from the tab shown
    /// (`shown`) among `tabs`.
    func select(_ next: MenuTab, from shown: MenuTab, in tabs: [MenuTab]) {
        movedForward = (tabs.firstIndex(of: next) ?? 0) >= (tabs.firstIndex(of: shown) ?? 0)
        selectedTab = next
    }
}
