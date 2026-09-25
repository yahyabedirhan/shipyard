import AppKit
import ShipyardCore
import SwiftUI

/// GitHub's colours for the menu model's semantic states, in light and dark.
enum Palette {
    static let green = dynamic(light: 0x1A7F37, dark: 0x3FB950)
    static let gray = dynamic(light: 0x59636E, dark: 0x9198A1)
    static let purple = dynamic(light: 0x8250DF, dark: 0xAB7DF8)
    static let red = dynamic(light: 0xD1242F, dark: 0xF85149)
    static let amber = dynamic(light: 0x9A6700, dark: 0xD29922)

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

    /// The row's icon (SF Symbols has no GitHub octicons).
    static func symbol(_ state: ItemState, kind: ItemKind) -> String {
        switch (kind, state) {
        case (.pullRequest, .merged): "arrow.triangle.merge"
        case (.pullRequest, .closed): "xmark.circle"
        case (.pullRequest, _): "arrow.triangle.pull"
        case (.issue, .closed): "checkmark.circle"
        case (.issue, _): "smallcircle.filled.circle"
        case (.workflowRun, .running): "clock"
        case (.workflowRun, .failed): "xmark.circle.fill"
        case (.workflowRun, _): "checkmark.circle.fill"
        }
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        })
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
