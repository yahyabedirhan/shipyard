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

    @Test("the app looks up every state a theme colours, and only states the theme has: rows, check dots, reviews and the rate limit")
    func stateNames() {
        var named: Set<String> = []
        func record(_ color: ThemeColor?) {
            guard case .state(let kind, let state)? = color?.source else { return }
            named.insert("\(kind.rawValue).\(state)")
        }
        for (itemKind, kind) in [(ItemKind.pullRequest, ThemeKind.pullRequest), (.issue, .issue), (.workflowRun, .run)] {
            for (state, _) in kind.states {
                let item = ItemState(rawValue: state)
                #expect(item != nil, "\(kind.rawValue).\(state)")
                if let item { record(ThemeColor.state(item, kind: itemKind)) }
            }
        }
        record(ThemeColor.state(.open, kind: .ping))
        record(ThemeColor.state(.open, kind: .note))
        for checks in [ChecksState.pending, .passed, .failed] { record(ThemeColor.checks(checks)) }
        #expect(ThemeColor.checks(.none) == nil)
        for decision in [ReviewDecision.approved, .changesRequested, .reviewRequired] { record(ThemeColor.review(decision)) }
        for level in [RateLevel.normal, .low, .exhausted] { record(ThemeColor.rate(level)) }
        let themed = Set(ThemeKind.allCases.flatMap { kind in kind.states.map { "\(kind.rawValue).\($0.name)" } })
        #expect(named == themed)
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
