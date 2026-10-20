import AppKit
import ShipyardConfig
import ShipyardCore
import SwiftUI

enum Grid {
    static let panelWidth: CGFloat = 400
    static let gutter: CGFloat = 12
    static let titleBarHeight: CGFloat = 38
    static let rowHeight: CGFloat = 24
    static let headerHeight: CGFloat = 26
    static let dotColumn: CGFloat = 10
    static let iconColumn: CGFloat = 16
    static let numberColumn: CGFloat = 30
    static let metaColumn: CGFloat = 74
    static let agentMark: CGFloat = 14
    static let ageColumn: CGFloat = 26
    static let chipGap: CGFloat = 6
    static let inset: CGFloat = 4
    static let maxListHeight: CGFloat = 560
    static let smallRadius: CGFloat = 5
    static let radius: CGFloat = 7
    static let maxTabTitleWidth: CGFloat = 140
    static let tabFade: CGFloat = 24
    static let tabSlide: CGFloat = 40
}

/// The list layout's tighter scale, from the frame's: 22 pt rows, a 22 pt
/// project header, narrower columns and smaller radii.
enum ListGrid {
    static let gutter = Grid.gutter
    static let rowHeight = Grid.rowHeight - 2
    static let headerHeight = Grid.headerHeight - 4
    static let dotColumn: CGFloat = 8
    static let iconColumn: CGFloat = 14
    static let numberColumn: CGFloat = 28
    static let metaColumn: CGFloat = 68
    static let agentMark: CGFloat = 12
    static let ageColumn: CGFloat = 24
    static let chipGap: CGFloat = 4
    static let radius: CGFloat = 5
}

/// The list layout's type: smaller steps from the 12 pt body, with
/// hierarchy by weight and by the text tiers.
enum ListType {
    private static let base: CGFloat = 12
    static let body = Font.system(size: base)
    static let bodyEmphasis = Font.system(size: base, weight: .semibold)
    static let meta = Font.system(size: base - 1.5).monospacedDigit()
    static let section = Font.system(size: base - 0.5, weight: .semibold)
    static let eyebrow = Font.system(size: base - 2.5, weight: .semibold)
    static let caption = Font.system(size: base - 2).monospacedDigit()
    static let badge = Font.system(size: base - 2, weight: .medium).monospacedDigit()
    static let branch = Font.system(size: base - 2, design: .monospaced)
}

enum TypeScale {
    static let title = Font.system(size: 13, weight: .semibold)
    static let display = Font.system(size: 14, weight: .semibold)
    static let body = Font.system(size: 12)
    static let bodyEmphasis = Font.system(size: 12, weight: .semibold)
    static let button = Font.system(size: 12, weight: .medium)
    static let meta = Font.system(size: 11).monospacedDigit()
    static let section = Font.system(size: 11, weight: .semibold)
    static let eyebrow = Font.system(size: 10, weight: .semibold)
    static let caption = Font.system(size: 10.5).monospacedDigit()
    static let captionEmphasis = Font.system(size: 10.5, weight: .medium)
    static let badge = Font.system(size: 10, weight: .bold).monospacedDigit()
    static let code = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let branch = Font.system(size: 10.5, weight: .medium, design: .monospaced)
}

enum Motion {
    static let collapse = Animation.spring(duration: 0.32, bounce: 0.08)
    static let count = Animation.spring(duration: 0.4, bounce: 0.2)
    static let tint = Animation.easeInOut(duration: 0.2)
    static let banner = Animation.spring(duration: 0.35, bounce: 0.1)
    static let seen = Animation.easeOut(duration: 0.5)
    static let hover = Animation.easeOut(duration: 0.12)
    static let highlight = Animation.spring(duration: 0.25, bounce: 0.1)
    static let tab = Animation.spring(response: 0.36, dampingFraction: 0.86)
}

enum Palette {

    static let green = dynamic(light: 0x1A7F37, dark: 0x3FB950)
    static let gray = dynamic(light: 0x59636E, dark: 0x9198A1)
    static let purple = dynamic(light: 0x8250DF, dark: 0xAB7DF8)
    static let red = dynamic(light: 0xD1242F, dark: 0xF85149)
    static let amber = dynamic(light: 0x9A6700, dark: 0xD29922)
    static let accent = dynamic(light: 0x006BED, dark: 0x4A94FF)
    static let lease = Color(nsColor: .systemYellow)

    static let header = dynamic(light: 0xF6F6F8, dark: 0x2A2A2D)
    static let panel = dynamic(light: 0xFBFBFC, dark: 0x252528)
    static let chrome = dynamic(light: 0xF3F3F5, dark: 0x202023, alpha: 0.6)
    static let separator = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.065, darkAlpha: 0.07)
    static let border = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.1, darkAlpha: 0.12)
    static let hover = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.075)
    static let pressed = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.12)
    static let fill = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.06)
    static let track = dynamic(light: 0xE8E8EB, dark: 0x18181A)
    static let raised = dynamic(light: 0xFFFFFF, dark: 0x3F3F44)
    static let raisedShadow = dynamic(light: 0x000000, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.35)

    static func color(_ state: ItemState, kind: ItemKind) -> Color {
        if kind == .ping || kind == .note { return gray }
        return switch state {
        case .open, .succeeded: green
        case .draft: gray
        case .merged: purple
        case .closed: kind == .issue ? purple : red
        case .running: amber
        case .failed: red
        }
    }

    static func color(_ checks: ChecksState) -> Color? {
        switch checks {
        case .none: nil
        case .pending: amber
        case .passed: green
        case .failed: red
        }
    }

    static func symbol(_ state: ItemState, kind: ItemKind) -> String {
        switch (kind, state) {
        case (.pullRequest, .merged): "arrow.triangle.merge"
        case (.issue, .closed): "checkmark.circle"
        case (.workflowRun, .running): "arrow.triangle.2.circlepath.circle.fill"
        case (.workflowRun, .failed): "xmark.circle.fill"
        case (.workflowRun, _): "checkmark.circle.fill"
        default: symbol(kind)
        }
    }

    static func symbol(_ kind: ItemKind) -> String {
        switch kind {
        case .pullRequest: "arrow.triangle.pull"
        case .issue: "smallcircle.filled.circle"
        case .workflowRun: "arrow.triangle.2.circlepath"
        case .ping: "bell.fill"
        case .note: "note.text"
        }
    }

    static func symbol(_ icon: PingIcon) -> String {
        switch icon {
        case .link: "link"
        case .app: "macwindow"
        case .terminal: "terminal"
        case .noAction: "bell.fill"
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        dynamic(light: light, dark: dark, lightAlpha: alpha, darkAlpha: alpha)
    }

    private static func dynamic(light: UInt32, dark: UInt32, lightAlpha: CGFloat, darkAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
