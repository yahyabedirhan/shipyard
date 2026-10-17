import Foundation

/// The height a measured scroll view takes from its content's measured
/// height: the measurement capped at `maxHeight`, and only when that capped
/// value moves by half a point or more.
///
/// A lazy stack's height is an estimate from the rows it laid out, which
/// depend on the viewport, which depends on this height; writing every new
/// estimate resized the panel, which made a new estimate, without end. Once
/// the content is taller than the cap, estimates above it change nothing.
public enum MeasuredHeight {
    /// The smallest change of the capped height worth a new layout.
    public static let threshold = 0.5

    /// The new height, or `nil` to keep `current`.
    public static func next(current: Double, measured: Double, maxHeight: Double) -> Double? {
        let capped = min(measured, maxHeight)
        return abs(capped - current) < threshold ? nil : capped
    }
}
