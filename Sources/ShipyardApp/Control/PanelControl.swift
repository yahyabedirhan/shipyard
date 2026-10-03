import ShipyardCommand
import ShipyardControl
import ShipyardCore

/// What the control server asks of the panel and the menu behind it.
@MainActor
protocol PanelControlling: AnyObject {
    /// The app's status: its version, whether the panel is open, the
    /// menu's layout and the projects.
    func status() -> AppStatus
}

/// The panel as app control sees it: whether it's open, which the panel's
/// own appearing and disappearing set, and the menu `shipyard` shows.
@MainActor
final class PanelControl: PanelControlling {
    private let shipyard: Shipyard
    /// Whether the panel's window is on screen.
    var isOpen = false

    init(shipyard: Shipyard) {
        self.shipyard = shipyard
    }

    func status() -> AppStatus {
        let configuration = shipyard.configStore.lastValid
        return AppStatus(
            version: ShipyardVersion.current,
            panelOpen: isOpen,
            layout: configuration.menu.layout.rawValue,
            projects: configuration.projects.map(\.name)
        )
    }
}
