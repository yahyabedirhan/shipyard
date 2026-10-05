import AppKit
import Foundation
@testable import ShipyardApp
import ShipyardCore
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

    /// Whether the lease's indicator was hidden each time a fresh panel was drawn.
    final class DrawnPanels {
        var hidden: [Bool] = []
    }

    /// How many of the image's pixels are the lease dot's yellow.
    func yellow(_ image: CGImage) throws -> Int {
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try #require(CGContext(
            data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return stride(from: 0, to: pixels.count, by: 4).filter { start in
            pixels[start + 3] > 200 && pixels[start] > 200 && pixels[start + 1] > 150 && pixels[start + 2] < 90
        }.count
    }

    @Test("the menu bar icon carries the lease's yellow dot only when asked, the sailboat still tinted for the appearance")
    func menuBarIconWithLeaseDot() async throws {
        let plain = try #require(await ScreenshotImage.menuBarIcon(appearance: ScreenshotImage.appearance(.light)))
        let light = try #require(await ScreenshotImage.menuBarIcon(appearance: ScreenshotImage.appearance(.light), leaseDot: true))
        let dark = try #require(await ScreenshotImage.menuBarIcon(appearance: ScreenshotImage.appearance(.dark), leaseDot: true))

        #expect(try yellow(plain) == 0)
        #expect(try yellow(light) > 0)
        #expect(try yellow(dark) > 0)
        #expect(light.width > plain.width)
    }

    @Test("a closed panel is rendered, never opened; without --with-indicator, with the lease's dot and banner hidden, and they come back afterwards")
    func fallbackHidesTheIndicator() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shipyard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        // The screenshotter sets the app's appearance, so the app object has to exist.
        _ = NSApplication.shared
        // The panel is closed, so the screenshot renders a fresh one rather than opening it.
        let panel = ControlServerTests.FakePanel()
        panel.isOpen = false
        let indicator = LeaseIndicator()
        let drawn = DrawnPanels()
        let screenshotter = Screenshotter(panel: panel, indicator: indicator) {
            drawn.hidden.append(indicator.isHiddenForCapture)
            return AnyView(Color.gray.frame(width: 20, height: 20))
        }
        let file = folder.appendingPathComponent("panel.png")

        let without = await screenshotter.capturePanel(to: file, appearance: .light, withIndicator: false)
        let hiddenAfter = indicator.isHiddenForCapture
        let with = await screenshotter.capturePanel(to: file, appearance: .light, withIndicator: true)

        #expect(without == .rendered(why: "the panel is closed"))
        #expect(with == .rendered(why: "the panel is closed"))
        #expect(panel.calls.isEmpty)
        #expect(drawn.hidden == [true, false])
        #expect(!hiddenAfter)
        #expect(!indicator.isHiddenForCapture)
    }

    @Test("overlapping captures without --with-indicator each hide the dot and the banner, and they come back once both have ended")
    func overlappingCapturesShowTheIndicatorAfterwards() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shipyard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = NSApplication.shared
        let panel = ControlServerTests.FakePanel()
        panel.isOpen = false
        let indicator = LeaseIndicator()
        let drawn = DrawnPanels()
        let screenshotter = Screenshotter(panel: panel, indicator: indicator) {
            drawn.hidden.append(indicator.isHiddenForCapture)
            return AnyView(Color.gray.frame(width: 20, height: 20))
        }

        // Both are under way at once: each waits while its fallback settles.
        async let first = screenshotter.capturePanel(to: folder.appendingPathComponent("first.png"), appearance: .light, withIndicator: false)
        async let second = screenshotter.capturePanel(to: folder.appendingPathComponent("second.png"), appearance: .light, withIndicator: false)
        let outcomes = await [first, second]

        #expect(outcomes == Array(repeating: .rendered(why: "the panel is closed"), count: 2))
        #expect(drawn.hidden == [true, true])
        #expect(!indicator.isHiddenForCapture)
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
