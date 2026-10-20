import Foundation
import ShipyardConfig
import Testing

@Suite("Themes: reading a theme file")
struct ThemeReaderTests {
    private static let red = ThemeValue.color(RGBA(r: 1, g: 0, b: 0))
    private static let blue = ThemeValue.color(RGBA(r: 0, g: 0, b: 1))
    private static let white = ThemeValue.color(RGBA(r: 1, g: 1, b: 1))

    /// A theme file the reader accepts, and what the theme it reads holds.
    struct Valid: CustomTestStringConvertible, Sendable {
        var name: String
        var text: String
        var check: @Sendable (Theme) -> Void
        var testDescription: String { name }
    }

    static let valid: [Valid] = [
        Valid(name: "a token in [any.*] sets both appearances; one left out is system", text: """
            name = "Plain"
            version = 1
            description = "Red text."
            [any.text]
            primary = "#ff0000"
            """) { theme in
            #expect(theme.name == "Plain")
            #expect(theme.summary == "Red text.")
            #expect(theme.value(.textPrimary, .light) == red)
            #expect(theme.value(.textPrimary, .dark) == red)
            #expect(theme.value(.textSecondary, .dark) == .system)
            #expect(theme.appearances == [.light, .dark])
            #expect(theme.knobs == .standard)
        },
        Valid(name: "[light.*] and [dark.*] override [any.*] for one appearance", text: """
            name = "Split"
            version = 1
            [any.accent]
            accent = "#ff0000"
            [dark.accent]
            accent = "#0000ff"
            """) { theme in
            #expect(theme.value(.accent, .light) == red)
            #expect(theme.value(.accent, .dark) == blue)
        },
        Valid(name: "a palette name is looked up per appearance; system and #rrggbbaa are colors too", text: """
            name = "Named"
            version = 1
            [palette]
            ink = "#ff0000"
            plain = "system"
            [dark.palette]
            ink = "#0000ff"
            [any.text]
            primary = "ink"
            secondary = "plain"
            tertiary = "#ffffff80"
            """) { theme in
            #expect(theme.value(.textPrimary, .light) == red)
            #expect(theme.value(.textPrimary, .dark) == blue)
            #expect(theme.value(.textSecondary, .light) == .system)
            #expect(theme.value(.textTertiary, .dark) == .color(RGBA(r: 1, g: 1, b: 1, a: 128.0 / 255)))
        },
        Valid(name: "a theme with no extends that fills one appearance draws it in both", text: """
            name = "Night"
            version = 1
            [dark.surface]
            panel = "#0000ff"
            """) { theme in
            #expect(theme.value(.panel, .light) == blue)
            #expect(theme.value(.panel, .dark) == blue)
            #expect(theme.appearances == [.dark])
        },
        Valid(name: "extends fills every token and knob the file leaves out, and its palette names carry over", text: """
            name = "Harbor at night"
            version = 1
            extends = "shipyard"
            [any.surface]
            panel = "accent"
            [shape]
            small = 2
            """) { theme in
            let parent = BuiltInThemes.shipyard
            #expect(theme.value(.panel, .light) == parent.value(.accent, .light))
            #expect(theme.value(.panel, .dark) == parent.value(.accent, .dark))
            #expect(theme.value(.textOnAccent, .dark) == white)
            #expect(theme.value(.header, .dark) == parent.value(.header, .dark))
            #expect(theme.knobs.small == 2)
            #expect(theme.knobs.medium == parent.knobs.medium)
            #expect(theme.knobs.glass)
        },
        Valid(name: "the knobs: font, a density preset with an explicit size over it, shape and material", text: """
            name = "Roomy"
            version = 1
            [font]
            family = "rounded"
            size = 13.5
            [density]
            preset = "comfortable"
            row = 30
            [shape]
            large = 0
            [material]
            style = "flat"
            """) { theme in
            var knobs = ThemeKnobs()
            knobs.fontFamily = "rounded"
            knobs.fontSize = 13.5
            knobs.density = "comfortable"
            (knobs.row, knobs.header, knobs.bar, knobs.gutter) = (30, 30, 42, 14)
            knobs.large = 0
            knobs.glass = false
            #expect(theme.knobs == knobs)
        },
    ]

    @Test("a valid theme file reads into its theme", arguments: valid)
    func reads(_ example: Valid) throws {
        let (theme, issues) = ThemeReader.theme(example.text, file: "Theme.toml", source: .builtIn, library: BuiltInThemes.definitions)
        #expect(issues.isEmpty, "\(issues)")
        example.check(try #require(theme))
    }

    /// A theme file the reader rejects, and each problem's banner line.
    struct Invalid: CustomTestStringConvertible, Sendable {
        var name: String
        var text: String
        var issues: [String]
        var testDescription: String { name }
    }

    static let invalid: [Invalid] = [
        Invalid(name: "an unknown token, with the nearest spelling", text: """
            name = "Typo"
            version = 1
            [any.text]
            primray = "#ff0000"
            """, issues: ["Theme.toml line 4: unknown token `any.text.primray`; did you mean `primary`?"]),
        Invalid(name: "an unknown section and an unknown top-level key", text: """
            name = "Typo"
            version = 1
            colour = "red"
            [light.surfaces]
            panel = "#ffffff"
            """, issues: [
                "Theme.toml line 3: unknown key `colour`",
                "Theme.toml line 4: unknown key `light.surfaces`; did you mean `surface`?",
            ]),
        Invalid(name: "a value that's no palette name, color or system", text: """
            name = "Wrong"
            version = 1
            [any.surface]
            panel = "blue"
            """, issues: ["Theme.toml line 4: `any.surface.panel` is \"blue\", which isn't a palette name, a color or `system`"]),
        Invalid(name: "a broken hex color, in a token and in the palette", text: """
            name = "Wrong"
            version = 1
            [palette]
            ink = "#12345"
            [any.surface]
            panel = "#zzzzzz"
            """, issues: [
                "Theme.toml line 4: `palette.ink` is \"#12345\", which isn't a color; write #rrggbb, #rrggbbaa or system",
                "Theme.toml line 6: `any.surface.panel` is \"#zzzzzz\", which isn't a color; write #rrggbb or #rrggbbaa",
            ]),
        Invalid(name: "a value that isn't a string, and a knob out of range", text: """
            name = "Wrong"
            version = 1
            [any.surface]
            panel = 3
            [font]
            size = 40
            """, issues: [
                "Theme.toml line 4: `any.surface.panel` must be a quoted string",
                "Theme.toml line 6: `font.size` must be a size in points from 9 to 20",
            ]),
        Invalid(name: "a wrong version", text: """
            name = "Future"
            version = 2
            """, issues: ["Theme.toml line 2: `version` 2 isn't supported; this shipyard reads version 1"]),
        Invalid(name: "a missing name and version", text: """
            [any.surface]
            panel = "system"
            """, issues: [
                "Theme.toml: `name` is missing; write name = \"My theme\"",
                "Theme.toml: `version` is missing; write version = 1",
            ]),
        Invalid(name: "extends names no theme", text: """
            name = "Orphan"
            version = 1
            extends = "Nowhere"
            """, issues: ["Theme.toml line 3: `extends` names \"Nowhere\", which isn't a theme"]),
        Invalid(name: "extends goes back to the theme itself", text: """
            name = "Loop"
            version = 1
            extends = "Loop"
            """, issues: ["Theme.toml line 3: `extends` goes in a circle: Loop → Loop"]),
        Invalid(name: "invalid TOML", text: """
            name = "Broken
            version = 1
            """, issues: []),
    ]

    @Test("a wrong theme file is rejected with each problem's line", arguments: invalid)
    func rejects(_ example: Invalid) {
        let (theme, issues) = ThemeReader.theme(example.text, file: "Theme.toml", source: .builtIn, library: BuiltInThemes.definitions)
        #expect(theme == nil)
        if example.issues.isEmpty {
            #expect(issues.count == 1)
            #expect(issues.first?.description.hasPrefix("Theme.toml line 1: invalid TOML") == true, "\(issues)")
        } else {
            #expect(issues.map(\.description) == example.issues)
        }
    }

    @Test("of two themes with one name, the later wins, so a user file replaces a built-in theme")
    func laterWins() throws {
        let user = try #require(ThemeReader.definition("""
            name = "shipyard"
            version = 1
            [any.accent]
            accent = "#ff0000"
            """, file: "Mine.toml", source: .file(URL(fileURLWithPath: "/themes/Mine.toml"))).definition)
        let (themes, issues) = ThemeReader.resolve(BuiltInThemes.definitions + [user])
        #expect(issues.isEmpty)
        #expect(themes.count == BuiltInThemes.themes.count)
        let shipyard = try #require(themes.first { $0.name.lowercased() == "shipyard" })
        #expect(shipyard.value(.accent, .light) == Self.red)
        #expect(shipyard.source == .file(URL(fileURLWithPath: "/themes/Mine.toml")))
    }

    @Test("the Shipyard theme is built in, reads with no problem, and draws white text on the accent in dark")
    func shipyard() {
        #expect(BuiltInThemes.issues.isEmpty, "\(BuiltInThemes.issues)")
        let theme = BuiltInThemes.shipyard
        #expect(theme.name == "Shipyard")
        #expect(BuiltInThemes.named("SHIPYARD") == theme)
        #expect(theme.value(.textOnAccent, .dark) == Self.white)
        #expect(theme.value(.accent, .dark) == .color(RGBA(hex: "#6D9CFF")!))
        #expect(theme.value(.panel, .light) == .system)
        #expect(theme.knobs == .standard)
    }
}
