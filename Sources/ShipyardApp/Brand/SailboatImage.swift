import AppKit
import SwiftUI

/// The menu bar item, drawn from `Sailboat.path`. The app icon and the
/// welcome screens' badge (`LogoBadge`) draw the same path (make-icon.swift
/// compiles Sailboat.swift), so all three show one figure.
enum SailboatImage {
    /// The menu bar item's side, in points.
    static let menuBarSide: CGFloat = 16

    /// The path the menu bar item fills: the sailboat fitted to a square of `side` points.
    static func menuBarPath(side: CGFloat = menuBarSide) -> CGPath {
        Sailboat.path(in: CGRect(x: 0, y: 0, width: side, height: side))
    }

    /// The menu bar item: a template image, so the menu bar tints it to match
    /// its appearance, as it does a symbol.
    static func menuBar(side: CGFloat = menuBarSide) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(menuBarPath(side: side))
            context.setFillColor(.black)
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "shipyard"
        return image
    }
}
