@testable import ShipyardApp
import SwiftUI
import Testing

/// A project's count badge is accented when folded and muted when unfolded:
/// only its colour differs, so folding never moves or resizes it.
@Suite("Count badge")
@MainActor
struct CountBadgeTests {
    private func size(_ badge: CountBadge) throws -> CGSize {
        let renderer = ImageRenderer(content: badge)
        renderer.scale = 2
        let image = try #require(renderer.cgImage)
        return CGSize(width: image.width, height: image.height)
    }

    @Test("muted and accented, the badge is the same size", arguments: [1, 7, 12, 99, 128])
    func sameSize(count: Int) throws {
        #expect(try size(CountBadge(count: count, muted: true)) == size(CountBadge(count: count, muted: false)))
    }
}
