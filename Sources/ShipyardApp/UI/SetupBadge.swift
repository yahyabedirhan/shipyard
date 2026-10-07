import AppKit
import ShipyardCore
import SwiftUI

/// A part's badge at the top of its status view (`StatusView`): shipyard's
/// logo (`LogoBadge`) for the skill and the CLI, and the maker's mark for
/// GitHub and Notion, on a tile of the badge's own squircle in the maker's
/// colours. Every badge is `side` square with the same corners, and keeps
/// its colours in light and dark mode, as `LogoBadge` does.
struct SetupBadge: View {
    let part: SetupPart
    var side: CGFloat = 32

    var body: some View {
        if let tile = Tile(part) {
            tiled(tile)
        } else {
            LogoBadge(side: side)
        }
    }

    private func tiled(_ tile: Tile) -> some View {
        let shape: LogoShape = .squircle
        return ZStack {
            shape.fill(tile.fill)
            mark(tile)
            // A hairline inside the edge, so the white tile holds its shape
            // on a light panel and the dark one on a dark panel: the stroke
            // is centred on the path, so clipping keeps its inner half and
            // the badge stays `side` square.
            shape.stroke(tile.hairline, lineWidth: 1)
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private func mark(_ tile: Tile) -> some View {
        Group {
            if let image = Self.mark(for: part) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(tile.mark)
            }
        }
        .frame(width: side * tile.markShare, height: side * tile.markShare)
    }

    /// GitHub's or Notion's mark as a template image, for the tile to draw
    /// in its mark colour; nil for the skill and the CLI, which show the
    /// sailboat, or when the bundle lacks the file.
    @MainActor
    static func mark(for part: SetupPart) -> NSImage? {
        guard let name = Tile(part)?.resource else { return nil }
        if let cached = cache[name] { return cached }
        guard let url = AgentLogoImage.resources.url(forResource: name, withExtension: "pdf", subdirectory: "ServiceLogos"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.isTemplate = true
        cache[name] = image
        return image
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// A maker's tile: its colours and how much of the side the mark's own
    /// 24-unit box takes, tuned so each mark looks the size of the sailboat.
    private struct Tile {
        let resource: String
        let fill: Color
        let mark: Color
        let hairline: Color
        let markShare: CGFloat

        init?(_ part: SetupPart) {
            switch part {
            case .github:
                // GitHub's dark (#24292F) with the white Invertocat, the
                // colours GitHub's logo terms allow.
                self.init(resource: "github", fill: LogoBadge.color(0x24292F), mark: .white, hairline: .white.opacity(0.10), markShare: 0.66)
            case .notion:
                // White with Notion's black cube, as Notion's own app icon.
                self.init(resource: "notion", fill: .white, mark: .black, hairline: .black.opacity(0.12), markShare: 0.64)
            case .skill, .cli:
                return nil
            }
        }

        private init(resource: String, fill: Color, mark: Color, hairline: Color, markShare: CGFloat) {
            self.resource = resource
            self.fill = fill
            self.mark = mark
            self.hairline = hairline
            self.markShare = markShare
        }
    }
}
