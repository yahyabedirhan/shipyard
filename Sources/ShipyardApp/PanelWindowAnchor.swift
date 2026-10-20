import AppKit
import SwiftUI

/// Keeps the panel's window where it opened, sideways, for as long as it's
/// open.
///
/// SwiftUI's `MenuBarExtra` window lines itself up under the status item
/// again each time it resizes. When the menu bar's count widens the item
/// while the panel is open (from "1" to "26" on the first refresh), the next
/// resize, such as a tab switch changing the panel's height, would slide the
/// panel sideways. This puts the window's left edge back inside the same
/// frame change, before it's drawn, so the slide never shows; the panel
/// lines up with the item again the next time it opens.
///
/// The edge is read when the window becomes key on opening, after SwiftUI
/// has placed it, and kept inside the screen's visible frame.
struct PanelWindowAnchor: NSViewRepresentable {
    let isOpen: Bool

    func makeNSView(context: Context) -> Anchor {
        Anchor()
    }

    func updateNSView(_ view: Anchor, context: Context) {
        view.isOpen = isOpen
    }

    final class Anchor: NSView {
        var isOpen = false {
            didSet {
                guard isOpen != oldValue else { return }
                keptX = nil
                if isOpen, window?.isKeyWindow == true {
                    DispatchQueue.main.async { [weak self] in self?.keepCurrentEdge() }
                }
            }
        }

        private var keptX: CGFloat?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            NotificationCenter.default.removeObserver(self)
            keptX = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // Selector observers run inside the frame change that posts them.
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(becameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(self, selector: #selector(frameChanged), name: NSWindow.didMoveNotification, object: window)
            center.addObserver(self, selector: #selector(frameChanged), name: NSWindow.didResizeNotification, object: window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        @objc private func becameKey(_ notification: Notification) {
            keepCurrentEdge()
        }

        private func keepCurrentEdge() {
            guard isOpen, keptX == nil, let window, window.isVisible else { return }
            keptX = window.frame.minX
        }

        @objc private func frameChanged(_ notification: Notification) {
            guard isOpen, var x = keptX, let window else { return }
            let frame = window.frame
            if let visible = window.screen?.visibleFrame {
                x = max(visible.minX, min(x, visible.maxX - frame.width))
            }
            guard abs(frame.minX - x) >= 0.5 else { return }
            window.setFrameOrigin(NSPoint(x: x, y: frame.minY))
        }
    }
}
