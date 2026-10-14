import AppKit
import Foundation
@testable import ShipyardApp
import SwiftUI
import Testing

@Suite("Sailboat")
struct SailboatTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("the menu bar item fills the sailboat path, fitted to its square")
    func menuBarPath() {
        let side = SailboatImage.menuBarSide
        #expect(SailboatImage.menuBarPath() == Sailboat.path(in: CGRect(x: 0, y: 0, width: side, height: side)))
        let box = SailboatImage.menuBarPath().boundingBoxOfPath
        #expect(abs(box.height - side) < 0.001)
        #expect(abs(box.midX - side / 2) < 0.001)
        let icon = Sailboat.bounds
        #expect(abs(box.width / box.height - icon.width / icon.height) < 0.001)
    }

    @Test("the menu bar image is a template, and its pixels are the sailboat path's")
    func menuBarImage() throws {
        let image = SailboatImage.menuBar()
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: SailboatImage.menuBarSide, height: SailboatImage.menuBarSide))

        let scale: CGFloat = 8
        let pixels = Int(SailboatImage.menuBarSide * scale)
        let rep = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()

        var inked = CGRect.null
        for y in 0..<pixels {
            for x in 0..<pixels where rep.colorAt(x: x, y: y)!.alphaComponent > 0.5 {
                inked = inked.union(CGRect(x: x, y: pixels - 1 - y, width: 1, height: 1))
            }
        }
        let path = SailboatImage.menuBarPath().boundingBoxOfPath
        let expected = CGRect(x: path.minX * scale, y: path.minY * scale, width: path.width * scale, height: path.height * scale)
        #expect(abs(inked.minX - expected.minX) <= 1.5)
        #expect(abs(inked.maxX - expected.maxX) <= 1.5)
        #expect(abs(inked.minY - expected.minY) <= 1.5)
        #expect(abs(inked.maxY - expected.maxY) <= 1.5)
    }

    @Test("the icon script is compiled with the app's sailboat and logo, and draws them")
    func iconSharesThePath() throws {
        let makefile = try String(contentsOf: Self.root.appendingPathComponent("Makefile"), encoding: .utf8)
        #expect(makefile.contains("BRAND       := Sources/ShipyardApp/Brand/Sailboat.swift Sources/ShipyardApp/Brand/Logo.swift"))
        #expect(makefile.contains("swiftc -o $@ $(dir $@)main.swift $(BRAND)"))
        #expect(makefile.contains("ICON        ?= graphite"))
        let script = try String(contentsOf: Self.root.appendingPathComponent("Packaging/Icon/make-icon.swift"), encoding: .utf8)
        #expect(script.contains("Sailboat.path"))
        #expect(script.contains("hue: (top: UInt32, bottom: UInt32) = (Logo.top, Logo.bottom)"))
        #expect(script.contains("Logo.figurePath"))
        #expect(script.contains("Logo.foldsPath"))
        #expect(script.contains("Logo.rims"))
        #expect(!script.contains("enum Sailboat"))
        #expect(!script.contains("enum Logo"))
    }

    @Test("the badge's figure is the logo's, flipped for SwiftUI")
    func badgeFigure() {
        let rect = CGRect(x: 0, y: 0, width: 32, height: 32)
        let shape = LogoShape.figure.path(in: rect).boundingRect
        let path = Logo.figurePath(inBody: rect).boundingBoxOfPath
        #expect(abs(shape.width - path.width) < 0.001)
        #expect(abs(shape.height - path.height) < 0.001)
        #expect(abs(shape.midX - path.midX) < 0.001)
        #expect(abs(shape.midY - (rect.height - path.midY)) < 0.001)
    }

    private static let iconBody = CGRect(x: 100, y: 100, width: 824, height: 824)
    private static let backgroundSpot = CGPoint(x: 160, y: 300)
    private static let sailSpot = CGPoint(x: 640, y: 600)
    private static let foldSpot = CGPoint(x: 540, y: 600)

    @Test("the app icon and the welcome screens' badge show the same colours")
    @MainActor
    func iconAndBadgeColours() throws {
        #expect(Sailboat.path.contains(Self.sailSpot))
        #expect(!Logo.folds.contains(Self.sailSpot))
        #expect(Logo.folds.contains(Self.foldSpot))
        let icns = try #require(NSImage(contentsOf: Self.root.appendingPathComponent("Packaging/Icon/AppIcon.icns")))
        let icon = try #require(icns.representations.compactMap { $0 as? NSBitmapImageRep }.first { $0.pixelsWide == 512 })
        func iconColour(_ p: CGPoint) -> NSColor {
            icon.colorAt(x: Int(p.x / 2), y: 511 - Int(p.y / 2))!.usingColorSpace(.sRGB)!
        }
        let side = Self.iconBody.width
        let renderer = ImageRenderer(content: LogoBadge(side: side))
        renderer.scale = 1
        let badge = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        func badgeColour(_ p: CGPoint) -> NSColor {
            badge.colorAt(x: Int(p.x), y: Int(p.y))!.usingColorSpace(.sRGB)!
        }

        // The same body colour, the same white figure and the same shaded fold, spot for spot. Both
        // go through the same colour management, so they're compared with
        // each other rather than with the raw hex values.
        let inBadgeBody = CGPoint(x: Self.backgroundSpot.x - Self.iconBody.minX, y: Self.iconBody.maxY - Self.backgroundSpot.y)
        let inIcon = Self.sailSpot.applying(Logo.figureTransform(inBody: Self.iconBody))
        let inBadge = Self.sailSpot.applying(Logo.figureTransform(inBody: CGRect(x: 0, y: 0, width: side, height: side), yDown: true))
        let iconBody = iconColour(Self.backgroundSpot), badgeBody = badgeColour(inBadgeBody)
        let iconFigure = iconColour(inIcon), badgeFigure = badgeColour(inBadge)
        let foldInIcon = Self.foldSpot.applying(Logo.figureTransform(inBody: Self.iconBody))
        let foldInBadge = Self.foldSpot.applying(Logo.figureTransform(inBody: CGRect(x: 0, y: 0, width: side, height: side), yDown: true))
        let iconFold = iconColour(foldInIcon), badgeFold = badgeColour(foldInBadge)
        #expect(Self.near(iconBody, badgeBody))
        #expect(Self.near(iconFigure, badgeFigure))
        #expect(Self.near(iconFold, badgeFold))
        #expect(badgeBody.greenComponent < 0.25)
        #expect(abs(badgeBody.greenComponent - badgeBody.redComponent) < 0.03 && abs(badgeBody.blueComponent - badgeBody.greenComponent) < 0.03)
        #expect(badgeFigure.redComponent > 0.95 && badgeFigure.greenComponent > 0.95 && badgeFigure.blueComponent > 0.95)
        #expect(badgeFold.greenComponent > 0.6 && badgeFold.greenComponent < badgeFigure.greenComponent - 0.1)
    }

    private static func near(_ a: NSColor, _ b: NSColor) -> Bool {
        abs(a.redComponent - b.redComponent) <= 4 / 255
            && abs(a.greenComponent - b.greenComponent) <= 4 / 255
            && abs(a.blueComponent - b.blueComponent) <= 4 / 255
    }
}
