import Foundation
import ShipyardCommand
import ShipyardConfig
import ShipyardControl
import ShipyardCore
import SwiftUI

@MainActor
protocol PanelControlling: AnyObject {
    func status() -> AppStatus
    func open() async throws(PanelRefusal)
    func close() async throws(PanelRefusal)
    func fold(_ project: String) throws(PanelRefusal)
    func unfold(_ project: String) throws(PanelRefusal)
    func showMore(_ project: String, kind: String) throws(PanelRefusal)
    func selectTab(_ name: String) throws(PanelRefusal) -> String
    func showView(_ name: String) throws(PanelRefusal) -> String
}

@MainActor
final class PanelControl: PanelControlling {
    private let shipyard: Shipyard
    private let state: PanelState
    private let demo: URL?
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
            tab: menu.layout == .tabs ? menu.tabTitle(menu.resolved(state.selectedTab)) : nil,
            projects: menu.projectNames,
            folded: menu.collapsedProjects,
            showingAll: menu.kindGroupsShowingAll.map { AppStatus.Group(project: $0.project, kind: $0.kind.commandName) },
            demo: demo?.path
        )
    }

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
        return menu.tabTitle(tab)
    }

    func showView(_ name: String) throws(PanelRefusal) -> String {
        let part = try SetupPart.named(name)
        state.openView = part
        return part.map(PanelText.statusTitle) ?? SetupPart.projectsName
    }
}
