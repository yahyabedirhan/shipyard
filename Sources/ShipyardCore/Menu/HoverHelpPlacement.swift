import Foundation

/// Where the panel's hover help sits: next to the view the pointer is on,
/// never over it, and inside the panel, so the panel's edge can't cut it off.
/// Pure geometry in its own rectangle (the core doesn't import
/// CoreGraphics, to build on Linux), so tests reach it without SwiftUI.
public enum HoverHelpPlacement {
    /// A rectangle in points, y growing downwards as in SwiftUI.
    public struct Rect: Equatable, Sendable {
        public var x: Double
        public var y: Double
        public var width: Double
        public var height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var minX: Double { x }
        var midX: Double { x + width / 2 }
        var maxX: Double { x + width }
        var minY: Double { y }
        var maxY: Double { y + height }
    }

    /// The help's frame, `width` by `height`, for `target` (the hovered
    /// view's frame) inside `bounds` (the panel's), in one coordinate space.
    ///
    /// Vertically: under the target, `gap` away, when it fits above the
    /// panel's bottom edge less `margin`; else over the target; and when
    /// neither fits, on the side with more room, kept inside the panel (the
    /// only case where it can reach over the target).
    ///
    /// Horizontally: a target wide enough (a row) lines the help up
    /// `leadingInset` in from its leading edge, under the row's title; a
    /// narrower one (a button) centres it. Either way it's kept `margin` in
    /// from the panel's sides, and no wider than the panel less its margins.
    public static func frame(
        width: Double,
        height: Double,
        target: Rect,
        bounds: Rect,
        gap: Double = 4,
        margin: Double = 6,
        leadingInset: Double = 0
    ) -> Rect {
        let width = min(width, max(bounds.width - 2 * margin, 0))

        let preferredX = target.width >= width + leadingInset
            ? target.minX + leadingInset
            : target.midX - width / 2
        let x = clamp(preferredX, lower: bounds.minX + margin, upper: bounds.maxX - margin - width)

        let below = target.maxY + gap
        let above = target.minY - gap - height
        let lowest = bounds.maxY - margin - height
        let highest = bounds.minY + margin
        let y: Double
        if below <= lowest {
            y = below
        } else if above >= highest {
            y = above
        } else if bounds.maxY - target.maxY >= target.minY - bounds.minY {
            y = clamp(below, lower: highest, upper: lowest)
        } else {
            y = clamp(above, lower: highest, upper: lowest)
        }
        return Rect(x: x, y: y, width: width, height: height)
    }

    /// `value` inside `lower...upper`; `lower` when the range is empty.
    private static func clamp(_ value: Double, lower: Double, upper: Double) -> Double {
        max(lower, min(value, upper))
    }
}
