import ShipyardConfig
import ShipyardCore
@testable import ShipyardApp
import SwiftUI
import Testing

@Suite("Row highlight: the layer behind a list's rows")
@MainActor
struct RowHighlightLayerTests {
    /// A theme whose row highlight is opaque red on a white panel, so a
    /// lit row reads as red pixels.
    private static let theme = Theme(name: "Test") { token, _ in
        switch token {
        case .rowHover: .color(RGBA(r: 1, g: 0, b: 0))
        case .panel: .color(RGBA(r: 1, g: 1, b: 1))
        default: .system
        }
    }

    private static let place = MenuRowPlace(section: "harbor", row: "pull-1")

    /// The red share of the pixel at the row's middle.
    private func middle(_ view: some View) throws -> (red: Double, green: Double) {
        let renderer = ImageRenderer(content: view
            .frame(width: 200, height: 22)
            .background(ThemeColor.panel)
            .environment(\.theme, Self.theme)
            .environment(\.colorScheme, .light))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let context = try #require(CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -100, y: -11, width: image.width, height: image.height))
        let pixel = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
        return (Double(pixel[0]) / 255, Double(pixel[1]) / 255)
    }

    private func layer(_ highlight: RowHighlight) -> some View {
        HighlightLayer(highlight: .constant(highlight), list: AnyHashable("tab")) {
            Color.clear.frame(width: 200, height: 22)
                .highlightable(Self.place, .constant(highlight))
        }
    }

    @Test("a row composed into a tab's layer is lit, though it wasn't tagged with the tab")
    func untaggedRowInTaggedLayer() throws {
        let unlit = try middle(layer(RowHighlight()))
        #expect(unlit.red > 0.9 && unlit.green > 0.9)
        let lit = try middle(layer(RowHighlight(place: Self.place)))
        #expect(lit.red > 0.9 && lit.green < 0.1)
    }
}
