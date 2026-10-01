@testable import ShipyardCore
import Testing

/// A measured scroll view takes a new height only when its content's height,
/// capped at the scroll view's maximum, really changed: otherwise a lazy
/// stack re-estimating its height under each new viewport resizes the panel
/// forever.
@Suite("Measured height")
struct MeasuredHeightTests {
    @Test("content shorter than the cap sets the height to its own")
    func shorterThanTheCap() {
        #expect(MeasuredHeight.next(current: 0, measured: 240, maxHeight: 500) == 240)
    }

    @Test("content taller than the cap sets the height to the cap")
    func clampedToTheCap() {
        #expect(MeasuredHeight.next(current: 0, measured: 900, maxHeight: 500) == 500)
    }

    @Test("a new estimate above the cap changes nothing while the height is the cap")
    func estimatesAboveTheCap() {
        #expect(MeasuredHeight.next(current: 500, measured: 1_300, maxHeight: 500) == nil)
    }

    @Test("a change under half a point is ignored", arguments: [0.1, 0.49, -0.3])
    func subPointJitter(delta: Double) {
        #expect(MeasuredHeight.next(current: 240, measured: 240 + delta, maxHeight: 500) == nil)
    }

    @Test("a change of half a point or more is taken", arguments: [0.5, 2, -12])
    func meaningfulChange(delta: Double) {
        #expect(MeasuredHeight.next(current: 240, measured: 240 + delta, maxHeight: 500) == 240 + delta)
    }

    @Test("content shrinking back under the cap is taken")
    func shrinksUnderTheCap() {
        #expect(MeasuredHeight.next(current: 500, measured: 320, maxHeight: 500) == 320)
    }

    @Test("a lazy stack's estimates flipping around and above the cap settle after one write")
    func oscillationSettles() {
        let estimates: [Double] = [900, 1_400, 900, 1_400, 499.8, 1_400, 900, 500.2]
        var height = 0.0
        var writes = 0
        for estimate in estimates {
            if let next = MeasuredHeight.next(current: height, measured: estimate, maxHeight: 500) {
                height = next
                writes += 1
            }
        }
        #expect(height == 500)
        #expect(writes == 1)
    }

    @Test("sub-point estimates flipping under the cap settle after the first write")
    func jitterUnderTheCapSettles() {
        let estimates: [Double] = [240, 240.3, 239.8, 240.3, 239.8, 240.1]
        var height = 0.0
        var writes = 0
        for estimate in estimates {
            if let next = MeasuredHeight.next(current: height, measured: estimate, maxHeight: 500) {
                height = next
                writes += 1
            }
        }
        #expect(height == 240)
        #expect(writes == 1)
    }
}
