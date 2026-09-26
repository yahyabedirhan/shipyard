// Draws Shipyard's app icon in one of four variants (see README.md here):
//
//   origami    the menu bar's sailboat folded from paper, on amber (the app's icon)
//   sailboat   the menu bar's sailboat on a sea-blue squircle
//   night      the sailboat under a crescent moon and stars
//   sunset     the sailboat in silhouette against a low sun
//
//   swift Packaging/Icon/make-icon.swift <out.iconset> [--variant <name>]   every size an .iconset needs (origami by default)
//   swift Packaging/Icon/make-icon.swift --sheet <out.png>                  a contact sheet of every variant, for review
//   swift Packaging/Icon/make-icon.swift --exploration <dir>                the minimal sailboat options, one PNG each and a comparison sheet
//
// Command Line Tools only (AppKit and CoreGraphics). `make icon` runs it and
// packs the iconset with `iconutil -c icns` into Packaging/Icon/AppIcon.icns;
// `make icon-alternates` packs the others into Packaging/Icon/alternates/.
//
// Everything is drawn on the 1024-point macOS 11+ icon grid (an 824-point body
// with a drop shadow) and rendered at each pixel size as vectors. Below 64
// pixels each variant simplifies (a bigger subject, less fine detail), so it
// still reads at 16.

import AppKit

// MARK: - Colour and gradients

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

/// A gradient through `colors`, evenly spaced unless `locations` are given.
func grad(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    let l = locations ?? colors.indices.map { CGFloat($0) / CGFloat(max(colors.count - 1, 1)) }
    return CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: l)!
}

// MARK: - Shapes (1024 grid, y up)

typealias P = (CGFloat, CGFloat)

/// The macOS 11+ body: an 824-point squircle (superellipse) centred on the grid.
func squircle(in rect: CGRect) -> CGPath {
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

func poly(_ pts: [P]) -> CGPath {
    let p = CGMutablePath()
    p.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
    p.closeSubpath()
    return p
}

func disc(_ c: P, _ r: CGFloat) -> CGPath {
    CGPath(ellipseIn: CGRect(x: c.0 - r, y: c.1 - r, width: r * 2, height: r * 2), transform: nil)
}

/// The sea: a swell across the body, filled down past its bottom edge.
func wave(_ body: CGRect, level: CGFloat, amplitude: CGFloat, waves: CGFloat, phase: CGFloat = 0.6) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: body.minX - 10, y: body.minY - 10))
    for i in 0...200 {
        let x = body.minX - 10 + (body.width + 20) * CGFloat(i) / 200
        let ph = (x - body.minX) / body.width * waves * 2 * .pi
        path.addLine(to: CGPoint(x: x, y: level + amplitude * sin(ph + phase)))
    }
    path.addLine(to: CGPoint(x: body.maxX + 10, y: body.minY - 10))
    path.closeSubpath()
    return path
}

struct Boat {
    var jib: CGPath
    var main: CGPath
    var mast: CGPath
    var hull: CGPath
}

/// The sailboat SF Symbol's shape: a straight-edged jib ahead of the mast, a
/// taller mainsail with a curved leech behind it, and a hull.
func boat() -> Boat {
    let mastX: CGFloat = 520
    let boomY: CGFloat = 392
    let headY: CGFloat = 812

    let jib = CGMutablePath()
    jib.move(to: CGPoint(x: mastX - 26, y: headY - 60))
    jib.addLine(to: CGPoint(x: mastX - 26, y: boomY))
    jib.addLine(to: CGPoint(x: 300, y: boomY))
    jib.closeSubpath()

    let main = CGMutablePath()
    main.move(to: CGPoint(x: mastX + 22, y: headY))
    main.addCurve(
        to: CGPoint(x: 748, y: boomY),
        control1: CGPoint(x: 700, y: 700),
        control2: CGPoint(x: 770, y: 520))
    main.addLine(to: CGPoint(x: mastX + 22, y: boomY))
    main.closeSubpath()

    let mast = CGPath(
        roundedRect: CGRect(x: mastX - 11, y: 340, width: 22, height: headY + 18 - 340),
        cornerWidth: 11, cornerHeight: 11, transform: nil)

    let hull = CGMutablePath()
    hull.move(to: CGPoint(x: 262, y: 358))
    hull.addLine(to: CGPoint(x: 786, y: 358))
    hull.addQuadCurve(to: CGPoint(x: 690, y: 250), control: CGPoint(x: 760, y: 272))
    hull.addLine(to: CGPoint(x: 350, y: 250))
    hull.addQuadCurve(to: CGPoint(x: 262, y: 358), control: CGPoint(x: 284, y: 272))
    hull.closeSubpath()

    return Boat(jib: jib, main: main, mast: mast, hull: hull)
}

// MARK: - Drawing helpers

func fillSolid(_ ctx: CGContext, _ path: CGPath, _ color: CGColor) {
    ctx.addPath(path); ctx.setFillColor(color); ctx.fillPath()
}

/// Fills `path` with a gradient running from p0 to p1, extended past both ends.
func fillAlong(_ ctx: CGContext, _ path: CGPath, _ g: CGGradient, _ p0: CGPoint, _ p1: CGPoint) {
    ctx.saveGState(); ctx.addPath(path); ctx.clip()
    ctx.drawLinearGradient(g, start: p0, end: p1, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

/// Fills `path` with a vertical gradient from `top` at y0 to `bottom` at y1.
func fill(_ ctx: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor, from y0: CGFloat, to y1: CGFloat) {
    fillAlong(ctx, path, grad([top, bottom]), CGPoint(x: 0, y: y0), CGPoint(x: 0, y: y1))
}

/// A radial gradient about `c`, clipped to `path` when one is given.
func fillRadial(_ ctx: CGContext, _ path: CGPath?, _ g: CGGradient, _ c: CGPoint, _ r: CGFloat) {
    ctx.saveGState()
    if let path { ctx.addPath(path); ctx.clip() }
    ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: r, options: [.drawsBeforeStartLocation])
    ctx.restoreGState()
}

func line(_ ctx: CGContext, _ pts: [P], _ color: CGColor, _ width: CGFloat) {
    ctx.saveGState()
    ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.addLines(between: pts.map { CGPoint(x: $0.0, y: $0.1) })
    ctx.strokePath()
    ctx.restoreGState()
}

/// A line along the sea's top edge, the same swell `wave` fills.
func crestLine(_ ctx: CGContext, _ body: CGRect, level: CGFloat, amplitude: CGFloat, waves: CGFloat,
               phase: CGFloat = 0.6, color: CGColor, width: CGFloat) {
    let crest = CGMutablePath()
    for i in 0...120 {
        let x = body.minX + body.width * CGFloat(i) / 120
        let ph = (x - body.minX) / body.width * waves * 2 * .pi
        let p = CGPoint(x: x, y: level + amplitude * sin(ph + phase))
        i == 0 ? crest.move(to: p) : crest.addLine(to: p)
    }
    ctx.saveGState()
    ctx.addPath(crest); ctx.setStrokeColor(color); ctx.setLineWidth(width); ctx.setLineCap(.round)
    ctx.strokePath()
    ctx.restoreGState()
}

/// Draws `body` scaled by `s` about `c`.
func scaled(_ ctx: CGContext, _ s: CGFloat, about c: CGPoint, _ body: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: c.x, y: c.y); ctx.scaleBy(x: s, y: s); ctx.translateBy(x: -c.x, y: -c.y)
    body()
    ctx.restoreGState()
}

/// Shadows ignore the transform, so they're given on the 1024 grid and scaled here.
func shadow(_ ctx: CGContext, dy: CGFloat, blur: CGFloat, color: CGColor) {
    let scale = ctx.ctm.a
    ctx.setShadow(offset: CGSize(width: 0, height: dy * scale), blur: blur * scale, color: color)
}

/// The shared macOS 11+ frame: a drop shadow cast by the body filled with
/// `base` (it shows at the body's edge), the squircle body with its background
/// gradient (top of the body down to `backgroundEnd`), the content,
/// a sheen from above and, above 32 pixels, a thin bright rim. The content gets
/// whether it's drawing small (below 64 pixels) and the body's rectangle.
func frame(_ ctx: CGContext, pixels: Int, base: CGColor = rgb(0x203050), background: CGGradient, backgroundEnd: CGFloat? = nil,
           sheen: CGFloat = 0.16, rim: CGFloat = 0.22, _ content: (CGContext, Bool, CGRect) -> Void) {
    let small = pixels < 64
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)
    ctx.saveGState()
    shadow(ctx, dy: -10, blur: 22, color: rgb(0x000000, 0.35))
    fillSolid(ctx, shape, base)
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape); ctx.clip()
    if let backgroundEnd {
        ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: backgroundEnd),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    } else {
        ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    }
    content(ctx, small, body)
    ctx.drawLinearGradient(grad([rgb(0xFFFFFF, sheen), rgb(0xFFFFFF, 0)]),
                           start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
    ctx.restoreGState()

    if !small {
        ctx.saveGState()
        ctx.addPath(shape); ctx.clip()
        ctx.addPath(shape)
        ctx.setStrokeColor(rgb(0xFFFFFF, rim))
        ctx.setLineWidth(4)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

// MARK: - Sailboat: the menu bar's sailboat on a sea-blue squircle

func drawSailboat(_ ctx: CGContext, pixels: Int) {
    let skyTop = rgb(0x4DB5F5), skyBottom = rgb(0x1466D2)
    let seaTop = rgb(0x0E4FA8), seaBottom = rgb(0x082C6B)
    let sailLight = rgb(0xFFFFFF), sailShade = rgb(0xDCE9F7)
    let hullTop = rgb(0xFF9A4D), hullBottom = rgb(0xE2531C)
    let mastColor = rgb(0x0B2F66)

    frame(ctx, pixels: pixels, base: skyBottom, background: grad([skyTop, skyBottom]), backgroundEnd: 340, sheen: 0.18, rim: 0.25) { ctx, small, body in
        let b = boat()
        // Small sizes: a bigger boat on the same background.
        scaled(ctx, small ? 1.22 : 1, about: CGPoint(x: 512, y: 560)) {
            // Sails and mast, with a soft shadow for depth.
            ctx.saveGState()
            shadow(ctx, dy: -8, blur: 18, color: rgb(0x06285C, 0.35))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            fillSolid(ctx, b.mast, mastColor)
            fill(ctx, b.jib, sailLight, sailShade, from: 760, to: 392)
            fill(ctx, b.main, sailLight, sailShade, from: 812, to: 392)
            ctx.endTransparencyLayer()
            ctx.restoreGState()

            if !small {
                // A shaded strip along the main's mast edge: the cloth's curve.
                ctx.saveGState()
                ctx.addPath(b.main); ctx.clip()
                ctx.drawLinearGradient(grad([rgb(0x9DB8DA, 0.45), rgb(0x9DB8DA, 0)]),
                                       start: CGPoint(x: 542, y: 0), end: CGPoint(x: 640, y: 0), options: [])
                ctx.restoreGState()
            }

            ctx.saveGState()
            shadow(ctx, dy: -6, blur: 14, color: rgb(0x06285C, 0.4))
            fill(ctx, b.hull, hullTop, hullBottom, from: 358, to: 250)
            ctx.restoreGState()
            if !small {
                // A light rail along the deck.
                ctx.saveGState()
                ctx.addPath(b.hull); ctx.clip()
                ctx.setFillColor(rgb(0xFFFFFF, 0.28))
                ctx.fill(CGRect(x: 0, y: 340, width: 1024, height: 18))
                ctx.restoreGState()
            }
        }

        // Sea, in front of the hull's keel.
        let level: CGFloat = small ? 222 : 282
        fill(ctx, wave(body, level: level, amplitude: small ? 10 : 14, waves: 2.5), seaTop, seaBottom, from: level + 14, to: body.minY)
        if !small {
            // A darker second swell, and a crest line on the first.
            fillSolid(ctx, wave(body, level: 206, amplitude: 12, waves: 3.5), rgb(0x000000, 0.14))
            crestLine(ctx, body, level: level, amplitude: 14, waves: 2.5, color: rgb(0xFFFFFF, 0.35), width: 6)
        }
    }
}

// MARK: - Origami: the sailboat folded from paper, on amber

func drawOrigami(_ ctx: CGContext, pixels: Int) {
    let bg = grad([rgb(0xFFDB78), rgb(0xF5A03C)])
    frame(ctx, pixels: pixels, background: bg) { ctx, small, body in
        if small {
            // A deeper amber, so the paper stands off it.
            ctx.drawLinearGradient(grad([rgb(0xFFC650), rgb(0xEE8A24)]), start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
        }
        let light = rgb(0xFFFEFA), mid = rgb(0xEEE7DA), shade = rgb(0xD3C7B2), deep = rgb(0xB9AB93)
        let crease = rgb(0xB3A690, 0.9)

        scaled(ctx, small ? 1.2 : 1, about: CGPoint(x: 512, y: 560)) {
            // Jib: two facets either side of a fold from the head.
            let jHead: P = (492, 752), jTack: P = (492, 392), jClew: P = (296, 392), jFold: P = (410, 392)
            // Main: a big facet from head to clew, the leech folded under.
            let mHead: P = (546, 818), mTack: P = (546, 392), mClew: P = (752, 392)
            let l1: P = (672, 650), l2: P = (740, 510)
            // Hull: a deck strip folded over, the side face and the two end flaps.
            let dL: P = (236, 384), dR: P = (812, 384), sL: P = (282, 340), sR: P = (766, 340)
            let kL: P = (360, 214), kR: P = (680, 214)
            let mFold: P = (676, 392)

            // One shadow under the whole boat.
            let whole = CGMutablePath()
            whole.addPath(poly([jHead, jTack, jClew]))
            whole.addPath(poly([mHead, mTack, mClew, l2, l1]))
            whole.addPath(poly([dL, dR, kR, kL]))
            whole.addRect(CGRect(x: 510, y: 372, width: 26, height: 460))
            ctx.saveGState()
            shadow(ctx, dy: -10, blur: 22, color: rgb(0x7A3E08, 0.35))
            fillSolid(ctx, whole, light)
            ctx.restoreGState()

            // Mast: a narrow folded strip.
            fillSolid(ctx, poly([(510, 372), (522, 372), (522, 836), (510, 828)]), mid)
            fillSolid(ctx, poly([(522, 372), (536, 372), (536, 828), (522, 836)]), deep)

            fillAlong(ctx, poly([jHead, jClew, jFold]), grad([light, mid]), CGPoint(x: 0, y: 752), CGPoint(x: 0, y: 392))
            fillAlong(ctx, poly([jHead, jFold, jTack]), grad([mid, shade]), CGPoint(x: 0, y: 752), CGPoint(x: 0, y: 392))
            fillAlong(ctx, poly([mHead, mTack, mFold]), grad([light, mid]), CGPoint(x: 546, y: 0), CGPoint(x: 676, y: 0))
            fillAlong(ctx, poly([mHead, mFold, mClew, l2, l1]), grad([shade, deep]), CGPoint(x: 600, y: 760), CGPoint(x: 740, y: 420))

            fillAlong(ctx, poly([sL, sR, kR, kL]), grad([mid, shade]), CGPoint(x: 0, y: 340), CGPoint(x: 0, y: 214))
            fillSolid(ctx, poly([dL, dR, sR, sL]), light)
            fillSolid(ctx, poly([dL, sL, kL]), shade)
            fillSolid(ctx, poly([dR, sR, kR]), deep)

            if !small {
                for seg in [[jHead, jFold], [mHead, mFold], [sL, sR], [sL, kL], [sR, kR]] {
                    line(ctx, seg, crease, 3)
                }
                // A centre crease down the hull's side.
                line(ctx, [(520, 340), (520, 214)], rgb(0xB3A690, 0.6), 3)
            }
        }

        // The sea, folded too: a row of faceted peaks (fewer when small).
        let level: CGFloat = small ? 214 : 236
        let peaks = small ? 4 : 7
        let step = (body.width + 40) / CGFloat(peaks)
        var pts: [P] = [(body.minX - 20, body.minY - 20)]
        for i in 0...peaks {
            let x = body.minX - 20 + CGFloat(i) * step
            pts.append((x, level - 16))
            if i < peaks { pts.append((x + step / 2, level + 18)) }
        }
        pts.append((body.maxX + 20, body.minY - 20))
        let sea = poly(pts)
        fillAlong(ctx, sea, grad([rgb(0x2F8FE3), rgb(0x0E4FA8)]), CGPoint(x: 0, y: level + 18), CGPoint(x: 0, y: body.minY))
        if !small {
            // Each peak lit on one face and shaded on the other.
            ctx.saveGState()
            ctx.addPath(sea); ctx.clip()
            for i in 0..<peaks {
                let x = body.minX - 20 + CGFloat(i) * step
                fillSolid(ctx, poly([(x, level - 16), (x + step / 2, level + 18), (x + step / 2, body.minY - 20), (x, body.minY - 20)]), rgb(0xFFFFFF, 0.07))
                fillSolid(ctx, poly([(x + step / 2, level + 18), (x + step, level - 16), (x + step, body.minY - 20), (x + step / 2, body.minY - 20)]), rgb(0x001A4A, 0.08))
            }
            ctx.restoreGState()
            // A second, deeper fold.
            var pts2: [P] = [(body.minX - 20, body.minY - 20)]
            for i in 0...peaks {
                let x = body.minX - 20 + CGFloat(i) * step + step / 2
                pts2.append((x, level - 110)); pts2.append((x + step / 2, level - 84))
            }
            pts2.append((body.maxX + 20, body.minY - 20))
            fillSolid(ctx, poly(pts2), rgb(0x001A4A, 0.16))
        }
    }
}

// MARK: - Night: the sailboat under a crescent moon and stars

func drawNight(_ ctx: CGContext, pixels: Int) {
    let bg = grad([rgb(0x0A1236), rgb(0x1B2C6B), rgb(0x3A4F96)], [0, 0.6, 1])
    frame(ctx, pixels: pixels, background: bg, rim: 0.18) { ctx, small, body in
        // Small: a bigger moon, one star and no moon path.
        let moon = small ? CGPoint(x: 760, y: 770) : CGPoint(x: 730, y: 740)
        fillRadial(ctx, nil, grad([rgb(0xFFF1C8, 0.35), rgb(0xFFF1C8, 0)]), moon, 260)
        // Crescent: the moon's disc with an offset disc bitten out.
        let mr: CGFloat = small ? 96 : 70
        ctx.saveGState()
        let bite = CGMutablePath()
        bite.addRect(body)
        bite.addEllipse(in: CGRect(x: moon.x - mr + mr * 0.55, y: moon.y - mr + mr * 0.35, width: mr * 2, height: mr * 2))
        ctx.addPath(bite); ctx.clip(using: .evenOdd)
        fillSolid(ctx, disc((moon.x, moon.y), mr), rgb(0xFFF3CF))
        ctx.restoreGState()

        // Stars: four-point sparkles.
        func star(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ a: CGFloat) {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x, y: y + r))
            p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
            p.addQuadCurve(to: CGPoint(x: x, y: y - r), control: CGPoint(x: x, y: y))
            p.addQuadCurve(to: CGPoint(x: x - r, y: y), control: CGPoint(x: x, y: y))
            p.addQuadCurve(to: CGPoint(x: x, y: y + r), control: CGPoint(x: x, y: y))
            fillSolid(ctx, p, rgb(0xFFFFFF, a))
        }
        if small {
            star(240, 790, 64, 0.95)
        } else {
            star(250, 780, 40, 0.95)
            star(380, 860, 22, 0.8)
            star(620, 860, 16, 0.7)
            star(180, 640, 18, 0.6)
            star(860, 600, 20, 0.7)
            for (x, y) in [(330, 700), (560, 780), (820, 860), (160, 860), (450, 640)] as [P] {
                fillSolid(ctx, disc((x, y), 5), rgb(0xFFFFFF, 0.55))
            }
        }

        // Boat, moonlit.
        let b = boat()
        scaled(ctx, small ? 1.0 : 0.86, about: CGPoint(x: small ? 490 : 440, y: small ? 300 : 330)) {
            ctx.translateBy(x: -60, y: 0)
            ctx.saveGState()
            shadow(ctx, dy: -8, blur: 18, color: rgb(0x000000, 0.35))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            fillSolid(ctx, b.mast, rgb(0xC9D2F0))
            fill(ctx, b.jib, rgb(0xFFFFFF), rgb(0xC3CCEB), from: 760, to: 392)
            fill(ctx, b.main, rgb(0xFFFFFF), rgb(0xC3CCEB), from: 812, to: 392)
            ctx.endTransparencyLayer()
            ctx.restoreGState()
            if !small {
                // Moonlight catches the main's leech; the luff sits in shade.
                ctx.saveGState()
                ctx.addPath(b.main); ctx.clip()
                ctx.drawLinearGradient(grad([rgb(0x7A88BE, 0.45), rgb(0x7A88BE, 0)]), start: CGPoint(x: 542, y: 0), end: CGPoint(x: 660, y: 0), options: [])
                ctx.restoreGState()
            }
            ctx.saveGState()
            shadow(ctx, dy: -6, blur: 14, color: rgb(0x000000, 0.4))
            fill(ctx, b.hull, rgb(0xF08A55), rgb(0xB9431C), from: 358, to: 250)
            ctx.restoreGState()
        }

        let level: CGFloat = small ? 232 : 276
        fillAlong(ctx, wave(body, level: level, amplitude: 12, waves: 2.5), grad([rgb(0x13245E), rgb(0x060C2A)]),
                  CGPoint(x: 0, y: level + 12), CGPoint(x: 0, y: body.minY))
        if !small {
            crestLine(ctx, body, level: level, amplitude: 12, waves: 2.5, color: rgb(0xBFD0FF, 0.35), width: 5)
            // Moon path on the water.
            for (i, w) in ([120, 90, 150, 70, 110] as [CGFloat]).enumerated() {
                let y = level - 34 - CGFloat(i) * 30
                let x = moon.x + (i % 2 == 0 ? -10 : 14)
                fillSolid(ctx, CGPath(roundedRect: CGRect(x: x - w / 2, y: y, width: w, height: 9), cornerWidth: 4.5, cornerHeight: 4.5, transform: nil),
                          rgb(0xFFF1C8, 0.5 - CGFloat(i) * 0.07))
            }
        }
    }
}

// MARK: - Sunset: the sailboat in silhouette against a low sun

func drawSunset(_ ctx: CGContext, pixels: Int) {
    let bg = grad([rgb(0x4B2F7F), rgb(0xD9607E), rgb(0xFFB35C)], [0, 0.55, 1])
    frame(ctx, pixels: pixels, background: bg) { ctx, small, body in
        // Small: a bigger sun and boat, and one bar of light on the water.
        let level: CGFloat = small ? 250 : 290
        let sun: P = (512, level + 150)
        fillRadial(ctx, nil, grad([rgb(0xFFE3A3, 0.6), rgb(0xFFB35C, 0)]), CGPoint(x: sun.0, y: sun.1), 420)
        fillRadial(ctx, disc(sun, small ? 250 : 220), grad([rgb(0xFFF6D2), rgb(0xFFC766), rgb(0xFF9A4A)], [0, 0.6, 1]),
                   CGPoint(x: sun.0, y: sun.1 + 60), 280)

        let silhouette = rgb(0x2B1638)
        let b = boat()
        scaled(ctx, small ? 1.1 : 0.9, about: CGPoint(x: 512, y: level + 40)) {
            ctx.saveGState()
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            for path in [b.jib, b.main, b.mast, b.hull] { fillSolid(ctx, path, silhouette) }
            if !small {
                // A faint warm rim where the sun catches the sails' edges.
                ctx.setBlendMode(.sourceAtop)
                ctx.drawLinearGradient(grad([rgb(0x5A2E52, 0.9), rgb(0x2B1638, 0)]), start: CGPoint(x: 0, y: 820), end: CGPoint(x: 0, y: 600), options: [])
            }
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }

        fillAlong(ctx, wave(body, level: level, amplitude: 10, waves: 2.5), grad([rgb(0xA0507A), rgb(0x3A1C4E), rgb(0x1E1034)], [0, 0.35, 1]),
                  CGPoint(x: 0, y: level + 10), CGPoint(x: 0, y: body.minY))
        // The sun's path on the water.
        let bars: [P] = small ? [(300, 28)] : [(340, 14), (240, 12), (300, 11), (170, 10), (220, 9)]
        for (i, (w, h)) in bars.enumerated() {
            let y = level - (small ? 60 : 36) - CGFloat(i) * 32
            fillSolid(ctx, CGPath(roundedRect: CGRect(x: 512 - w / 2, y: y, width: w, height: h), cornerWidth: h / 2, cornerHeight: h / 2, transform: nil),
                      rgb(0xFFC766, 0.75 - CGFloat(i) * 0.12))
        }
    }
}

// MARK: - Minimal: shipyard's sailboat, flat, like the connect screen's badge

/// shipyard's sailboat as a flat mark of our own paths, facing right like the
/// menu bar item: a straight-edged jib on the left, a taller mainsail with a
/// rounded head and a bellied leech on the right, a thin gap between them, a
/// stub of mast down to the hull, a hull whose bottom edge is a wave, and one
/// wave line below. Small sizes open the gaps and thicken the wave, so the
/// parts stay apart at 16 and 32.
struct MinimalMark {
    var sails: CGPath
    var mast: CGPath
    var hull: CGPath
    var wave: CGPath
    var waveWidth: CGFloat
    var corner: CGFloat
}

func minimalMark(small: Bool) -> MinimalMark {
    let foot: CGFloat = small ? 418 : 404
    let gap: CGFloat = small ? 44 : 30

    let sails = CGMutablePath()
    // Mainsail: the luff bows gently forward from the tack to the head; the
    // head rounds over into a leech that bellies out aft, down to the clew.
    let head = CGPoint(x: 536, y: 784), tack = CGPoint(x: 506, y: foot), clew = CGPoint(x: 706, y: foot)
    sails.move(to: tack)
    sails.addQuadCurve(to: head, control: CGPoint(x: 494, y: 610))
    sails.addCurve(to: clew, control1: CGPoint(x: 648, y: 770), control2: CGPoint(x: 766, y: 580))
    sails.closeSubpath()
    // Jib: a straight luff from its head down to the tack, a flat foot, and a
    // back edge that follows the mainsail's luff a gap ahead of it.
    let jibHead = CGPoint(x: 520 - gap, y: 730), jibTack = CGPoint(x: 318, y: foot)
    sails.move(to: jibHead)
    sails.addLine(to: jibTack)
    sails.addLine(to: CGPoint(x: tack.x - gap, y: foot))
    sails.addQuadCurve(to: jibHead, control: CGPoint(x: 494 - gap, y: 600))
    sails.closeSubpath()

    let mastX = tack.x - gap / 2
    let mastW: CGFloat = small ? 24 : 18
    let mast = CGPath(rect: CGRect(x: mastX - mastW / 2, y: 340, width: mastW, height: foot - 330), transform: nil)

    // The sea's swell, shared by the hull's bottom edge and the wave line so they run in step.
    let left: CGFloat = 286, right: CGFloat = 738, period = (right - left) / 2
    let amplitude: CGFloat = small ? 20 : 19
    func swell(_ x: CGFloat) -> CGFloat { amplitude * sin((x - left) / period * 2 * .pi) }

    let deck: CGFloat = small ? 370 : 362
    let keel: CGFloat = small ? 304 : 302
    let hull = CGMutablePath()
    hull.move(to: CGPoint(x: 316, y: deck))
    hull.addLine(to: CGPoint(x: 712, y: deck))
    for i in 0...120 {
        let x = 698 - (698 - 330) * CGFloat(i) / 120
        hull.addLine(to: CGPoint(x: x, y: keel + swell(x)))
    }
    hull.closeSubpath()

    let waveY: CGFloat = small ? 212 : 248
    let wave = CGMutablePath()
    for i in 0...160 {
        let x = left + (right - left) * CGFloat(i) / 160
        let p = CGPoint(x: x, y: waveY + swell(x))
        i == 0 ? wave.move(to: p) : wave.addLine(to: p)
    }
    return MinimalMark(sails: sails, mast: mast, hull: hull, wave: wave, waveWidth: small ? 38 : 26, corner: small ? 10 : 8)
}

/// The exploration's two families: a coloured body with a white mark, and a
/// white body with the mark in colour. Navy, the favourite, has a lighter and a
/// deeper shade too.
enum Minimal: String, CaseIterable {
    case solidBlue = "solid-blue", solidTeal = "solid-teal", solidCoral = "solid-coral"
    case solidNavyLight = "solid-navy-light", solidNavy = "solid-navy", solidNavyDeep = "solid-navy-deep"
    case whiteBlue = "white-blue", whiteTeal = "white-teal", whiteCoral = "white-coral", whiteNavy = "white-navy"

    var onWhite: Bool { rawValue.hasPrefix("white-") }

    /// The hue as a top-to-bottom pair: the body's gradient, or the mark's on white.
    var hue: (top: UInt32, bottom: UInt32) {
        switch self {
        case .solidBlue, .whiteBlue: return (0x2E8BFF, 0x0058D6)   // the connect screen's accent, 0x006BED
        case .solidTeal, .whiteTeal: return (0x22B8B0, 0x0A827E)
        case .solidCoral, .whiteCoral: return (0xFF8C6E, 0xEA5645)
        case .solidNavyLight: return (0x5476C4, 0x2C4A94)
        case .solidNavy, .whiteNavy: return (0x30498C, 0x152049)
        case .solidNavyDeep: return (0x1E2B55, 0x080E26)
        }
    }

    func draw(_ ctx: CGContext, pixels: Int) {
        let (top, bottom) = hue
        let background = onWhite ? grad([rgb(0xFFFFFF), rgb(0xECEFF3)]) : grad([rgb(top), rgb(bottom)])
        let base = onWhite ? rgb(0xC9CFD8) : rgb(bottom)
        frame(ctx, pixels: pixels, base: base, background: background,
              sheen: onWhite ? 0 : 0.14, rim: onWhite ? 0.6 : 0.2) { ctx, small, _ in
            let mark = minimalMark(small: small)
            scaled(ctx, small ? 1.02 : 0.92, about: CGPoint(x: 512, y: 512)) {
                ctx.saveGState()
                shadow(ctx, dy: -6, blur: 16, color: rgb(onWhite ? bottom : 0x000000, onWhite ? 0.22 : 0.2))
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                let ink = rgb(0xFFFFFF)
                ctx.setFillColor(ink); ctx.setStrokeColor(ink)
                ctx.setLineJoin(.round); ctx.setLineCap(.round)
                // Fill and stroke together to round the corners a little.
                ctx.setLineWidth(mark.corner)
                for path in [mark.sails, mark.mast, mark.hull] { ctx.addPath(path); ctx.drawPath(using: .fillStroke) }
                ctx.setLineWidth(mark.waveWidth)
                ctx.addPath(mark.wave); ctx.strokePath()
                if onWhite {
                    // Colour the mark with the hue's gradient.
                    ctx.setBlendMode(.sourceIn)
                    ctx.drawLinearGradient(grad([rgb(top), rgb(bottom)]), start: CGPoint(x: 0, y: 800), end: CGPoint(x: 0, y: 220),
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                }
                ctx.endTransparencyLayer()
                ctx.restoreGState()
            }
        }
    }
}

// MARK: - Variants

enum Variant: String, CaseIterable {
    case origami, sailboat, night, sunset

    func draw(_ ctx: CGContext, pixels: Int) {
        switch self {
        case .origami: drawOrigami(ctx, pixels: pixels)
        case .sailboat: drawSailboat(ctx, pixels: pixels)
        case .night: drawNight(ctx, pixels: pixels)
        case .sunset: drawSunset(ctx, pixels: pixels)
        }
    }
}

// MARK: - Rendering

func render(_ variant: Variant, pixels: Int) -> NSBitmapImageRep {
    render(pixels: pixels) { variant.draw($0, pixels: pixels) }
}

func render(pixels: Int, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = graphics.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    draw(ctx)
    graphics.flushGraphics()
    return rep.retagging(with: .sRGB)!
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Contact sheet

/// One row per variant (origami first), each at 16, 32, 128 and 512 pixels on
/// a light panel and on a dark panel.
func sheet(to url: URL) throws {
    let sizes = [16, 32, 128, 512]
    let gap = 28
    let labelW = 220
    let panelW = sizes.reduce(0, +) + gap * (sizes.count + 1)
    let rowH = 512 + gap * 2
    let width = labelW + panelW * 2
    let height = rowH * Variant.allCases.count
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let backgrounds = [NSColor(white: 0.94, alpha: 1), NSColor(white: 0.11, alpha: 1)]
    for (row, variant) in Variant.allCases.enumerated() {
        let y = height - rowH * (row + 1)
        NSColor(white: 0.985, alpha: 1).setFill()
        NSRect(x: 0, y: y, width: labelW, height: rowH).fill()
        NSAttributedString(string: variant.rawValue, attributes: [
            .font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor(white: 0.1, alpha: 1),
        ]).draw(at: NSPoint(x: 24, y: y + rowH - 72))
        for (panel, background) in backgrounds.enumerated() {
            let x0 = labelW + panelW * panel
            background.setFill()
            NSRect(x: x0, y: y, width: panelW, height: rowH).fill()
            var x = x0 + gap
            for size in sizes {
                let icon = NSImage(size: NSSize(width: size, height: size))
                icon.addRepresentation(render(variant, pixels: size))
                icon.draw(in: NSRect(x: x, y: y + gap + (512 - size) / 2, width: size, height: size))
                x += size + gap
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try writePNG(rep, to: url)
}

// MARK: - Exploration

/// Writes a 512-pixel PNG of each minimal variant into `dir`, and
/// `comparison.png`: a row with the maintainer's reference shots (when `dir`
/// has them) beside the mark, then every variant at 512 and 32, a row per
/// family, on a light panel and then on a dark one.
func exploration(to dir: URL) throws {
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for m in Minimal.allCases {
        try writePNG(render(pixels: 512) { m.draw($0, pixels: 512) }, to: dir.appendingPathComponent("\(m.rawValue).png"))
    }

    let families = [Minimal.allCases.filter { !$0.onWhite }, Minimal.allCases.filter(\.onWhite)]
    let columns = families.map(\.count).max()!
    let gap = 40, small = 32, label = 44
    let cellW = 512, rowH = gap + 512 + 20 + small + 12 + label
    let width = gap + (cellW + gap) * columns
    let panelH = rowH * families.count + gap
    let references = ["reference-connect-badge", "reference-menu-bar"].compactMap { name in
        NSImage(contentsOf: dir.appendingPathComponent("\(name).png")).map { (name, $0) }
    }
    let refH = references.isEmpty ? 0 : gap + 400 + 12 + label + gap
    let height = refH + panelH * 2
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.imageInterpolation = .high

    func caption(_ s: String, centredIn x: Int, width w: Int, y: Int, color: NSColor) {
        let t = NSAttributedString(string: s, attributes: [.font: NSFont.systemFont(ofSize: 26, weight: .semibold), .foregroundColor: color])
        t.draw(at: NSPoint(x: x + (w - Int(t.size().width)) / 2, y: y))
    }

    if !references.isEmpty {
        // The references (enlarged screenshots) beside the mark in blue and in navy, all 400 tall.
        NSColor(white: 0.16, alpha: 1).setFill()
        NSRect(x: 0, y: height - refH, width: width, height: refH).fill()
        var x = gap
        let imageY = height - gap - 400
        let light = NSColor(white: 0.88, alpha: 1)
        for (name, image) in references {
            let w = Int(400 * image.size.width / image.size.height)
            image.draw(in: NSRect(x: x, y: imageY, width: w, height: 400))
            caption(name, centredIn: x, width: w, y: imageY - 12 - 32, color: light)
            x += w + gap
        }
        for m in [Minimal.solidBlue, .solidNavy] {
            let icon = NSImage(size: NSSize(width: 400, height: 400))
            icon.addRepresentation(render(pixels: 400) { m.draw($0, pixels: 400) })
            icon.draw(in: NSRect(x: x, y: imageY, width: 400, height: 400))
            caption("\(m.rawValue) (ours)", centredIn: x, width: 400, y: imageY - 12 - 32, color: light)
            x += 400 + gap
        }
    }

    let panels = [NSColor(white: 0.94, alpha: 1), NSColor(white: 0.11, alpha: 1)]
    for (p, panel) in panels.enumerated() {
        let panelTop = height - refH - panelH * p
        panel.setFill()
        NSRect(x: 0, y: panelTop - panelH, width: width, height: panelH).fill()
        let text = p == 0 ? NSColor(white: 0.15, alpha: 1) : NSColor(white: 0.88, alpha: 1)
        for (f, family) in families.enumerated() {
            let rowTop = panelTop - rowH * f
            for (c, m) in family.enumerated() {
                let x = gap + (cellW + gap) * c
                let big = NSImage(size: NSSize(width: 512, height: 512))
                big.addRepresentation(render(pixels: 512) { m.draw($0, pixels: 512) })
                big.draw(in: NSRect(x: x, y: rowTop - gap - 512, width: 512, height: 512))
                let tiny = NSImage(size: NSSize(width: small, height: small))
                tiny.addRepresentation(render(pixels: small) { m.draw($0, pixels: small) })
                let smallY = rowTop - gap - 512 - 20 - small
                tiny.draw(in: NSRect(x: x + (cellW - small) / 2, y: smallY, width: small, height: small))
                caption(m.rawValue, centredIn: x, width: cellW, y: smallY - 12 - 32, color: text)
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try writePNG(rep, to: dir.appendingPathComponent("comparison.png"))
}

// MARK: - Main

func fail(_ message: String) -> Never {
    FileHandle.standardError.write("\(message)\nusage: make-icon.swift <out.iconset> [--variant \(Variant.allCases.map(\.rawValue).joined(separator: "|"))] | --sheet <out.png>\n".data(using: .utf8)!)
    exit(64)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var variant = Variant.origami
if let flag = arguments.firstIndex(of: "--variant") {
    guard flag + 1 < arguments.count else { fail("--variant needs a name") }
    guard let chosen = Variant(rawValue: arguments[flag + 1]) else { fail("unknown variant \(arguments[flag + 1])") }
    variant = chosen
    arguments.removeSubrange(flag...flag + 1)
}

if arguments.count == 2, arguments[0] == "--exploration" {
    try exploration(to: URL(fileURLWithPath: arguments[1], isDirectory: true))
} else if arguments.count == 2, arguments[0] == "--sheet" {
    try sheet(to: URL(fileURLWithPath: arguments[1]))
} else if arguments.count == 1 {
    let iconset = URL(fileURLWithPath: arguments[0], isDirectory: true)
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        try writePNG(render(variant, pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
        try writePNG(render(variant, pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }
} else {
    fail("wrong arguments")
}
