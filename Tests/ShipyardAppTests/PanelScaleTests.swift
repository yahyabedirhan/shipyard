import ShipyardConfig
@testable import ShipyardApp
import SwiftUI
import Testing

@Suite("Panel scale: the theme's font, density and shape knobs")
struct PanelScaleTests {
    @Test("the Shipyard theme gives the panel's long-standing grid and list grid, its 6 and 8 pt corners, and the system text styles")
    func shipyard() {
        let scale = PanelScale(BuiltInThemes.system.knobs)
        let grid = scale.grid
        #expect([grid.gutter, grid.titleBarHeight, grid.rowHeight, grid.headerHeight, grid.tabRowPadding] == [12, 38, 24, 26, 5])
        #expect([grid.smallRadius, grid.radius] == [6, 8])
        let list = scale.list
        #expect([list.gutter, list.rowHeight, list.headerHeight] == [12, 22, 22])
        #expect(scale.type.body == Font.system(.callout))
        #expect(scale.type.title == Font.system(.headline, weight: .semibold))
        #expect(scale.listType.body == Font.system(size: 12, weight: .regular, design: .default))
        #expect(scale.listType.meta == Font.system(size: 10.5, weight: .regular, design: .default).monospacedDigit())
    }

    @Test("a theme's knobs move the sizes, the radii and the type from its body size")
    func knobs() {
        var knobs = ThemeKnobs.standard
        knobs.fontFamily = "rounded"
        knobs.fontSize = 14
        (knobs.row, knobs.header, knobs.bar, knobs.gutter) = (28, 30, 42, 14)
        (knobs.small, knobs.medium) = (0, 12)
        let scale = PanelScale(knobs)
        #expect([scale.grid.rowHeight, scale.grid.tabRowPadding, scale.list.rowHeight, scale.list.headerHeight] == [28, 7, 26, 26])
        #expect([scale.grid.smallRadius, scale.grid.radius] == [0, 12])
        #expect(scale.type.body == Font.system(size: 14, weight: .regular, design: .rounded))
        #expect(scale.listType.body == Font.system(size: 14, weight: .regular, design: .rounded))
    }

    @Test("setting a theme in the environment sets its scale; with none set, the scale is Shipyard's")
    func environment() {
        var environment = EnvironmentValues()
        #expect(environment.panelScale == PanelScale(BuiltInThemes.system.knobs))
        var knobs = ThemeKnobs.standard
        knobs.row = 22
        environment.theme = Theme(name: "Compact", knobs: knobs) { _, _ in .system }
        #expect(environment.panelScale.grid.rowHeight == 22)
    }
}
