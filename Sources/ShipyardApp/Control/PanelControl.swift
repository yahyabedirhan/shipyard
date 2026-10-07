import Foundation
import ShipyardCommand
import ShipyardConfig
import ShipyardControl
import ShipyardCore
import SwiftUI

/// What the control server asks of the panel and the menu behind it. Each
/// operation that names a project, kind or tab refuses with the ones that
/// exist (`PanelRefusal`).
@MainActor
protocol PanelControlling: AnyObject {
    /// The app's status: its version, whether the panel is open, the view
    /// it shows, the menu's layout and selected tab, the projects, which
    /// are folded and which groups show every row.
    func status() -> AppStatus
    /// Opens the panel, once it's on screen; refused when it didn't open.
    func open() async throws(PanelRefusal)
    /// Closes the panel, once it's gone; refused when it didn't close.
    func close() async throws(PanelRefusal)
    /// Collapses the project's section.
    func fold(_ project: String) throws(PanelRefusal)
    /// Expands the project's section.
    func unfold(_ project: String) throws(PanelRefusal)
    /// Shows every row of the project's group of `kind`
    /// (`pull-requests`, `issues`, `workflow-runs`, `pings`, `notes`).
    func showMore(_ project: String, kind: String) throws(PanelRefusal)
    /// Selects the tab `name` names in the tabs layout, and returns its
    /// title (`All`, or the project's name).
    func selectTab(_ name: String) throws(PanelRefusal) -> String
    /// Shows the status view `name` names (`github`, `notion`, `skill`,
    /// `cli`) in place of the projects, or the projects again
    /// (`projects`), and returns what it shows: the view's title, or
    /// `projects`.
    func showView(_ name: String) throws(PanelRefusal) -> String
}

/// The panel as app control sees it: `PanelState`, the menu bar window
/// behind it, and the orchestrator's operations a click would run.
@MainActor
final class PanelControl: PanelControlling {
    private let shipyard: Shipyard
    private let state: PanelState
    /// The folder a demo run reads (`AppFiles.demo`), nil for the user's own app.
    private let demo: URL?
    /// How long `open` and `close` wait for the panel to appear or go.
    private static let wait = Duration.seconds(2)

    init(shipyard: Shipyard, state: PanelState, demo: URL?) {
        self.shipyard = shipyard
        self.state = state
        self.demo = demo
    }

    func status() -> AppStatus {
        let configuration = shipyard.configStore.lastValid
        let menu = shipyard.menu
        return AppStatus(
            version: ShipyardVersion.current,
            panelOpen: state.isOpen,
            view: state.openView?.commandName ?? SetupPart.projectsName,
            layout: configuration.menu.layout.rawValue,
            // As `tab` accepts it: only while the menu draws tabs.
            tab: menu.layout == .tabs ? PanelText.tabTitle(menu.resolved(state.selectedTab)) : nil,
            // As `fold` and `tab` accept them, remote machines included.
            projects: menu.projectNames,
            folded: menu.collapsedProjects,
            showingAll: menu.kindGroupsShowingAll.map { AppStatus.Group(project: $0.project, kind: $0.kind.commandName) },
            demo: demo?.path
        )
    }

    /// Refused while the user's close keeps app control out
    /// (`PanelReopenGuard`), with nothing done.
    func open() async throws(PanelRefusal) {
        if !state.isOpen, let refusal = state.reopenGuard.refusal(at: Date(), timeZone: .current) {
            throw PanelRefusal(refusal)
        }
        guard await present(true) else {
            throw PanelRefusal("the panel didn't open within \(Self.wait.components.seconds) seconds; click shipyard's menu bar icon")
        }
    }

    func close() async throws(PanelRefusal) {
        guard await present(false) else {
            throw PanelRefusal("the panel didn't close within \(Self.wait.components.seconds) seconds")
        }
    }

    /// Asks the menu bar window to be open (or closed) unless it already
    /// is, and waits until the panel's appearing (or disappearing) says so.
    private func present(_ open: Bool) async -> Bool {
        guard state.isOpen != open else { return true }
        if open {
            MenuBarWindow.open()
        } else {
            state.closingByControl = true
            MenuBarWindow.close()
        }
        let step = Duration.milliseconds(50)
        var waited = Duration.zero
        while state.isOpen != open, waited < Self.wait {
            try? await Task.sleep(for: step)
            waited += step
        }
        // A close that didn't happen isn't app control's any more.
        if !open, state.isOpen { state.closingByControl = false }
        return state.isOpen == open
    }

    func fold(_ project: String) throws(PanelRefusal) {
        try shipyard.setCollapsed(project, true)
    }

    func unfold(_ project: String) throws(PanelRefusal) {
        try shipyard.setCollapsed(project, false)
    }

    func showMore(_ project: String, kind: String) throws(PanelRefusal) {
        try shipyard.showMore(project, kind: kind)
    }

    func selectTab(_ name: String) throws(PanelRefusal) -> String {
        let menu = shipyard.menu
        let tab = try menu.tab(named: name)
        withAnimation(Motion.tab) {
            state.select(tab, from: menu.resolved(state.selectedTab), in: menu.tabs)
        }
        return PanelText.tabTitle(tab)
    }

    func showView(_ name: String) throws(PanelRefusal) -> String {
        let part = try SetupPart.named(name)
        state.openView = part
        return part.map(PanelText.statusTitle) ?? SetupPart.projectsName
    }
}
