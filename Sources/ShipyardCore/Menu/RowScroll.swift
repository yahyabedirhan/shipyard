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

/// How the list scrolls to keep the row the keys highlighted in view,
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
    /// ↓ wrapped from the last row to the first: scroll straight to the
    /// list's very top, in the same key press. The first row may not be
    /// laid out, so the list goes to its own top edge, not to the row.
    case wrapToTop
    /// ↑ wrapped from the first row to the last: scroll straight to the
    /// list's very bottom, whether the last row is laid out or not.
    case wrapToBottom

    /// How to reveal `target`, highlighted after `previous`, among `places`
    /// (the layout's rows, top to bottom). A step from one end of `places`
    /// to the other is a wrap, which goes to the list's far edge. `frame`
    /// is the row's span in the visible area, or `nil` when the lazy list
    /// hasn't laid it out (it's off screen: the list scrolls towards it the
    /// way the highlight moved, up when it went up, or from a header to its
    /// first item, which is under the pinned header). `pinnedHeader` is the
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
        if places.count > 1, let previous {
            if previous == places.last, target == places.first { return .wrapToTop }
            if previous == places.first, target == places.last { return .wrapToBottom }
        }
        let clear = target.isHeader ? 0 : pinnedHeader
        guard let frame else {
            let index = places.firstIndex(of: target) ?? 0
            let from = previous.flatMap { places.firstIndex(of: $0) }
            // A header's first item sits just under it; with the header
            // pinned at the top, that item is scrolled away above.
            let underHeader = previous?.isHeader == true && previous?.section == target.section && from == index - 1
            let upward = underHeader || from.map { index < $0 } ?? (index == 0)
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

/// A wrap's scroll to the list's far end, followed until its row lands in
/// full view. The list layout's lazy stack guesses the height of the rows
/// it hasn't laid out, so its end is only where the guess puts it until
/// the rows there are laid out: the first scroll to the bottom can stop
/// short of the last row. The list checks the row once the rows have
/// moved and scrolls to the same end again until it's in view, a few
/// times at most, so a wrap that can't land (a list still loading) doesn't
/// hold the list.
public struct RowWrapLanding: Equatable, Sendable {
    /// What a check says to do next.
    public enum Step: Equatable, Sendable {
        /// The row is in full view: done.
        case landed
        /// Short of it: scroll to the list's end again.
        case scrollAgain
        /// Scrolled again as often as it may: stop following the wrap.
        case giveUp
    }

    /// The row the wrap highlighted.
    public let target: MenuRowPlace
    /// `.wrapToTop` or `.wrapToBottom`: the end the list scrolls to.
    public let scroll: RowScroll
    private var retries = 0
    private static let maxRetries = 4

    /// The landing of `scroll` to `target`, if it's a wrap; other scrolls
    /// go to a laid-out row, or the way the highlight moved, just once.
    public init?(_ scroll: RowScroll, to target: MenuRowPlace) {
        guard scroll == .wrapToTop || scroll == .wrapToBottom else { return nil }
        self.target = target
        self.scroll = scroll
    }

    /// With the rows moved, the target's span in the visible area (`nil`
    /// if it isn't laid out) in a list `visibleHeight` tall.
    public mutating func check(frame: RowSpan?, visibleHeight: Double) -> Step {
        if let frame, frame.top >= -0.5, frame.bottom <= visibleHeight + 0.5 { return .landed }
        guard retries < Self.maxRetries else { return .giveUp }
        retries += 1
        return .scrollAgain
    }
}
