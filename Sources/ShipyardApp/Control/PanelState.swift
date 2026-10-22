import Observation
import ShipyardControl
import ShipyardCore

@MainActor
@Observable
final class PanelState {
    var isOpen = false
    var closingByControl = false
    var reopenGuard = PanelReopenGuard()
    /// The status view shown in place of the projects; `nil` shows them.
    private(set) var openView: SetupPart?
    /// Looks at what a status view shows (ntn for Notion, the link for
    /// the CLI, the skill), each time `show` opens a different view.
    @ObservationIgnored var lookAt: (SetupPart) -> Void = { _ in }
    private(set) var selectedTab: MenuTab = .all
    private(set) var movedForward = true

    /// Opens a status view, or the projects for `nil`, from the settings
    /// menu, a banner, Back or `shipyard panel show-view`. A view's check
    /// starts here, when it opens, never when SwiftUI draws it: the panel
    /// may be closed (`show-view`), and a screenshot draws a copy of the
    /// panel off screen that must not start the check over.
    func show(_ part: SetupPart?) {
        guard part != openView else { return }
        openView = part
        if let part { lookAt(part) }
    }

    func select(_ next: MenuTab, from shown: MenuTab, in tabs: [MenuTab]) {
        movedForward = (tabs.firstIndex(of: next) ?? 0) >= (tabs.firstIndex(of: shown) ?? 0)
        selectedTab = next
    }
}
