import AppKit
import SwiftUI

enum SailboatImage {
    static let menuBarSide: CGFloat = 16

    static func menuBarPath(side: CGFloat = menuBarSide) -> CGPath {
        Sailboat.path(in: CGRect(x: 0, y: 0, width: side, height: side))
    }

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
