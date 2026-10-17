import CoreGraphics

/// shipyard's logo: the sailboat (`Sailboat.path`) folded like paper, white on
/// a graphite squircle with a double rim, in the style of the
/// skills repository's logo. Each sail folds along a crease from its
/// head to its foot: the face ahead of the crease is shaded, the face behind it
/// lit, as if from the right. The app icon (`make-icon.swift`'s
/// `graphite`) and the welcome screens' badge both draw it from here, so
/// their shape, colours and figure can't drift apart.
///
/// CoreGraphics only, so the icon script compiles this same file.
enum Logo {
    /// The body's gradient, top to bottom: the graphite tile.
    static let top: UInt32 = 0x222529
    static let bottom: UInt32 = 0x131417
    /// The figure's lit faces, and the sails' shaded faces (`folds`).
    static let figure: UInt32 = 0xFFFFFF
    static let shade: UInt32 = 0xB9BEC4

    /// One of the body's two rims: a squircle `inset` inside the body's edge,
    /// stroked `width` wide in white that fades from `topAlpha` to
    /// `bottomAlpha` down the body. Inset and width are fractions of the body's side.
    struct Rim {
        let inset: CGFloat, width: CGFloat, topAlpha: CGFloat, bottomAlpha: CGFloat
    }

    /// A bright outer rim and a faint inner one. Below 64 pixels the icon
    /// draws the outer one alone (`smallRims`): the inner one would blur into it.
    static let rims = [
        Rim(inset: 4 / 256, width: 2 / 256, topAlpha: 0.32, bottomAlpha: 0.08),
        Rim(inset: 12 / 256, width: 1.5 / 256, topAlpha: 0.14, bottomAlpha: 0.03),
    ]
    static var smallRims: [Rim] { Array(rims.prefix(1)) }

    /// The rim's squircle in a body filling `body`, ready to stroke.
    static func rimPath(_ rim: Rim, inBody body: CGRect) -> CGPath {
        squircle(in: body.insetBy(dx: rim.inset * body.width, dy: rim.inset * body.width))
    }

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

    /// The sails' shaded faces on `Sailboat.path`'s own grid: the part of the
    /// figure ahead of each sail's crease, above the deck. The jib's crease runs
    /// from its head (482, 734) and the mainsail's from its head (548, 808),
    /// each to a point on its foot; the mainsail's face starts aft of the mast,
    /// so the mast stays lit.
    /// A `CGPath` is immutable once built, so sharing it across threads is safe.
    nonisolated(unsafe) static let folds: CGPath = {
        let deck: CGFloat = 401
        let faces = CGMutablePath()
        faces.addLines(between: [
            CGPoint(x: 0, y: deck), CGPoint(x: 413.6, y: deck), CGPoint(x: 482, y: 734),
            CGPoint(x: 482, y: 1024), CGPoint(x: 0, y: 1024),
        ])
        faces.closeSubpath()
        faces.addLines(between: [
            CGPoint(x: 512, y: deck), CGPoint(x: 605.5, y: deck), CGPoint(x: 548, y: 808),
            CGPoint(x: 548, y: 1024), CGPoint(x: 512, y: 1024),
        ])
        faces.closeSubpath()
        return Sailboat.path.intersection(faces)
    }()

    /// Maps `Sailboat.path` onto a body filling `body`: centred, and sized
    /// against the body as the icon sizes it. `yDown` for top-left-origin drawing.
    static func figureTransform(inBody body: CGRect, small: Bool = false, yDown: Bool = false) -> CGAffineTransform {
        let scale = (small ? smallFigureScale : figureScale) * body.width / iconBody
        return Sailboat.transform(centredAt: CGPoint(x: body.midX, y: body.midY), scale: scale, yDown: yDown)
    }

    static func figurePath(inBody body: CGRect, small: Bool = false, yDown: Bool = false) -> CGPath {
        var t = figureTransform(inBody: body, small: small, yDown: yDown)
        return Sailboat.path.copy(using: &t)!
    }

    /// `folds` on a body filling `body`, placed as `figurePath` places the figure.
    static func foldsPath(inBody body: CGRect, small: Bool = false, yDown: Bool = false) -> CGPath {
        var t = figureTransform(inBody: body, small: small, yDown: yDown)
        return folds.copy(using: &t)!
    }
}
