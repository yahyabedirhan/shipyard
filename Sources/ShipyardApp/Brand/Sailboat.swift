import CoreGraphics

/// shipyard's sailboat: the one figure behind the app icon, the menu bar item
/// and the connect screen's badge. It's our own drawing, facing right: a jib
/// with a bellied luff ahead of the mast, a taller mainsail whose luff bows
/// forward and whose head rounds over into a full leech, a stub of mast down to
/// the hull, a hull whose bottom edge rides the swell, and a wave line below.
///
/// CoreGraphics only, so the icon script (`Packaging/Icon/make-icon.swift`)
/// compiles this same file: the icon and the app draw one path.
enum Sailboat {
    /// The figure on the app icon's 1024-point grid, y up, as one filled outline
    /// (the wave is already stroked, and every corner softly rounded).
    /// A `CGPath` is immutable once built, so sharing it across threads is safe.
    nonisolated(unsafe) static let path: CGPath = makePath()

    /// The figure's own bounds on the 1024 grid.
    static var bounds: CGRect { path.boundingBoxOfPath }

    /// The figure scaled to fit `rect` and centred in it. `yDown` flips it for
    /// top-left-origin drawing (SwiftUI shapes, flipped views).
    static func path(in rect: CGRect, yDown: Bool = false) -> CGPath {
        let b = bounds
        let scale = min(rect.width / b.width, rect.height / b.height)
        var t = CGAffineTransform(translationX: rect.midX, y: rect.midY)
        t = t.scaledBy(x: scale, y: yDown ? -scale : scale)
        t = t.translatedBy(x: -b.midX, y: -b.midY)
        return path.copy(using: &t)!
    }

    // MARK: - Drawing

    /// The gap between the jib and the mainsail, and the stub of mast in it.
    private static let slot: CGFloat = 44

    private static func makePath() -> CGPath {
        let foot: CGFloat = 430

        // Each part is its own path, joined with `union` below: overlapping
        // subpaths of one path can wind against each other and leave holes.
        var parts: [CGPath] = []
        var body = CGMutablePath()

        // Mainsail: the luff bows forward from the tack up to the head, the
        // head rounds over, and the leech bellies out aft and sweeps down to
        // the clew. The foot curves up a little.
        let tack = CGPoint(x: 520, y: foot), head = CGPoint(x: 548, y: 808), clew = CGPoint(x: 722, y: foot)
        body.move(to: tack)
        body.addCurve(to: head, control1: CGPoint(x: 486, y: 560), control2: CGPoint(x: 500, y: 730))
        body.addCurve(to: clew, control1: CGPoint(x: 668, y: 800), control2: CGPoint(x: 800, y: 590))
        body.addQuadCurve(to: tack, control: CGPoint(x: 620, y: foot + 18))
        body.closeSubpath()
        parts.append(body); body = CGMutablePath()

        // Jib: its back edge follows the mainsail's luff a slot ahead of it,
        // its luff bellies forward, and its foot curves up a little too.
        let jibHead = CGPoint(x: 518 - slot + 8, y: 734), jibTack = CGPoint(x: 312, y: foot)
        let jibClew = CGPoint(x: tack.x - slot, y: foot)
        body.move(to: jibClew)
        body.addCurve(to: jibHead, control1: CGPoint(x: jibClew.x - 32, y: 560), control2: CGPoint(x: jibHead.x - 16, y: 670))
        body.addCurve(to: jibTack, control1: CGPoint(x: 430, y: 660), control2: CGPoint(x: 350, y: 540))
        body.addQuadCurve(to: jibClew, control: CGPoint(x: (jibTack.x + jibClew.x) / 2, y: foot + 14))
        body.closeSubpath()
        parts.append(body); body = CGMutablePath()

        // Mast: a stub down from the sails' feet to the deck, in the slot.
        let mastX = tack.x - slot / 2
        parts.append(CGPath(rect: CGRect(x: mastX - 10, y: 370, width: 20, height: foot + 10 - 370), transform: nil))

        // Hull: a straight deck, sides that curve in, and a bottom edge on the swell.
        let deck: CGFloat = 392, keel: CGFloat = 318
        body.move(to: CGPoint(x: 290, y: deck))
        body.addLine(to: CGPoint(x: 748, y: deck))
        body.addQuadCurve(to: CGPoint(x: 704, y: keel + swell(704)), control: CGPoint(x: 738, y: keel + 30))
        for i in 1...120 {
            let x = 704 - (704 - 330) * CGFloat(i) / 120
            body.addLine(to: CGPoint(x: x, y: keel + swell(x)))
        }
        body.addQuadCurve(to: CGPoint(x: 290, y: deck), control: CGPoint(x: 300, y: keel + 30))
        body.closeSubpath()
        parts.append(body)

        // Round every corner a little.
        let rounded = parts.map { $0.union($0.copy(strokingWithWidth: 18, lineCap: .round, lineJoin: .round, miterLimit: 10)) }
            .reduce(CGMutablePath() as CGPath) { $0.union($1) }

        // The wave line below the hull, on the same swell so the two run in step.
        let wave = CGMutablePath()
        for i in 0...160 {
            let x = waveLeft + (waveRight - waveLeft) * CGFloat(i) / 160
            let p = CGPoint(x: x, y: 236 + swell(x))
            i == 0 ? wave.move(to: p) : wave.addLine(to: p)
        }
        return rounded.union(wave.copy(strokingWithWidth: 34, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }

    private static let waveLeft: CGFloat = 272, waveRight: CGFloat = 764

    /// Two whole swells across the wave line's width.
    private static func swell(_ x: CGFloat) -> CGFloat {
        let period = (waveRight - waveLeft) / 2
        return 24 * sin((x - waveLeft) / period * 2 * .pi)
    }
}
