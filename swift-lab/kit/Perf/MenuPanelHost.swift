import AppKit
import SwiftUI

/// Hosts the panel the way `MenuBarExtra(.window)` does in the app: a
/// borderless, non-activating panel whose size follows the SwiftUI
/// content's preferred size, rather than a fixed window. It opens behind
/// other windows at the bottom left, so the maintainer's work isn't covered;
/// the meter in the lab window measures it all the same (one main thread).
@MainActor
final class MenuPanelHost {
    static let shared = MenuPanelHost()
    private var panel: NSPanel?

    var isOpen: Bool { panel != nil }

    func open(store: LabStore) {
        guard panel == nil else { return }
        let controller = NSHostingController(rootView: LabPanel(store: store))
        controller.sizingOptions = [.preferredContentSize]
        let panel = NSPanel(
            contentRect: NSRect(x: 40, y: 40, width: Grid.panelWidth, height: 600),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.contentViewController = controller
        panel.isReleasedWhenClosed = false
        panel.hasShadow = true
        panel.level = .normal
        panel.setFrameOrigin(NSPoint(x: 40, y: 40))
        panel.orderBack(nil)
        self.panel = panel
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
