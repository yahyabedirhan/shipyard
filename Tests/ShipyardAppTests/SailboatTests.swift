import AppKit
import Foundation
@testable import ShipyardApp
import SwiftUI
import Testing

/// The app icon, the menu bar item and the connect screen's badge are one figure:
/// `Sailboat.path`, drawn by the app and compiled into the icon script.
@Suite("Sailboat")
struct SailboatTests {
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test("the menu bar item fills the sailboat path, fitted to its square")
    func menuBarPath() {
        let side = SailboatImage.menuBarSide
        #expect(SailboatImage.menuBarPath() == Sailboat.path(in: CGRect(x: 0, y: 0, width: side, height: side)))
        // Fitted: the figure's height fills the square and it's centred across.
        let box = SailboatImage.menuBarPath().boundingBoxOfPath
        #expect(abs(box.height - side) < 0.001)
        #expect(abs(box.midX - side / 2) < 0.001)
        // The same shape as the icon's, only scaled.
        let icon = Sailboat.bounds
        #expect(abs(box.width / box.height - icon.width / icon.height) < 0.001)
    }

    @Test("the menu bar image is a template, and its pixels are the sailboat path's")
    func menuBarImage() throws {
        let image = SailboatImage.menuBar()
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: SailboatImage.menuBarSide, height: SailboatImage.menuBarSide))

        // Rendered at 8 pixels to the point, the inked pixels span the path's bounds.
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
                // colorAt counts rows from the top; the path's y runs up.
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

    @Test("the badge's shape is the same path, flipped for SwiftUI")
    func badge() {
        let rect = CGRect(x: 0, y: 0, width: 18, height: 18)
        let shape = SailboatShape().path(in: rect).boundingRect
        let path = Sailboat.path(in: rect).boundingBoxOfPath
        #expect(abs(shape.width - path.width) < 0.001)
        #expect(abs(shape.height - path.height) < 0.001)
        #expect(abs(shape.midX - path.midX) < 0.001)
    }

    @Test("the icon script is compiled with the app's sailboat file and draws its path")
    func iconSharesThePath() throws {
        let makefile = try String(contentsOf: Self.root.appendingPathComponent("Makefile"), encoding: .utf8)
        #expect(makefile.contains("SAILBOAT    := Sources/ShipyardApp/Brand/Sailboat.swift"))
        #expect(makefile.contains("swiftc -o $@ $(dir $@)main.swift $(SAILBOAT)"))
        let script = try String(contentsOf: Self.root.appendingPathComponent("Packaging/Icon/make-icon.swift"), encoding: .utf8)
        #expect(script.contains("Sailboat.path"))
        #expect(!script.contains("enum Sailboat"))
    }
}
