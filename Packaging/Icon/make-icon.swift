// Draws Shipyard's app icon: the menu bar's sailboat on a sea-blue squircle.
//
//   swift Packaging/Icon/make-icon.swift <out.iconset>        every size an .iconset needs
//   swift Packaging/Icon/make-icon.swift --sheet <out.png>    a contact sheet for review
//
// Command Line Tools only (AppKit and CoreGraphics). `make icon` runs it and
// packs the iconset with `iconutil -c icns` into Packaging/Icon/AppIcon.icns.
//
// Everything is drawn on the 1024-point macOS 11+ icon grid (an 824-point body
// with a drop shadow) and rendered at each pixel size as vectors. Below 64
// pixels the boat grows and the fine detail goes, so it still reads at 16.

import AppKit

// MARK: - Palette

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

let skyTop = rgb(0x4DB5F5)
let skyBottom = rgb(0x1466D2)
let seaTop = rgb(0x0E4FA8)
let seaBottom = rgb(0x082C6B)
let sailLight = rgb(0xFFFFFF)
let sailShade = rgb(0xDCE9F7)
let hullTop = rgb(0xFF9A4D)
let hullBottom = rgb(0xE2531C)
let mastColor = rgb(0x0B2F66)

// MARK: - Shapes (1024 grid, y up)

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

/// The sea's top edge: a gentle swell across the body.
func sea(body: CGRect, level: CGFloat, amplitude: CGFloat, waves: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: body.minX - 10, y: body.minY - 10))
    let steps = 200
    for i in 0...steps {
        let x = body.minX - 10 + (body.width + 20) * CGFloat(i) / CGFloat(steps)
        let phase = (x - body.minX) / body.width * waves * 2 * .pi
        path.addLine(to: CGPoint(x: x, y: level + amplitude * sin(phase + 0.6)))
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

// MARK: - Drawing

func linear(_ ctx: CGContext, _ top: CGColor, _ bottom: CGColor, from y0: CGFloat, to y1: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: y0), end: CGPoint(x: 0, y: y1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func fill(_ ctx: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor, from y0: CGFloat, to y1: CGFloat) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    linear(ctx, top, bottom, from: y0, to: y1)
    ctx.restoreGState()
}

/// Shadows ignore the transform, so they're given on the 1024 grid and scaled here.
func shadow(_ ctx: CGContext, dy: CGFloat, blur: CGFloat, color: CGColor) {
    let scale = ctx.ctm.a
    ctx.setShadow(offset: CGSize(width: 0, height: dy * scale), blur: blur * scale, color: color)
}

/// Draws the icon on the 1024 grid; `pixels` is the size it ends up at.
func drawIcon(_ ctx: CGContext, pixels: Int) {
    let small = pixels < 64
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = squircle(in: body)

    // Drop shadow under the body, as on the macOS grid.
    ctx.saveGState()
    shadow(ctx, dy: -10, blur: 22, color: rgb(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(skyBottom)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()

    // Sky.
    linear(ctx, skyTop, skyBottom, from: body.maxY, to: body.minY + 240)

    // Small sizes: a bigger boat on the same background.
    let boatScale: CGFloat = small ? 1.22 : 1
    ctx.saveGState()
    ctx.translateBy(x: 512, y: 560)
    ctx.scaleBy(x: boatScale, y: boatScale)
    ctx.translateBy(x: -512, y: -560)
    let b = boat()

    // Sails and mast, with a soft shadow for depth.
    ctx.saveGState()
    shadow(ctx, dy: -8, blur: 18, color: rgb(0x06285C, 0.35))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(b.mast)
    ctx.setFillColor(mastColor)
    ctx.fillPath()
    fill(ctx, b.jib, sailLight, sailShade, from: 760, to: 392)
    fill(ctx, b.main, sailLight, sailShade, from: 812, to: 392)
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // A shaded strip along each sail's mast edge: the cloth's curve.
    if !small {
        ctx.saveGState()
        ctx.addPath(b.main)
        ctx.clip()
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [rgb(0x9DB8DA, 0.45), rgb(0x9DB8DA, 0)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 542, y: 0), end: CGPoint(x: 640, y: 0), options: [])
        ctx.restoreGState()
    }

    // Hull.
    ctx.saveGState()
    shadow(ctx, dy: -6, blur: 14, color: rgb(0x06285C, 0.4))
    fill(ctx, b.hull, hullTop, hullBottom, from: 358, to: 250)
    ctx.restoreGState()
    if !small {
        // A light rail along the deck.
        ctx.saveGState()
        ctx.addPath(b.hull)
        ctx.clip()
        ctx.setFillColor(rgb(0xFFFFFF, 0.28))
        ctx.fill(CGRect(x: 0, y: 340, width: 1024, height: 18))
        ctx.restoreGState()
    }
    ctx.restoreGState()

    // Sea, in front of the hull's keel.
    let seaLevel: CGFloat = small ? 222 : 282
    fill(ctx, sea(body: body, level: seaLevel, amplitude: small ? 10 : 14, waves: 2.5),
         seaTop, seaBottom, from: seaLevel + 14, to: body.minY)
    if !small {
        // A crest line on the second swell.
        ctx.saveGState()
        ctx.addPath(sea(body: body, level: 206, amplitude: 12, waves: 3.5))
        ctx.setFillColor(rgb(0x000000, 0.14))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.35))
        ctx.setLineWidth(6)
        ctx.setLineCap(.round)
        let crest = CGMutablePath()
        for i in 0...100 {
            let x = body.minX + body.width * CGFloat(i) / 100
            let phase = (x - body.minX) / body.width * 2.5 * 2 * .pi
            let p = CGPoint(x: x, y: seaLevel + 14 * sin(phase + 0.6))
            i == 0 ? crest.move(to: p) : crest.addLine(to: p)
        }
        ctx.addPath(crest)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // Light from above: a sheen on the top half and a thin bright rim.
    let sheen = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                           colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY), options: [])
    ctx.restoreGState()

    if !small {
        ctx.saveGState()
        ctx.addPath(shape)
        ctx.clip()
        ctx.addPath(shape)
        ctx.setStrokeColor(rgb(0xFFFFFF, 0.25))
        ctx.setLineWidth(4)
        ctx.strokePath()
        ctx.restoreGState()
    }
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let ctx = graphics.cgContext
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(ctx, pixels: pixels)
    graphics.flushGraphics()
    return rep.retagging(with: .sRGB)!
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

// MARK: - Contact sheet

/// Each size at 1x, on a light row and on a dark row; then 16 and 32 blown up
/// 8x (pixels kept square), on light and on dark, to judge the smallest sizes.
func sheet(to url: URL) throws {
    let sizes = [16, 32, 64, 128, 256, 512]
    let gap = 32
    let width = sizes.reduce(0, +) + gap * (sizes.count + 1)
    let rowHeight = 512 + gap * 2
    let zoomHeight = 32 * 8 + gap * 2
    let height = rowHeight * 2 + zoomHeight
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let backgrounds = [NSColor(white: 0.93, alpha: 1), NSColor(white: 0.12, alpha: 1)]
    for (row, background) in backgrounds.enumerated() {
        let y = height - rowHeight * (row + 1)
        background.setFill()
        NSRect(x: 0, y: y, width: width, height: rowHeight).fill()
        var x = gap
        for size in sizes {
            let icon = NSImage(size: NSSize(width: size, height: size))
            icon.addRepresentation(render(pixels: size))
            icon.draw(in: NSRect(x: x, y: y + gap, width: size, height: size))
            x += size + gap
        }
    }
    NSGraphicsContext.current?.imageInterpolation = .none
    var x = gap
    for background in backgrounds {
        background.setFill()
        NSRect(x: x - gap, y: 0, width: width / 2, height: zoomHeight).fill()
        for size in [16, 32] {
            let icon = NSImage(size: NSSize(width: size, height: size))
            icon.addRepresentation(render(pixels: size))
            icon.draw(in: NSRect(x: x, y: gap, width: size * 8, height: size * 8))
            x += size * 8 + gap
        }
        x = width / 2 + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    try writePNG(rep, to: url)
}

// MARK: - Main

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count == 2, arguments[0] == "--sheet" {
    try sheet(to: URL(fileURLWithPath: arguments[1]))
} else if arguments.count == 1 {
    let iconset = URL(fileURLWithPath: arguments[0], isDirectory: true)
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        try writePNG(render(pixels: points), to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
        try writePNG(render(pixels: points * 2), to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }
} else {
    FileHandle.standardError.write("usage: make-icon.swift <out.iconset> | --sheet <out.png>\n".data(using: .utf8)!)
    exit(64)
}
