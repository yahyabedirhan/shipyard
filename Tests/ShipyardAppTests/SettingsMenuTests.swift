import AppKit
import ShipyardConfig
import ShipyardCore
@testable import ShipyardApp
import Testing

@MainActor
@Suite("The settings menu and its Theme submenu")
struct SettingsMenuTests {
    private static let tide = Theme(name: "Tide", source: .file(URL(fileURLWithPath: "/themes/Tide.toml"))) { token, _ in
        token == .accent ? .color(RGBA(hex: "#2E7357")!) : .system
    }

    private func menu(picked: @escaping (String) -> Void = { _ in }) -> NSMenu {
        let library = ThemeLibrary(BuiltInThemes.themes + [Self.tide])
        let items = PanelText.settingsMenu(SetupStatus(cli: .linked), canSignOut: true)
        return SettingsMenu.make(
            items,
            themes: ThemeMenu(library, current: BuiltInThemes.named("Ocean")!),
            appearance: .light,
            actions: SettingsMenu.Actions(openConfiguration: {}, show: { _ in }, signOut: {}, pickTheme: picked)
        )
    }

    @Test("the menu lists the configuration file and Theme, a separator, the Set up items with their marks, a separator and Sign out")
    func items() throws {
        let menu = menu()
        #expect(menu.items.map { $0.isSeparatorItem ? "—" : $0.title } == [
            "Open configuration file", "Theme", "—", "Set up GitHub", "Set up Notion", "Set up /shipyard skill", "Set up shipyard command", "—", "Sign out",
        ])
        #expect(menu.items.first { $0.title == "Set up shipyard command" }?.badge?.stringValue == PanelText.setUpMark)
        #expect(menu.items.first { $0.title == "Set up GitHub" }?.badge == nil)
        #expect(menu.items.first { $0.title == "Theme" }?.submenu != nil)
    }

    @Test("the Theme submenu lists the built-in themes, a separator, the theme files; the current one checked, each with its circle at the trailing edge; a click picks the theme")
    func themes() throws {
        var picked: [String] = []
        let submenu = try #require(menu { picked.append($0) }.items.first { $0.title == "Theme" }?.submenu)
        func name(_ item: NSMenuItem) -> String? { item.representedObject as? String }
        #expect(submenu.items.map { $0.isSeparatorItem ? "—" : name($0) ?? "" } == BuiltInThemes.themes.map(\.name) + ["—", "Tide"])
        #expect(submenu.items.filter { $0.state == .on }.map(name) == ["Ocean"])

        for item in submenu.items where !item.isSeparatorItem {
            let title = try #require(item.attributedTitle)
            #expect(title.string == (name(item) ?? "") + "\t\u{FFFC}", "the name, a tab, then the circle")
            let style = try #require(title.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
            #expect(style.tabStops.map(\.alignment) == [.right], "the circle is right-aligned at the row's trailing edge")
            let attachment = try #require(title.attribute(.attachment, at: title.length - 1, effectiveRange: nil) as? NSTextAttachment)
            #expect(attachment.image?.size == NSSize(width: SettingsMenu.circleSide, height: SettingsMenu.circleSide))
            #expect(attachment.image?.isTemplate == false)
        }

        let tide = try #require(submenu.items.first { name($0) == "Tide" })
        _ = (tide.target as? NSObject)?.perform(tide.action, with: tide)
        #expect(picked == ["Tide"])
    }

    @Test("the circle splits the panel on the left from the accent on the right")
    func circle() throws {
        let swatch = ThemeSwatch(panel: RGBA(r: 1, g: 0, b: 0), accent: RGBA(r: 0, g: 0, b: 1))
        let image = SettingsMenu.circle(swatch, appearance: .light)
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 28, pixelsHigh: 28, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let left = try #require(bitmap.colorAt(x: 8, y: 14)?.usingColorSpace(.sRGB))
        let right = try #require(bitmap.colorAt(x: 20, y: 14)?.usingColorSpace(.sRGB))
        #expect(left.redComponent > 0.9 && left.blueComponent < 0.1)
        #expect(right.blueComponent > 0.9 && right.redComponent < 0.1)
    }
}
