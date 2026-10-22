import ShipyardConfig
import ShipyardCore
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

    @Test("a state icon's colour says where it is in its life, whatever its kind: active, done or failed", arguments: [
        (ItemState.open, ItemKind.pullRequest, ThemeToken.open),
        (.open, .issue, .open),
        (.running, .workflowRun, .running),
        (.draft, .pullRequest, .draft),
        (.merged, .pullRequest, .merged),
        (.closed, .issue, .merged),
        (.succeeded, .workflowRun, .merged),
        (.closed, .pullRequest, .closed),
        (.failed, .workflowRun, .closed),
        (.open, .ping, .neutral),
        (.open, .note, .neutral),
    ])
    func stateIcon(_ state: ItemState, _ kind: ItemKind, _ token: ThemeToken) {
        #expect(ThemeColor.state(state, kind: kind) == ThemeColor(token))
    }

    @Test("each built-in theme passes the contrast check with the live macOS colours, as with the reference ones the command uses")
    func liveContrast() {
        let live: (SystemShade, ThemeAppearance) -> RGBA = { shade, appearance in
            var environment = EnvironmentValues()
            environment.colorScheme = ColorScheme(appearance)
            let color = SystemColors.color(shade, appearance).resolve(in: environment)
            return RGBA(r: Double(color.red), g: Double(color.green), b: Double(color.blue), a: Double(color.opacity))
        }
        for theme in BuiltInThemes.themes {
            #expect(ThemeContrast.shortfalls(theme, system: live).isEmpty, "\(theme.name): \(ThemeContrast.shortfalls(theme, system: live))")
        }
    }
}
