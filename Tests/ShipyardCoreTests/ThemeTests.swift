import Foundation
import ShipyardConfig
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let shop = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    """

/// The custom example theme the documentation ships: Sunset, which extends
/// Shipyard with a coral accent.
private let sunset: String = {
    let url = repositoryRoot.appendingPathComponent("docs/themes/example-custom.toml")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}()

private func coral(_ appearance: ThemeAppearance) -> ThemeValue {
    .color(RGBA(hex: appearance == .light ? "#C2410C" : "#FB923C")!)
}

extension Harness {
    /// Saves `text` as `themes/<name>` beside the configuration file.
    func writeTheme(_ name: String, _ text: String) throws {
        let folder = ThemeFiles.folder(beside: configURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: folder.appendingPathComponent(name))
    }
}

private func answer(_ numbers: Int...) -> StubHTTP.Answer {
    PullRequestsResponse("yahyabedirhan/shop", numbers.map { PullRequestsResponse.PullRequest($0) }).answer
}

@MainActor
@Suite("The theme")
struct ThemeTests {
    @Test("the panel draws Shipyard without the key, and the theme the key names with it, from the first read")
    func configured() async throws {
        let plain = try await Harness.started(config: shop, graphQL: answer(1))
        #expect(plain.shipyard.theme == BuiltInThemes.shipyard)

        let paper = try await Harness.started(config: "theme = \"paper\"\n\n" + shop, graphQL: answer(1))
        #expect(paper.shipyard.theme == BuiltInThemes.named("Paper"))
    }

    @Test("changing the theme changes the panel's theme at once; an unknown name keeps it, with the configuration error")
    func liveChange() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(1))

        try harness.writeConfig("theme = \"Midnight\"\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.theme == BuiltInThemes.named("Midnight"))

        try harness.writeConfig("theme = \"Midnigt\"\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError?.issues
            == [ConfigurationIssue(line: 1, message: "unknown theme `Midnigt` (did you mean `Midnight`?)")])
        #expect(harness.shipyard.theme == BuiltInThemes.named("Midnight"))

        try harness.writeConfig(shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.theme == BuiltInThemes.shipyard)
    }

    @Test("a theme file the key names draws in the panel; a saved file applies at once; a broken one keeps the last good theme, with the banner")
    func liveThemeFile() async throws {
        let harness = try await Harness.started(config: "theme = \"sunset\"\n\n" + shop, graphQL: answer(1))
        try #require(harness.shipyard.configError != nil, "Sunset isn't a theme before its file is saved")

        try harness.writeTheme("Sunset.toml", sunset)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError == nil)
        let theme = harness.shipyard.theme
        #expect(theme.name == "Sunset")
        for appearance in ThemeAppearance.allCases {
            #expect(theme.value(.accent, appearance) == coral(appearance))
            #expect(theme.value(.accent, appearance) != BuiltInThemes.shipyard.value(.accent, appearance))
            #expect(theme.value(.panel, appearance) == BuiltInThemes.shipyard.value(.panel, appearance))
        }

        try harness.writeTheme("Sunset.toml", sunset.replacingOccurrences(of: "coral = \"#C2410C\"", with: "coral = \"#0F766E\""))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.theme.value(.accent, .light) == .color(RGBA(hex: "#0F766E")!))
        let good = harness.shipyard.theme

        try harness.writeTheme("Sunset.toml", sunset.replacingOccurrences(of: "accent = \"coral\"", with: "accent = \"corral\""))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.theme == good)
        let banner = try #require(harness.shipyard.banners(at: harness.clock.now).first { $0.id == "themes" })
        #expect(banner.kind == .configError)
        #expect(banner.text == """
            themes/Sunset.toml line 22: `accent.accent` is "corral", which isn't a palette name, a color or `system`
            A theme keeps the version that last read until its file is fixed.
            """)

        try harness.writeTheme("Sunset.toml", sunset)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.theme.value(.accent, .light) == coral(.light))
        #expect(!harness.shipyard.banners(at: harness.clock.now).contains { $0.id == "themes" })
    }

    @Test("a theme file that never read keeps the rest of the configuration: the panel draws Shipyard, with a warning and the banner")
    func brokenAtStart() async throws {
        let harness = try Harness(stored: "gho_stored", config: "theme = \"Sunset\"\nversion = 1\n\n" + shop)
        try harness.writeTheme("Sunset.toml", sunset.replacingOccurrences(of: "extends = \"Shipyard\"", with: "extends = \"Shipyrd\""))
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([answer(1)])
        await harness.shipyard.start()

        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.configWarnings == [ConfigurationIssue(
            line: 1,
            message: "theme `Sunset` isn't one shipyard has read, and `themes/Sunset.toml` has a problem; the panel draws Shipyard until it reads"
        )])
        #expect(harness.shipyard.theme == BuiltInThemes.shipyard)
        #expect(harness.section("shop") != nil)
        #expect(harness.shipyard.themeIssues.map(\.description)
            == ["themes/Sunset.toml line 9: `extends` names \"Shipyrd\", which isn't a theme"])
    }

    @Test("a theme of the user's own doesn't stop the layout button or a ping's project")
    func ownThemeElsewhere() async throws {
        let harness = try await Harness.started(config: "theme = \"Sunset\"\n\n" + shop, graphQL: answer(1), answer(1))
        try harness.writeTheme("Sunset.toml", sunset)
        await harness.shipyard.reloadConfiguration()
        try #require(harness.shipyard.theme.name == "Sunset")

        await harness.shipyard.switchToNextLayout()
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.configStore.lastValid.menu.layout == .tabs)

        #expect(harness.cli("ping", "send", "Ready", "--project", "shop").status == 0)
    }
}
