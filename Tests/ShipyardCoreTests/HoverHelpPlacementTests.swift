@testable import ShipyardCore
import Testing

@Suite("Hover help placement")
struct HoverHelpPlacementTests {
    private typealias Rect = HoverHelpPlacement.Rect

    /// The panel: 400 points wide, as `Grid.panelWidth`.
    private let panel = Rect(x: 0, y: 0, width: 400, height: 300)

    private func row(at y: Double) -> Rect {
        Rect(x: 0, y: y, width: 400, height: 24)
    }

    @Test("a row's help sits under it, lined up with its title")
    func underARow() {
        let frame = HoverHelpPlacement.frame(width: 250, height: 30, target: row(at: 100), bounds: panel, leadingInset: 30)
        #expect(frame == Rect(x: 30, y: 128, width: 250, height: 30))
    }

    @Test("a row near the panel's bottom edge has its help over it instead")
    func overTheLastRow() {
        let target = row(at: 260)
        let frame = HoverHelpPlacement.frame(width: 250, height: 30, target: target, bounds: panel, leadingInset: 30)
        #expect(frame == Rect(x: 30, y: 226, width: 250, height: 30))
        #expect(frame.maxY <= target.minY)
    }

    @Test("a small button's help is centred under it, and kept in from the panel's side")
    func underAButtonAtTheEdge() {
        let middle = HoverHelpPlacement.frame(width: 80, height: 20, target: Rect(x: 200, y: 8, width: 24, height: 22), bounds: panel)
        #expect(middle == Rect(x: 172, y: 34, width: 80, height: 20))

        let corner = HoverHelpPlacement.frame(width: 120, height: 20, target: Rect(x: 360, y: 8, width: 24, height: 22), bounds: panel)
        #expect(corner == Rect(x: 274, y: 34, width: 120, height: 20))
        #expect(corner.maxX == panel.maxX - 6)
    }

    @Test("help wider than the panel is narrowed to fit inside its margins")
    func narrowedToThePanel() {
        let frame = HoverHelpPlacement.frame(width: 500, height: 44, target: row(at: 40), bounds: panel, leadingInset: 30)
        #expect(frame == Rect(x: 6, y: 68, width: 388, height: 44))
    }

    @Test("on every row of the panel, the help stays inside it and off the hovered row", arguments: Array(stride(from: 0.0, through: 276, by: 24)))
    func neverOverTheRow(y: Double) {
        let target = row(at: y)
        let frame = HoverHelpPlacement.frame(width: 300, height: 46, target: target, bounds: panel, leadingInset: 30)
        #expect(frame.minX >= panel.minX + 6 && frame.maxX <= panel.maxX - 6)
        #expect(frame.minY >= panel.minY + 6 && frame.maxY <= panel.maxY - 6)
        #expect(frame.maxY <= target.minY || frame.minY >= target.maxY)
    }

    @Test("in a panel too short for either side, the help takes the roomier side and stays inside")
    func tooShort() {
        let short = Rect(x: 0, y: 0, width: 400, height: 60)
        let frame = HoverHelpPlacement.frame(width: 200, height: 40, target: row(at: 20), bounds: short, leadingInset: 30)
        #expect(frame == Rect(x: 30, y: 6, width: 200, height: 40))
    }
}
