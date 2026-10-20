import AppKit
@testable import ShipyardApp
import Testing

@Suite("Symbol images")
struct SymbolImageTests {
    @Test("a tinted symbol isn't a template and draws its ink in the colour given, so a system menu shows the theme's colour")
    func tinted() throws {
        let color = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let image = SymbolImage.tinted("gearshape", color)
        #expect(!image.isTemplate)
        #expect(image.size.width > 0)

        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: bitmap.pixelsWide, height: bitmap.pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()

        let ink = (0..<bitmap.pixelsWide).flatMap { x in (0..<bitmap.pixelsHigh).map { (x, $0) } }
            .compactMap { bitmap.colorAt(x: $0.0, y: $0.1) }
            .filter { $0.alphaComponent > 0.99 }
        #expect(!ink.isEmpty)
        for pixel in ink {
            let srgb = try #require(pixel.usingColorSpace(.sRGB))
            #expect(srgb.redComponent > 0.9 && srgb.greenComponent < 0.1 && srgb.blueComponent < 0.1)
        }
    }
}
