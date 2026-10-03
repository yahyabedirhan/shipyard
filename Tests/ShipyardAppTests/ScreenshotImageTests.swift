import AppKit
import Foundation
@testable import ShipyardApp
import SwiftUI
import Testing

/// The screenshot's fallback, drawn in this process without a window or
/// the screen: a view rendered in the appearance asked for, the menu bar
/// icon as the menu bar tints it, and the PNG written where asked.
@Suite("Screenshot rendering")
@MainActor
struct ScreenshotImageTests {
    /// The mean brightness (0 to 1) of the image's opaque pixels, and how
    /// many there are.
    func opaque(_ image: CGImage) throws -> (brightness: Double, count: Int) {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var total = 0.0, count = 0
        for start in stride(from: 0, to: pixels.count, by: 4) where pixels[start + 3] > 200 {
            total += (Double(pixels[start]) + Double(pixels[start + 1]) + Double(pixels[start + 2])) / (3 * 255)
            count += 1
        }
        return (count == 0 ? 0 : total / Double(count), count)
    }

    @Test("a view renders in the appearance asked for: the text colour is dark in light, light in dark")
    func appearance() throws {
        let swatch = AnyView(Color(nsColor: .textColor).frame(width: 40, height: 20))

        let light = try #require(ScreenshotImage.render(swatch, appearance: ScreenshotImage.appearance(.light)))
        let dark = try #require(ScreenshotImage.render(swatch, appearance: ScreenshotImage.appearance(.dark)))

        #expect(try opaque(light).brightness < 0.3)
        #expect(try opaque(dark).brightness > 0.7)
        #expect(light.width == dark.width && light.width >= 40)
    }

    @Test("the menu bar icon is the menu bar's size, dark in light and white in dark")
    func menuBarIcon() throws {
        let light = try #require(ScreenshotImage.menuBarIcon(appearance: ScreenshotImage.appearance(.light)))
        let dark = try #require(ScreenshotImage.menuBarIcon(appearance: ScreenshotImage.appearance(.dark)))

        let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
        #expect(light.width == Int(SailboatImage.menuBarSide) * scale)
        #expect(try opaque(light).count > 0)
        #expect(try opaque(light).brightness < 0.3)
        #expect(try opaque(dark).brightness > 0.7)
    }

    @Test("the image is written as a PNG at the path; a folder that doesn't exist is refused with the path")
    func write() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shipyard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try #require(ScreenshotImage.menuBarIcon(appearance: ScreenshotImage.appearance(.light)))
        let file = folder.appendingPathComponent("icon.png")

        try ScreenshotImage.write(image, to: file)

        let data = try Data(contentsOf: file)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(NSImage(data: data) != nil)
        let missing = folder.appendingPathComponent("nowhere/icon.png")
        let refusal = #expect(throws: ScreenshotFailure.self) { try ScreenshotImage.write(image, to: missing) }
        #expect(refusal?.why.contains(missing.path) == true)
    }
}
