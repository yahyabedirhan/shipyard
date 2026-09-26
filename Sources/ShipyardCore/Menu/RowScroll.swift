import Foundation

/// A row's top and bottom edges in the list's visible area, in points from
/// its top edge (negative above it).
public struct RowSpan: Equatable, Sendable {
    public var top: Double
    public var bottom: Double

    public init(top: Double, bottom: Double) {
        self.top = top
        self.bottom = bottom
    }

    public var height: Double { bottom - top }
}

/// How the list scrolls to keep the row the keys highlighted in view (#45),
/// the way a menu does: not at all while the row is in full view, and
/// otherwise just far enough to show it at the edge it went past, clear of
/// the pinned project header. No animation: holding a key repeats at the
/// system's rate and the list keeps up.
public enum RowScroll: Equatable, Sendable {
    /// The row is in view.
    case stay
    /// Scroll to the row with this unit anchor (`UnitPoint`'s y): the row's
    /// point at `anchor` of its height meets the list's point at `anchor`
    /// of its height, which puts the row's top just below the pinned header.
    case alignTop(anchor: Double)
    /// Scroll so the row's bottom meets the list's bottom.
    case alignBottom

    /// How to reveal `target`, highlighted after `previous`, among `places`
    /// (the layout's rows, top to bottom). `frame` is the row's span in the
    /// visible area, or `nil` when the lazy list hasn't laid it out (it's
    /// off screen: the list scrolls towards it the way the highlight moved,
    /// up when it went up or wrapped to the top). `pinnedHeader` is the
    /// height of a project header pinned over the top (0 in a tab); a
    /// header itself pins at the very top.
    public static func reveal(
        _ target: MenuRowPlace,
        from previous: MenuRowPlace?,
        in places: [MenuRowPlace],
        frame: RowSpan?,
        visibleHeight: Double,
        pinnedHeader: Double
    ) -> RowScroll {
        let clear = target.isHeader ? 0 : pinnedHeader
        guard let frame else {
            let index = places.firstIndex(of: target) ?? 0
            let upward = previous.flatMap { places.firstIndex(of: $0) }.map { index < $0 } ?? (index == 0)
            // Without the row's height, near enough: off by the row's share of the header.
            return upward ? .alignTop(anchor: anchor(clear, visibleHeight, rowHeight: 0)) : .alignBottom
        }
        if frame.top < clear { return .alignTop(anchor: anchor(clear, visibleHeight, rowHeight: frame.height)) }
        if frame.bottom > visibleHeight { return .alignBottom }
        return .stay
    }

    /// The unit anchor whose point on the row and on the list are `clear`
    /// apart: y × (visible − row) = clear.
    private static func anchor(_ clear: Double, _ visibleHeight: Double, rowHeight: Double) -> Double {
        let room = visibleHeight - rowHeight
        guard room > 0 else { return 0 }
        return min(max(clear / room, 0), 1)
    }
}
