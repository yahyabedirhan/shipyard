import AppKit

/// The yellow dot the menu bar icon carries while an agent holds the lease,
/// as macOS's recording dot says something is using the microphone.
///
/// The menu bar draws a template image in its own tint and would tint the
/// dot with it, so the icon with its dot is one image in its own colours:
/// the icon tinted like text for the appearance it's drawn in (black in a
/// light menu bar, white in a dark one), and the dot beside it, cut out of
/// whatever it overlaps.
enum LeaseDot {
    /// The icon the dot goes on: the sailboat, or the pause glyph while
    /// refreshing is paused.
    enum Icon: Sendable {
        case sailboat
        case paused

        /// The icon as the menu bar shows it without the dot: a template.
        var template: NSImage {
            switch self {
            case .sailboat:
                return SailboatImage.menuBar()
            case .paused:
                return NSImage(systemSymbolName: "pause.circle", accessibilityDescription: "paused") ?? SailboatImage.menuBar()
            }
        }
    }

    /// The dot's diameter, and the clear ring around it, in points.
    static let diameter: CGFloat = 6
    static let ring: CGFloat = 1.5
    /// How far the image reaches past the icon's right edge for the dot.
    static let overhang: CGFloat = 4

    /// `icon` with the dot at its top right. The image is drawn each time
    /// it's shown, so it follows the menu bar's appearance.
    static func image(on icon: Icon) -> NSImage {
        let iconSize = icon.template.size
        let size = NSSize(width: iconSize.width + overhang, height: iconSize.height)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let iconRect = NSRect(origin: .zero, size: iconSize)
            icon.template.draw(in: iconRect)
            // The template's pixels tinted like text, in the appearance being drawn.
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
