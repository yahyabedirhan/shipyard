import AppKit
import ShipyardConfig
import ShipyardCore

/// The header's settings menu, built as an NSMenu so the Theme submenu can
/// draw each theme's circle at the trailing edge of its row, which a SwiftUI
/// menu has no place for. Built again at each click, so it always shows the
/// themes and set-up marks as they are.
@MainActor
enum SettingsMenu {
    /// What the menu's items do.
    struct Actions {
        var openConfiguration: () -> Void
        var show: (SetupPart) -> Void
        var signOut: () -> Void
        var pickTheme: (String) -> Void
    }

    /// The circle's side, in points.
    static let circleSide: CGFloat = 14

    /// The menu: `items` in order, a separator after the Theme submenu and
    /// before Sign out; `appearance` is the one the menu draws in, for
    /// System's circle.
    static func make(_ items: [PanelText.SettingsItem], themes: ThemeMenu, appearance: ThemeAppearance, actions: Actions) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items {
            switch item.action {
            case .openConfiguration:
                menu.addItem(ActionMenuItem(title: item.title, run: actions.openConfiguration))
            case .theme:
                let theme = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                theme.submenu = themeMenu(themes, appearance: appearance, pick: actions.pickTheme)
                menu.addItem(theme)
                menu.addItem(.separator())
            case .open(let part):
                let entry = ActionMenuItem(title: item.title) { actions.show(part) }
                if item.isChecked { entry.badge = NSMenuItemBadge(string: PanelText.setUpMark) }
                menu.addItem(entry)
            case .signOut:
                menu.addItem(.separator())
                menu.addItem(ActionMenuItem(title: item.title, run: actions.signOut))
            }
        }
        return menu
    }

    /// The Theme submenu: the built-in themes, a separator, the theme
    /// files' themes; a check mark on the current one, and each theme's
    /// circle at the trailing edge, its panel on the left and its accent on
    /// the right, as it draws while the menu is in `appearance`.
    static func themeMenu(_ themes: ThemeMenu, appearance: ThemeAppearance, pick: @escaping (String) -> Void) -> NSMenu {
        let menu = NSMenu(title: PanelText.themeMenuTitle)
        menu.autoenablesItems = false
        let font = NSFont.menuFont(ofSize: 0)
        let all = themes.builtIn + themes.files
        let widest = all.map { ($0.theme.name as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let tab = ceil(widest) + 24 + circleSide
        for (index, entry) in all.enumerated() {
            if index == themes.builtIn.count, index > 0 { menu.addItem(.separator()) }
            let name = entry.theme.name
            let item = ActionMenuItem(title: name) { pick(name) }
            item.representedObject = name
            item.state = entry.isCurrent ? .on : .off
            item.attributedTitle = title(name, swatch: entry.theme.swatch(appearance, system: SystemColors.rgba), appearance: appearance, font: font, tab: tab)
            menu.addItem(item)
        }
        return menu
    }

    /// A theme's row: its name, then its circle right-aligned at `tab`.
    static func title(_ name: String, swatch: ThemeSwatch, appearance: ThemeAppearance, font: NSFont, tab: CGFloat) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .right, location: tab)]
        let attachment = NSTextAttachment()
        attachment.image = circle(swatch, appearance: appearance)
        attachment.bounds = CGRect(x: 0, y: (font.capHeight - circleSide) / 2, width: circleSide, height: circleSide)
        let title = NSMutableAttributedString(string: name + "\t", attributes: [.font: font, .paragraphStyle: style])
        title.append(NSAttributedString(attachment: attachment))
        title.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: title.length))
        return title
    }

    /// The circle: split down the middle, the panel on the left and the
    /// accent on the right, inside a hairline rim in the label colour.
    static func circle(_ swatch: ThemeSwatch, appearance: ThemeAppearance) -> NSImage {
        let side = circleSide
        let rim = appearance == .dark ? NSColor(white: 1, alpha: 0.22) : NSColor(white: 0, alpha: 0.22)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let disc = NSBezierPath(ovalIn: rect)
            NSGraphicsContext.saveGraphicsState()
            disc.addClip()
            nsColor(swatch.panel).setFill()
            NSRect(x: 0, y: 0, width: rect.width / 2, height: rect.height).fill()
            nsColor(swatch.accent).setFill()
            NSRect(x: rect.width / 2, y: 0, width: rect.width / 2, height: rect.height).fill()
            NSGraphicsContext.restoreGraphicsState()
            rim.setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
            ring.lineWidth = 0.5
            ring.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = nil
        return image
    }

    private static func nsColor(_ rgba: RGBA) -> NSColor {
        NSColor(srgbRed: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
    }
}

/// A menu item that runs a closure: the settings menu's and a header
/// count's page menu.
final class ActionMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(choose), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not decoded") }

    @objc private func choose() { run() }
}
