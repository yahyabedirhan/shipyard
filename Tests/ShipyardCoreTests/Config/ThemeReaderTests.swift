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
        Valid(name: "a token in a table without a prefix sets both appearances; one left out is system", text: """
            name = "Plain"
            version = 1
            description = "Red text."
            [text]
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
        Valid(name: "[light.*] and [dark.*] override a table without a prefix for one appearance, whichever comes first", text: """
            name = "Split"
            version = 1
            [accent]
            accent = "#ff0000"
            [dark.accent]
            accent = "#0000ff"
            [light.surface]
            panel = "#0000ff"
            [surface]
            panel = "#ff0000"
            """) { theme in
            #expect(theme.value(.accent, .light) == red)
            #expect(theme.value(.accent, .dark) == blue)
            #expect(theme.value(.panel, .light) == blue)
            #expect(theme.value(.panel, .dark) == red)
            #expect(theme.appearances == [.light, .dark])
        },
        Valid(name: "a palette name is looked up per appearance; system and #rrggbbaa are colors too", text: """
            name = "Named"
            version = 1
            [palette]
            ink = "#ff0000"
            plain = "system"
            [dark.palette]
            ink = "#0000ff"
            [text]
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
        Valid(name: "tokens without a prefix that read one appearance's own palette make a theme that fills that one", text: """
            name = "Cream"
            version = 1
            [light.palette]
            ink = "#ff0000"
            [text]
            primary = "ink"
            """) { theme in
            #expect(theme.appearances == [.light])
            #expect(theme.value(.textPrimary, .dark) == red)
        },
        Valid(name: "extends fills every token and knob the file leaves out, and its palette names carry over", text: """
            name = "Harbor at night"
            version = 1
            extends = "shipyard dark"
            [surface]
            panel = "accent"
            [shape]
            small = 2
            """) { theme in
            let parent = BuiltInThemes.named("Shipyard Dark")!
            #expect(theme.appearances == [.dark], "it keeps its parent's one appearance")
            #expect(theme.value(.panel, .dark) == parent.value(.accent, .dark))
            #expect(theme.value(.textOnAccent, .dark) == white)
            #expect(theme.value(.header, .dark) == parent.value(.header, .dark))
            #expect(theme.knobs.small == 2)
            #expect(theme.knobs.medium == parent.knobs.medium)
            #expect(theme.knobs.glass)
        },
        Valid(name: "a state with no colour of its own takes its phase, the rate limit's low the macOS orange; one left out of [phase] is its macOS colour", text: """
            name = "Phases"
            version = 1
            [palette]
            live = "#ff0000"
            [phase]
            active = "live"
            done = "#0000ff"
            failed = "#ffffff80"
            """) { theme in
            for appearance in ThemeAppearance.allCases {
                #expect(theme.color(.pullRequest, "open", appearance) == .color(RGBA(r: 1, g: 0, b: 0)))
                #expect(theme.color(.run, "running", appearance) == .color(RGBA(r: 1, g: 0, b: 0)))
                #expect(theme.color(.issue, "closed", appearance) == .color(RGBA(r: 0, g: 0, b: 1)))
                #expect(theme.color(.run, "failed", appearance) == .color(RGBA(r: 1, g: 1, b: 1, a: 128.0 / 255)))
                #expect(theme.color(.pullRequest, "draft", appearance) == .system(SystemShade(.secondaryLabel)))
                #expect(theme.color(.check, "pending", appearance) == .color(RGBA(r: 1, g: 0, b: 0)))
                #expect(theme.color(.review, "review-required", appearance) == .color(RGBA(r: 1, g: 0, b: 0)))
                #expect(theme.color(.rate, "normal", appearance) == .color(RGBA(r: 1, g: 0, b: 0)))
                #expect(theme.color(.check, "passed", appearance) == .color(RGBA(r: 0, g: 0, b: 1)))
                #expect(theme.color(.review, "approved", appearance) == .color(RGBA(r: 0, g: 0, b: 1)))
                #expect(theme.color(.check, "failed", appearance) == .color(RGBA(r: 1, g: 1, b: 1, a: 128.0 / 255)))
                #expect(theme.color(.review, "changes-requested", appearance) == .color(RGBA(r: 1, g: 1, b: 1, a: 128.0 / 255)))
                #expect(theme.color(.rate, "exhausted", appearance) == .color(RGBA(r: 1, g: 1, b: 1, a: 128.0 / 255)))
                #expect(theme.color(.rate, "low", appearance) == .system(SystemShade(.orange)))
                #expect(theme.color(.ping, "open", appearance) == .system(SystemShade(.secondaryLabel)))
                #expect(theme.color(.note, "open", appearance) == .system(SystemShade(.secondaryLabel)))
            }
            #expect(theme.color(.issue, "draft", .light) == nil)
            #expect(theme.color(.rate, "high", .light) == nil)
        },
        Valid(name: "a state names a phase, a palette name, a hex colour or system, which is its phase's macOS colour", text: """
            name = "States"
            version = 1
            [palette]
            ink = "#0000ff"
            quiet = "#ffffff"
            [phase]
            failed = "#ff0000"
            active = "system"
            [states.pull-request]
            open = "failed"
            draft = "ink"
            merged = "#ffffff80"
            closed = "system"
            [states.issue]
            closed = "quiet"
            [states.run]
            failed = "system"
            [states.rate]
            low = "system"
            exhausted = "active"
            [states.note]
            open = "ink"
            """) { theme in
            #expect(theme.color(.pullRequest, "open", .dark) == .color(RGBA(r: 1, g: 0, b: 0)))
            #expect(theme.color(.pullRequest, "draft", .dark) == .color(RGBA(r: 0, g: 0, b: 1)))
            #expect(theme.color(.pullRequest, "merged", .light) == .color(RGBA(r: 1, g: 1, b: 1, a: 128.0 / 255)))
            // A phase's name is the phase, though the palette has one too.
            #expect(theme.color(.issue, "closed", .light) == .system(SystemShade(.secondaryLabel)))
            #expect(theme.color(.pullRequest, "closed", .light) == .system(SystemShade(.red)))
            #expect(theme.color(.run, "failed", .light) == .system(SystemShade(.red)))
            // Another kind's state in that phase keeps the phase's colour.
            #expect(theme.color(.issue, "open", .light) == .system(SystemShade(.green)))
            // `system` for a state with no phase is the macOS orange.
            #expect(theme.color(.rate, "low", .dark) == .system(SystemShade(.orange)))
            #expect(theme.color(.rate, "exhausted", .dark) == .system(SystemShade(.green)))
            #expect(theme.color(.note, "open", .light) == .color(RGBA(r: 0, g: 0, b: 1)))
            #expect(theme.color(.ping, "open", .light) == .system(SystemShade(.secondaryLabel)))
        },
        Valid(name: "a [light.*] or [dark.*] phase or state wins over the table without a prefix", text: """
            name = "Split states"
            version = 1
            [dark.states.issue]
            closed = "#0000ff"
            [states.issue]
            closed = "#ff0000"
            [phase]
            active = "#ff0000"
            [light.phase]
            active = "#0000ff"
            """) { theme in
            #expect(theme.color(.issue, "closed", .light) == .color(RGBA(r: 1, g: 0, b: 0)))
            #expect(theme.color(.issue, "closed", .dark) == .color(RGBA(r: 0, g: 0, b: 1)))
            #expect(theme.color(.issue, "open", .light) == .color(RGBA(r: 0, g: 0, b: 1)))
            #expect(theme.color(.issue, "open", .dark) == .color(RGBA(r: 1, g: 0, b: 0)))
            #expect(theme.appearances == [.light, .dark])
        },
        Valid(name: "extends fills the phases and states a file leaves out, and a state follows the phase the file changes", text: """
            name = "System red"
            version = 1
            extends = "System"
            [phase]
            done = "#ff0000"
            [dark.states.run]
            running = "#0000ff"
            """) { theme in
            let parent = BuiltInThemes.system
            #expect(theme.color(.pullRequest, "merged", .light) == .color(RGBA(r: 1, g: 0, b: 0)))
            #expect(theme.color(.run, "succeeded", .dark) == .color(RGBA(r: 1, g: 0, b: 0)))
            #expect(theme.color(.run, "running", .dark) == .color(RGBA(r: 0, g: 0, b: 1)))
            #expect(theme.color(.run, "running", .light) == parent.color(.run, "running", .light))
            #expect(theme.color(.pullRequest, "closed", .dark) == parent.color(.pullRequest, "closed", .dark))
            #expect(theme.color(.pullRequest, "draft", .light) == parent.color(.quiet, .light))
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
            [text]
            primray = "#ff0000"
            """, issues: ["Theme.toml line 4: unknown token `text.primray`; did you mean `primary`?"]),
        Invalid(name: "an [any.*] table, each on its line, with the prefix to remove", text: """
            name = "Old"
            version = 1
            [any.text]
            primary = "#ff0000"
            [surface]
            panel = "#ffffff"
            [any.accent]
            accent = "#0000ff"
            """, issues: [
                "Theme.toml line 3: `[any.text]` has an `any.` prefix; remove it and write `[text]`, which sets light and dark",
                "Theme.toml line 7: `[any.accent]` has an `any.` prefix; remove it and write `[accent]`, which sets light and dark",
            ]),
        Invalid(name: "an unknown table without a prefix, with the nearest section", text: """
            name = "Typo"
            version = 1
            [surfaces]
            panel = "#ffffff"
            """, issues: ["Theme.toml line 3: unknown key `surfaces`; did you mean `surface`?"]),
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
            [surface]
            panel = "blue"
            """, issues: ["Theme.toml line 4: `surface.panel` is \"blue\", which isn't a palette name, a color or `system`"]),
        Invalid(name: "a broken hex color, in a token and in the palette", text: """
            name = "Wrong"
            version = 1
            [palette]
            ink = "#12345"
            [surface]
            panel = "#zzzzzz"
            """, issues: [
                "Theme.toml line 4: `palette.ink` is \"#12345\", which isn't a color; write #rrggbb, #rrggbbaa or system",
                "Theme.toml line 6: `surface.panel` is \"#zzzzzz\", which isn't a color; write #rrggbb or #rrggbbaa",
            ]),
        Invalid(name: "an unknown kind, state and phase, each with the nearest spelling, and a broken hex phase", text: """
            name = "Typo"
            version = 1
            [states.pull-requests]
            open = "active"
            [states.review]
            aproved = "done"
            [phase]
            activ = "#ff0000"
            done = "#12345"
            [dark.states.run]
            passed = "done"
            """, issues: [
                "Theme.toml line 3: unknown kind `states.pull-requests`; did you mean `pull-request`?",
                "Theme.toml line 6: unknown state `states.review.aproved`; did you mean `approved`?",
                "Theme.toml line 8: unknown phase `phase.activ`; did you mean `active`?",
                "Theme.toml line 9: `phase.done` is \"#12345\", which isn't a color; write #rrggbb or #rrggbbaa",
                "Theme.toml line 11: unknown state `dark.states.run.passed`",
            ]),
        Invalid(name: "a state or phase value that's no phase, palette name, color or system", text: """
            name = "Wrong"
            version = 1
            [phase]
            done = "violet"
            [states.issue]
            open = "green"
            """, issues: [
                "Theme.toml line 4: `phase.done` is \"violet\", which isn't a palette name, a color or `system`",
                "Theme.toml line 6: `states.issue.open` is \"green\", which isn't a phase, a palette name, a color or `system`",
            ]),
        Invalid(name: "a phase that names a phase, even one the palette has too", text: """
            name = "Loop"
            version = 1
            [palette]
            quiet = "#ffffff"
            [phase]
            failed = "done"
            [dark.phase]
            quiet = "quiet"
            """, issues: [
                "Theme.toml line 6: `phase.failed` is \"done\", which names a phase; a phase is a palette name, a color or `system`",
                "Theme.toml line 8: `dark.phase.quiet` is \"quiet\", which names a phase; a phase is a palette name, a color or `system`",
            ]),
        Invalid(name: "a removed state token, each on its line, with the keys that replace it", text: """
            name = "Old"
            version = 1
            [state]
            merged = "#ff0000"
            success = "#00ff00"
            failure = "#ff0000"
            neutral = "#888888"
            hover = "#000000"
            [dark.state]
            running = "#0000ff"
            pending = "#ffaa00"
            """, issues: [
                "Theme.toml line 4: `state.merged` was removed; write `[phase] done` for every done state, or `[states.pull-request] merged`, `[states.issue] closed` and `[states.run] succeeded`",
                "Theme.toml line 5: `state.success` was removed; write `[phase] done` for every done state, or `[states.check] passed` and `[states.review] approved`",
                "Theme.toml line 6: `state.failure` was removed; write `[phase] failed` for every failed state, or `[states.check] failed`, `[states.review] changes-requested` and `[states.rate] exhausted`",
                "Theme.toml line 7: `state.neutral` was removed; write `[phase] quiet` for every quiet state, or `[states.ping] open` and `[states.note] open`",
                "Theme.toml line 8: `state.hover` isn't a theme key; a state takes its colour from `[phase]` and `[states.<kind>]`",
                "Theme.toml line 10: `dark.state.running` was removed; write `[dark.phase] active` for every active state, or `[dark.states.run] running`",
                "Theme.toml line 11: `dark.state.pending` was removed; write `[dark.phase] active` for every active state, or `[dark.states.check] pending` and `[dark.states.review] review-required`; `[dark.states.rate] low` is in no phase, so write it too",
            ]),
        Invalid(name: "a value that isn't a string, and a knob out of range", text: """
            name = "Wrong"
            version = 1
            [surface]
            panel = 3
            [font]
            size = 40
            """, issues: [
                "Theme.toml line 4: `surface.panel` must be a quoted string",
                "Theme.toml line 6: `font.size` must be a size in points from 9 to 20",
            ]),
        Invalid(name: "a wrong version", text: """
            name = "Future"
            version = 2
            """, issues: ["Theme.toml line 2: `version` 2 isn't supported; this shipyard reads version 1"]),
        Invalid(name: "a missing name and version", text: """
            [surface]
            panel = "system"
            """, issues: [
                "Theme.toml: `name` is missing; write name = \"My theme\"",
                "Theme.toml: `version` is missing; write version = 1",
            ]),
        Invalid(name: "extends names no theme", text: """
            name = "Orphan"
            version = 1
            extends = "Nowhere"
            """, issues: ["""
                Theme.toml line 3: `extends` names "Nowhere", which isn't a theme (expected one of `Brass`, `Harbor`, `Heather`, \
                `Ocean`, `Paper Dark`, `Paper Light`, `Shipyard Dark`, `Shipyard Light`, `Sunset`, `System`)
                """]),
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
            name = "ocean"
            version = 1
            [accent]
            accent = "#ff0000"
            """, file: "Mine.toml", source: .file(URL(fileURLWithPath: "/themes/Mine.toml"))).definition)
        let (themes, issues) = ThemeReader.resolve(BuiltInThemes.definitions + [user])
        #expect(issues.isEmpty)
        #expect(themes.count == BuiltInThemes.themes.count)
        let shipyard = try #require(themes.first { $0.name.lowercased() == "ocean" })
        #expect(shipyard.value(.accent, .light) == Self.red)
        #expect(shipyard.source == .file(URL(fileURLWithPath: "/themes/Mine.toml")))
    }

    @Test("the built-in themes are the lineup, in its order: System, which follows the macOS appearance, then one theme of each appearance")
    func lineup() {
        #expect(BuiltInThemes.issues.isEmpty, "\(BuiltInThemes.issues)")
        #expect(BuiltInThemes.themes.map(\.name) == [
            "System", "Shipyard Light", "Shipyard Dark", "Paper Light", "Paper Dark", "Harbor", "Heather", "Brass", "Ocean", "Sunset",
        ])
        #expect(ThemeLibrary.builtIn.names == BuiltInThemes.themes.map(\.name))
        #expect(BuiltInThemes.system.name == "System")
        #expect(BuiltInThemes.named("SYSTEM") == BuiltInThemes.system)
        #expect(ThemeLibrary.defaultName == "System")
        let accents = [
            "Shipyard Light": "#2F6BDE", "Shipyard Dark": "#6D9CFF", "Paper Light": "#B4491E", "Paper Dark": "#E3CFA8",
            "Harbor": "#0E7C86", "Heather": "#6A4FB0", "Brass": "#8A6100", "Ocean": "#4FC3F7", "Sunset": "#FB923C",
        ]
        for (name, accent) in accents {
            let theme = BuiltInThemes.named(name)
            #expect(theme?.value(.accent, theme?.appearances.first ?? .light) == .color(RGBA(hex: accent)!), "\(name)")
        }
        // System is the macOS colours throughout, the accent included.
        for token in ThemeToken.allCases {
            #expect(BuiltInThemes.system.value(token, .light) == .system, "\(token)")
        }
        #expect(BuiltInThemes.named("Paper Light")?.color(.failed, .light) == .color(RGBA(hex: "#A3203C")!))
        #expect(BuiltInThemes.named("Sunset")?.color(.failed, .dark) == .color(RGBA(hex: "#F0506E")!))
        #expect(BuiltInThemes.named("Sunset")?.value(.attentionFailed, .dark) == .color(RGBA(hex: "#F0506E")!))
    }

    @Test("each built-in theme reads with no problem, passes the contrast and attention checks, gives active, done and failed their own colours and every state of one phase one colour, and fills its one appearance (System both)", arguments: BuiltInThemes.themes.map(\.name))
    func builtIn(_ name: String) throws {
        #expect(BuiltInThemes.issues.isEmpty, "\(BuiltInThemes.issues)")
        let theme = try #require(BuiltInThemes.named(name))
        #expect(ThemeContrast.shortfalls(theme).isEmpty, "\(ThemeContrast.shortfalls(theme))")
        #expect(ThemeSignals.clashes(theme).isEmpty, "\(ThemeSignals.clashes(theme))")
        for appearance in theme.appearances {
            var byPhase: [ThemePhase: Set<ThemeStateColor>] = [:]
            for kind in ThemeKind.allCases {
                for (state, phase) in kind.states {
                    let color = try #require(theme.color(kind, state, appearance))
                    if let phase { byPhase[phase, default: []].insert(color) }
                }
            }
            for (phase, colors) in byPhase {
                #expect(colors.count == 1, "\(appearance) \(phase): \(colors)")
            }
            let lifecycle = [ThemePhase.active, .done, .failed].compactMap { byPhase[$0]?.first }
            #expect(Set(lifecycle).count == 3, "\(appearance): \(lifecycle)")
        }
        let fills: [ThemeAppearance] = switch name {
        case "System": [.light, .dark]
        case "Shipyard Dark", "Paper Dark", "Ocean", "Sunset": [.dark]
        default: [.light]
        }
        #expect(theme.appearances == fills)
        for appearance in ThemeAppearance.allCases {
            #expect(fills.contains(theme.drawn(appearance)))
        }
    }

    @Test("a theme's circle in the Theme submenu is its panel and its accent in the appearance it draws: a one-appearance theme's own in both, System's the macOS colours of the appearance")
    func swatches() throws {
        let white = RGBA(r: 1, g: 1, b: 1)
        let system = BuiltInThemes.system
        #expect(system.swatch(.light) == ThemeSwatch(panel: SystemColor.windowBackground.reference(.light).over(white), accent: SystemColor.accent.reference(.light)))
        #expect(system.swatch(.dark).panel == SystemColor.windowBackground.reference(.dark))
        #expect(system.swatch(.light) != system.swatch(.dark))
        // System follows the live colours the app passes, such as a purple accent.
        let purple = RGBA(hex: "#953D96")!
        #expect(system.swatch(.light) { shade, appearance in shade.color == .accent ? purple : shade.reference(appearance) }.accent == purple)

        let expected: [String: (panel: String?, accent: String)] = [
            "Shipyard Light": (nil, "#2F6BDE"), "Shipyard Dark": (nil, "#6D9CFF"),
            "Paper Light": ("#FAF6EE", "#B4491E"), "Paper Dark": ("#221C1D", "#E3CFA8"),
            "Harbor": (nil, "#0E7C86"), "Heather": ("#FAF9FC", "#6A4FB0"), "Brass": ("#FBF9F3", "#8A6100"),
            "Ocean": ("#0F1830", "#4FC3F7"), "Sunset": (nil, "#FB923C"),
        ]
        for (name, colours) in expected {
            let theme = try #require(BuiltInThemes.named(name))
            let own = try #require(theme.appearances.first)
            #expect(theme.swatch(.light) == theme.swatch(.dark), "\(name) draws one appearance")
            let swatch = theme.swatch(.light)
            #expect(swatch.accent == RGBA(hex: colours.accent)!, "\(name)")
            let panel = colours.panel.flatMap { RGBA(hex: $0) } ?? SystemColor.windowBackground.reference(own)
            #expect(swatch.panel == panel, "\(name)")
        }
    }

    @Test("a text tier with too little contrast on the panel is a shortfall, named with its ratio and the one it needs")
    func contrastShortfall() throws {
        let (theme, issues) = ThemeReader.theme("""
            name = "Faint"
            version = 1
            [surface]
            panel = "#ffffff"
            [text]
            primary = "#000000"
            secondary = "#000000"
            seen = "#000000"
            tertiary = "#b0b0b0"
            [dark.surface]
            panel = "#00000080"
            """, file: "Faint.toml", source: .builtIn, library: BuiltInThemes.definitions)
        #expect(issues.isEmpty)
        let shortfalls = ThemeContrast.shortfalls(try #require(theme))
        #expect(shortfalls.map(\.description) == [
            "light `text.tertiary` is 2.1:1 on `surface.panel`; it needs 3:1",
            "dark `text.primary` is 1:1 on `surface.panel`; it needs 4.5:1",
            "dark `text.secondary` is 1:1 on `surface.panel`; it needs 4.5:1",
            "dark `text.seen` is 1:1 on `surface.panel`; it needs 4.5:1",
        ])
    }
}
