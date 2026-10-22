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

/// The custom example theme the documentation ships: Tide, which extends
/// Shipyard Light with a deep green accent.
private let tide: String = {
    let url = repositoryRoot.appendingPathComponent("docs/themes/example-custom.toml")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}()

private let green = ThemeValue.color(RGBA(hex: "#2E7357")!)

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
    @Test("the panel draws System without the key, and the theme the key names with it, from the first read")
    func configured() async throws {
        let plain = try await Harness.started(config: shop, graphQL: answer(1))
        #expect(plain.shipyard.theme == BuiltInThemes.system)

        let paper = try await Harness.started(config: "theme = \"paper dark\"\n\n" + shop, graphQL: answer(1))
        #expect(paper.shipyard.theme == BuiltInThemes.named("Paper Dark"))
    }

    @Test("changing the theme changes the panel's theme at once; an unknown name keeps it, with the configuration error")
    func liveChange() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(1))

        try harness.writeConfig("theme = \"Ocean\"\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.theme == BuiltInThemes.named("Ocean"))

        try harness.writeConfig("theme = \"Ocen\"\n\n" + shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError?.issues == [ConfigurationIssue(line: 1, message: """
            unknown theme `Ocen` (did you mean `Ocean`? expected one of `System`, `Shipyard Light`, `Shipyard Dark`, \
            `Paper Light`, `Paper Dark`, `Harbor`, `Heather`, `Brass`, `Ocean`, `Sunset`)
            """)])
        #expect(harness.shipyard.theme == BuiltInThemes.named("Ocean"))

        try harness.writeConfig(shop)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.theme == BuiltInThemes.system)
    }

    @Test("a theme file the key names draws in the panel; a saved file applies at once; a broken one keeps the last good theme, with the banner")
    func liveThemeFile() async throws {
        let harness = try await Harness.started(config: "theme = \"tide\"\n\n" + shop, graphQL: answer(1))
        try #require(harness.shipyard.configError != nil, "Tide isn't a theme before its file is saved")

        try harness.writeTheme("Tide.toml", tide)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError == nil)
        let theme = harness.shipyard.theme
        let parent = try #require(BuiltInThemes.named("Shipyard Light"))
        #expect(theme.name == "Tide")
        #expect(theme.appearances == [.light], "it extends Shipyard Light, so it is light too")
        #expect(theme.value(.accent, .light) == green)
        #expect(theme.value(.accent, .light) != parent.value(.accent, .light))
        #expect(theme.value(.header, .light) == parent.value(.header, .light))

        try harness.writeTheme("Tide.toml", tide.replacingOccurrences(of: "green = \"#2E7357\"", with: "green = \"#0F766E\""))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.theme.value(.accent, .light) == .color(RGBA(hex: "#0F766E")!))
        let good = harness.shipyard.theme

        try harness.writeTheme("Tide.toml", tide.replacingOccurrences(of: "accent = \"green\"", with: "accent = \"gren\""))
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.theme == good)
        let banner = try #require(harness.shipyard.banners(at: harness.clock.now).first { $0.id == "themes" })
        #expect(banner.kind == .configError)
        #expect(banner.text == """
            themes/Tide.toml line 24: `accent.accent` is "gren", which isn't a palette name, a color or `system`
            A theme keeps the version that last read until its file is fixed.
            """)

        try harness.writeTheme("Tide.toml", tide)
        await harness.shipyard.reloadConfiguration()
        #expect(harness.shipyard.theme.value(.accent, .light) == green)
        #expect(!harness.shipyard.banners(at: harness.clock.now).contains { $0.id == "themes" })
    }

    @Test("a theme file that never read keeps the rest of the configuration: the panel draws System, with a warning and the banner")
    func brokenAtStart() async throws {
        let harness = try Harness(stored: "gho_stored", config: "theme = \"Tide\"\nversion = 1\n\n" + shop)
        try harness.writeTheme("Tide.toml", tide.replacingOccurrences(of: "extends = \"Shipyard Light\"", with: "extends = \"Shipyard\""))
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([answer(1)])
        await harness.shipyard.start()

        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.configWarnings == [ConfigurationIssue(
            line: 1,
            message: "theme `Tide` isn't one shipyard has read, and `themes/Tide.toml` has a problem; the panel draws System until it reads"
        )])
        #expect(harness.shipyard.theme == BuiltInThemes.system)
        #expect(harness.section("shop") != nil)
        #expect(harness.shipyard.themeIssues.map(\.description)
            == ["""
                themes/Tide.toml line 11: `extends` names "Shipyard", which isn't a theme (expected one of `Brass`, `Harbor`, `Heather`, \
                `Ocean`, `Paper Dark`, `Paper Light`, `Shipyard Dark`, `Shipyard Light`, `Sunset`, `System`, `Tide`)
                """])
    }

    @Test("the Theme submenu lists the built-in themes, then the theme files, the current one checked; picking one writes it and the panel draws it at once")
    func themeSubmenu() async throws {
        let harness = try await Harness.started(config: "# my theme\ntheme = \"Ocean\"\n\n" + shop, graphQL: answer(1), answer(1), answer(1))
        try harness.writeTheme("Tide.toml", tide)
        await harness.shipyard.reloadConfiguration()

        var menu = harness.shipyard.themeMenu
        #expect(menu.builtIn.map(\.theme.name) == BuiltInThemes.themes.map(\.name))
        #expect(menu.files.map(\.theme.name) == ["Tide"])
        #expect((menu.builtIn + menu.files).filter(\.isCurrent).map(\.theme.name) == ["Ocean"])

        await harness.shipyard.switchTheme(to: "Tide")
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.theme.name == "Tide")
        #expect(try String(contentsOf: harness.configURL, encoding: .utf8) == "# my theme\ntheme = \"Tide\"\n\n" + shop)
        menu = harness.shipyard.themeMenu
        #expect((menu.builtIn + menu.files).filter(\.isCurrent).map(\.theme.name) == ["Tide"])

        // A file that doesn't read changes nothing, and the banner says why.
        let broken = "theme = \"Tide\"\nrefresh-interval = 3\n\n" + shop
        try harness.writeConfig(broken)
        await harness.shipyard.switchTheme(to: "Brass")
        #expect(harness.shipyard.configError != nil)
        #expect(harness.shipyard.theme.name == "Tide")
        #expect(try String(contentsOf: harness.configURL, encoding: .utf8) == broken)
    }

    @Test("a theme file named after a built-in theme replaces it in place in the Theme submenu")
    func replacingFile() async throws {
        let harness = try await Harness.started(config: shop, graphQL: answer(1))
        try harness.writeTheme("Mine.toml", "name = \"harbor\"\nversion = 1\nextends = \"Shipyard Light\"\n")
        await harness.shipyard.reloadConfiguration()
        let menu = harness.shipyard.themeMenu
        #expect(menu.builtIn.map(\.theme.name.localizedLowercase) == BuiltInThemes.themes.map(\.name.localizedLowercase))
        #expect(menu.builtIn.first { $0.theme.name == "harbor" }?.theme.source != .builtIn)
        #expect(menu.files.isEmpty)
        #expect(menu.builtIn.filter(\.isCurrent).map(\.theme.name) == ["System"])
    }

    @Test("a theme of the user's own doesn't stop the layout button or a ping's project")
    func ownThemeElsewhere() async throws {
        let harness = try await Harness.started(config: "theme = \"Tide\"\n\n" + shop, graphQL: answer(1), answer(1))
        try harness.writeTheme("Tide.toml", tide)
        await harness.shipyard.reloadConfiguration()
        try #require(harness.shipyard.theme.name == "Tide")

        await harness.shipyard.switchToNextLayout()
        #expect(harness.shipyard.configError == nil)
        #expect(harness.shipyard.configStore.lastValid.menu.layout == .tabs)

        #expect(harness.cli("ping", "send", "Ready", "--project", "shop").status == 0)
    }
}
