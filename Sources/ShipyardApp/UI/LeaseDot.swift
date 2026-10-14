import AppKit

enum LeaseDot {
    enum Icon: Sendable {
        case sailboat
        case paused

        var template: NSImage {
            switch self {
            case .sailboat:
                return SailboatImage.menuBar()
            case .paused:
                return NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "paused") ?? SailboatImage.menuBar()
            }
        }
    }

    static let diameter: CGFloat = 6
    static let ring: CGFloat = 1.5
    static let overhang: CGFloat = 4

    static func image(on icon: Icon) -> NSImage {
        let iconSize = icon.template.size
        let size = NSSize(width: iconSize.width + overhang, height: iconSize.height)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let iconRect = NSRect(origin: .zero, size: iconSize)
            icon.template.draw(in: iconRect)
            let isDark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (isDark ? NSColor.white : NSColor.black).setFill()
            iconRect.fill(using: .sourceAtop)
            let dot = CGRect(x: size.width - diameter, y: size.height - diameter, width: diameter, height: diameter)
            context.setBlendMode(.clear)
            context.fillEllipse(in: dot.insetBy(dx: -ring, dy: -ring))
            context.setBlendMode(.normal)
            context.setFillColor(NSColor.systemYellow.cgColor)
            context.fillEllipse(in: dot)
            return true
        }
        image.isTemplate = false
        image.cacheMode = .never
        image.accessibilityDescription = "shipyard, in use by an agent"
        return image
    }
}
