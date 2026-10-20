import ShipyardConfig
@testable import ShipyardApp
import SwiftUI
import Testing

@Suite("Theme colors: the token layer")
struct ThemeColorTests {
    private static let theme = Theme(name: "Test") { token, appearance in
        guard token == .panel else { return .system }
        return .color(appearance == .dark ? RGBA(r: 0, g: 0, b: 1) : RGBA(r: 1, g: 0, b: 0))
    }

    private func drawn(_ color: ThemeColor, theme: Theme?, _ scheme: ColorScheme) -> Color.Resolved {
        var environment = EnvironmentValues()
        if let theme { environment.theme = theme }
        environment.colorScheme = scheme
        return color.resolve(in: environment).resolve(in: environment)
    }

    @Test("a token draws the theme in its environment, in the environment's appearance")
    func followsEnvironment() {
        let light = drawn(.panel, theme: Self.theme, .light)
        let dark = drawn(.panel, theme: Self.theme, .dark)
        #expect((light.red, light.green, light.blue) == (1, 0, 0))
        #expect((dark.red, dark.green, dark.blue) == (0, 0, 1))
        // Another part of the window, with no theme set, keeps drawing Shipyard.
        #expect(drawn(.panel, theme: nil, .dark) == drawn(.panel, theme: BuiltInThemes.shipyard, .dark))
        #expect(drawn(.panel, theme: nil, .dark) != dark)
    }

    @Test("a system value draws the macOS colour for its appearance; opacity scales it")
    func system() {
        let onAccent = drawn(.textOnAccent, theme: Self.theme, .dark)
        #expect((onAccent.red, onAccent.green, onAccent.blue, onAccent.opacity) == (1, 1, 1, 1))
        #expect(drawn(.textPrimary, theme: Self.theme, .light) != drawn(.textPrimary, theme: Self.theme, .dark))
        #expect(abs(drawn(.panel.opacity(0.5), theme: Self.theme, .light).opacity - 0.5) < 0.001)
    }
}
