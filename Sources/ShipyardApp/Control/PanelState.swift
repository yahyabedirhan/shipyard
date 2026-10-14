import Observation
import ShipyardControl
import ShipyardCore

@MainActor
@Observable
final class PanelState {
    var isOpen = false
    var closingByControl = false
    var reopenGuard = PanelReopenGuard()
    var openView: SetupPart?
    private(set) var selectedTab: MenuTab = .all
    private(set) var movedForward = true

    func select(_ next: MenuTab, from shown: MenuTab, in tabs: [MenuTab]) {
        movedForward = (tabs.firstIndex(of: next) ?? 0) >= (tabs.firstIndex(of: shown) ?? 0)
        selectedTab = next
    }
}
