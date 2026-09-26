import CoreGraphics

/// shipyard's logo: the sailboat (`Sailboat.path`) in cream on an olive khaki
/// squircle. The app icon (`make-icon.swift`'s `olive-khaki`) and the welcome
/// screens' badge both draw it from here, so their shape, colours and figure
/// can't drift apart.
///
/// CoreGraphics only, so the icon script compiles this same file.
enum Logo {
    /// The body's gradient, top to bottom, and the figure's colour.
    static let top: UInt32 = 0x8C8660
    static let bottom: UInt32 = 0x6A6541
    static let figure: UInt32 = 0xFBF6EA
    /// A white sheen over the body's top half, fading out at the middle.
    static let sheen: CGFloat = 0.14

    static func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
        CGColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
    }

    /// The icon's body is 824 points on its 1024-point grid (the macOS 11+ grid).
    static let iconBody: CGFloat = 824
    /// How big the figure is against the body: `Sailboat.path` at this scale on
    /// the 1024 grid, and a little bigger when drawing below 64 pixels.
    static let figureScale: CGFloat = 0.92
    static let smallFigureScale: CGFloat = 1.1

    /// The macOS 11+ body shape: a squircle (a superellipse) filling `rect`.
    static func squircle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let n: CGFloat = 5
        let a = rect.width / 2, b = rect.height / 2
        let steps = 720
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let c = cos(t), s = sin(t)
            let x = a * copysign(pow(abs(c), 2 / n), c)
            let y = b * copysign(pow(abs(s), 2 / n), s)
            let p = CGPoint(x: rect.midX + x, y: rect.midY + y)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }

    /// Maps `Sailboat.path` onto a body filling `body`: centred, and sized
    /// against the body as the icon sizes it. `yDown` for top-left-origin drawing.
    static func figureTransform(inBody body: CGRect, small: Bool = false, yDown: Bool = false) -> CGAffineTransform {
        let b = Sailboat.bounds
        let scale = (small ? smallFigureScale : figureScale) * body.width / iconBody
        return CGAffineTransform(translationX: body.midX, y: body.midY)
            .scaledBy(x: scale, y: yDown ? -scale : scale)
            .translatedBy(x: -b.midX, y: -b.midY)
    }

    static func figurePath(inBody body: CGRect, small: Bool = false, yDown: Bool = false) -> CGPath {
        var t = figureTransform(inBody: body, small: small, yDown: yDown)
        return Sailboat.path.copy(using: &t)!
    }
}
