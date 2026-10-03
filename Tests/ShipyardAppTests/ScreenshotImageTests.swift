import AppKit
import Foundation
@testable import ShipyardApp
import SwiftUI
import Testing

/// The screenshot's fallback, drawn in this process in an invisible
/// window off screen: a view rendered in the appearance asked for, the menu bar
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

    @Test("a panel renders in the appearance asked for, on an opaque window background: never light text on transparency")
    func appearance() async throws {
        // A text-coloured swatch on nothing, as the panel's rows sit on the window's material.
        let swatch = AnyView(Color(nsColor: .textColor).frame(width: 20, height: 20).padding(10))

        let light = try #require(await ScreenshotImage.render(swatch, appearance: ScreenshotImage.appearance(.light), opaque: true))
        let dark = try #require(await ScreenshotImage.render(swatch, appearance: ScreenshotImage.appearance(.dark), opaque: true))

        for image in [light, dark] {
            #expect(try opaque(image).count == image.width * image.height)
            #expect(image.width >= 40)
        }
        #expect(try brightness(light, atX: light.width / 2) < 0.3)
        #expect(try brightness(light, atX: 1) > 0.7)
        #expect(try brightness(dark, atX: dark.width / 2) > 0.7)
        #expect(try brightness(dark, atX: 1) < 0.3)
    }

    /// The brightness (0 to 1) of the pixel at `x` on the image's middle row.
    func brightness(_ image: CGImage, atX x: Int) throws -> Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -x, y: -image.height / 2, width: image.width, height: image.height))
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }

    @Test("the menu bar icon is the menu bar's size, dark in light and white in dark")
    func menuBarIcon() async throws {
        let light = try #require(await ScreenshotImage.menuBarIcon(appearance: ScreenshotImage.appearance(.light)))
        let dark = try #require(await ScreenshotImage.menuBarIcon(appearance: ScreenshotImage.appearance(.dark)))

        let scale = Int(NSScreen.main?.backingScaleFactor ?? 2)
        #expect(light.width == Int(SailboatImage.menuBarSide) * scale)
        #expect(try opaque(light).count > 0)
        #expect(try opaque(light).brightness < 0.3)
        #expect(try opaque(dark).brightness > 0.7)
    }

    @Test("the image is written as a PNG at the path; a folder that doesn't exist is refused with the path")
    func write() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shipyard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try #require(await ScreenshotImage.menuBarIcon(appearance: ScreenshotImage.appearance(.light)))
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
