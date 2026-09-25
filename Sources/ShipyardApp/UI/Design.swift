import AppKit
import ShipyardCore
import SwiftUI

// The panel's design tokens, shared by the frame (header, banners, footer,
// onboarding) and every layout: the spacing grid, the type scale, the
// colours for light and dark, and the motion.

/// The spacing grid: everything is a multiple of 2, most of 4.
enum Grid {
    /// The panel's width.
    static let panelWidth: CGFloat = 400
    /// The panel's side padding.
    static let gutter: CGFloat = 12
    /// The header's height.
    static let titleBarHeight: CGFloat = 38
    /// One item.
    static let rowHeight: CGFloat = 24
    /// A project's header.
    static let headerHeight: CGFloat = 26
    /// The attention dot's column.
    static let dotColumn: CGFloat = 10
    /// The state icon's column.
    static let iconColumn: CGFloat = 16
    /// The number's column.
    static let numberColumn: CGFloat = 30
    /// The author's, or the repository's, column.
    static let metaColumn: CGFloat = 74
    /// The age's column.
    static let ageColumn: CGFloat = 26
    /// How far a row's hover highlight sits in from the panel's edges.
    static let inset: CGFloat = 4
    /// The tallest the scrolling area gets before it scrolls.
    static let maxListHeight: CGFloat = 560
    /// Rounded corners: small controls, and cards and banners.
    static let smallRadius: CGFloat = 5
    static let radius: CGFloat = 7
    /// The tabs layout: the widest a tab's title gets, how far the strip's
    /// ends fade where tabs are hidden past them, and how far the list
    /// slides when the tab changes.
    static let maxTabTitleWidth: CGFloat = 140
    static let tabFade: CGFloat = 24
    static let tabSlide: CGFloat = 40
}

/// The type scale: one family (SF Pro), a few sizes, weights for emphasis,
/// monospaced digits wherever a number sits.
enum TypeScale {
    /// The panel's heading, and a screen's title.
    static let title = Font.system(size: 13, weight: .semibold)
    /// A larger heading, on the connect screen.
    static let display = Font.system(size: 14, weight: .semibold)
    /// Body text: a row's title, a screen's message.
    static let body = Font.system(size: 12)
    static let bodyEmphasis = Font.system(size: 12, weight: .semibold)
    static let button = Font.system(size: 12, weight: .medium)
    /// Numbers, authors, ages; banner text.
    static let meta = Font.system(size: 11).monospacedDigit()
    /// A project's name.
    static let section = Font.system(size: 11, weight: .semibold)
    /// A small uppercase header over a kind's rows, in the tabs layout.
    static let eyebrow = Font.system(size: 10, weight: .semibold)
    /// The footer, and small print.
    static let caption = Font.system(size: 10.5).monospacedDigit()
    static let captionEmphasis = Font.system(size: 10.5, weight: .medium)
    /// A count in a capsule.
    static let badge = Font.system(size: 10, weight: .bold).monospacedDigit()
    /// A command to copy, and a run's branch.
    static let code = Font.system(size: 12, weight: .medium, design: .monospaced)
    static let branch = Font.system(size: 10.5, weight: .medium, design: .monospaced)
}

/// The motion: springs for what moves, a short ease for hover.
enum Motion {
    /// A project collapsing or expanding.
    static let collapse = Animation.spring(duration: 0.32, bounce: 0.08)
    /// A count rolling to its new number.
    static let count = Animation.spring(duration: 0.4, bounce: 0.2)
    /// A banner sliding in or out.
    static let banner = Animation.spring(duration: 0.35, bounce: 0.1)
    /// Marking seen: the dot fading, the title losing its weight.
    static let seen = Animation.easeOut(duration: 0.5)
    /// Hover and press highlights.
    static let hover = Animation.easeOut(duration: 0.12)
    /// The tabs layout's selected pill sliding, and its list following.
    static let tab = Animation.spring(response: 0.36, dampingFraction: 0.86)
}

/// The colours, each resolving for light or dark: GitHub's colours for the
/// menu model's semantic states, and the panel's surfaces.
enum Palette {
    // MARK: States

    static let green = dynamic(light: 0x1A7F37, dark: 0x3FB950)
    static let gray = dynamic(light: 0x59636E, dark: 0x9198A1)
    static let purple = dynamic(light: 0x8250DF, dark: 0xAB7DF8)
    static let red = dynamic(light: 0xD1242F, dark: 0xF85149)
    static let amber = dynamic(light: 0x9A6700, dark: 0xD29922)
    /// The attention dot, the count badge, a prominent button.
    static let accent = dynamic(light: 0x006BED, dark: 0x4A94FF)

    // MARK: Surfaces

    /// A project's header, opaque so rows scroll under it.
    static let header = dynamic(light: 0xF6F6F8, dark: 0x2A2A2D)
    /// Under the check dot, to cut it out of the state icon.
    static let panel = dynamic(light: 0xFBFBFC, dark: 0x252528)
    /// The footer.
    static let chrome = dynamic(light: 0xF3F3F5, dark: 0x202023, alpha: 0.6)
    /// Hairlines between the header, the list and the footer, and between kinds.
    static let separator = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.065, darkAlpha: 0.07)
    /// Around cards, command boxes and secondary buttons.
    static let border = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.1, darkAlpha: 0.12)
    /// A hovered row or button.
    static let hover = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.075)
    /// A pressed row or button.
    static let pressed = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.12)
    /// A card's, command box's or chip's fill.
    static let fill = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.045, darkAlpha: 0.06)
    /// The tabs layout's strip, sunk under its pills.
    static let track = dynamic(light: 0xE8E8EB, dark: 0x18181A)
    /// The selected tab's pill, raised off the track, and its shadow.
    static let raised = dynamic(light: 0xFFFFFF, dark: 0x3F3F44)
    static let raisedShadow = dynamic(light: 0x000000, dark: 0x000000, lightAlpha: 0.08, darkAlpha: 0.35)

    // MARK: What the model says

    /// A row's colour, by kind: a pull request open green, draft gray,
    /// merged purple, closed red; an issue open green, closed purple; a
    /// workflow run running amber, succeeded green, failed red.
    static func color(_ state: ItemState, kind: ItemKind) -> Color {
        switch state {
        case .open, .succeeded: green
        case .draft: gray
        case .merged: purple
        case .closed: kind == .issue ? purple : red
        case .running: amber
        case .failed: red
        }
    }

    /// The check dot: pending amber, passed green, failed red; no dot
    /// when there are no checks.
    static func color(_ checks: ChecksState) -> Color? {
        switch checks {
        case .none: nil
        case .pending: amber
        case .passed: green
        case .failed: red
        }
    }

    /// The rate-limit text: normal in the secondary colour, low amber,
    /// exhausted red.
    static func color(_ level: RateLevel) -> Color {
        switch level {
        case .normal: .secondary
        case .low: amber
        case .exhausted: red
        }
    }

    /// The rate-limit bar: normal green, low amber, exhausted red.
    static func bar(_ level: RateLevel) -> Color {
        switch level {
        case .normal: green.opacity(0.65)
        case .low: amber
        case .exhausted: red
        }
    }

    /// The row's icon (SF Symbols has no GitHub octicons).
    static func symbol(_ state: ItemState, kind: ItemKind) -> String {
        switch (kind, state) {
        case (.pullRequest, .merged): "arrow.triangle.merge"
        case (.pullRequest, _): "arrow.triangle.pull"
        case (.issue, .closed): "checkmark.circle"
        case (.issue, _): "smallcircle.filled.circle"
        case (.workflowRun, .running): "arrow.triangle.2.circlepath.circle.fill"
        case (.workflowRun, .failed): "xmark.circle.fill"
        case (.workflowRun, _): "checkmark.circle.fill"
        }
    }

    // MARK: Building them

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
