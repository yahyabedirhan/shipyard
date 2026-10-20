import ShipyardConfig
import ShipyardCore
import SwiftUI

/// The panel's sizes and type at one theme's font, density and shape knobs.
/// It is resolved once where the theme is set (`EnvironmentValues.theme`),
/// and views read it from the environment's `panelScale`, so a row reads
/// its sizes and builds nothing. The Shipyard theme's knobs give the
/// panel's long-standing grid, and the design lab's 6 and 8 pt corners.
struct PanelScale: Equatable {
    let knobs: ThemeKnobs
    /// The frame's and the tabs layout's grid and type.
    let grid: Grid
    let type: TypeScale
    /// The list layout's tighter grid and type.
    let list: ListGrid
    let listType: ListType

    init(_ knobs: ThemeKnobs) {
        self.knobs = knobs
        grid = Grid(knobs)
        type = TypeScale(knobs)
        list = ListGrid(knobs)
        listType = ListType(knobs)
    }

    /// The Shipyard theme's scale, for views with no theme set above them.
    static let shipyard = PanelScale(BuiltInThemes.shipyard.knobs)

    /// A shared row piece's sizes and type, in the layout `style` draws.
    func rowHeight(_ style: PanelStyle) -> CGFloat { style == .list ? list.rowHeight : grid.rowHeight }
    func meta(_ style: PanelStyle) -> Font { style == .list ? listType.meta : type.meta }
    func eyebrow(_ style: PanelStyle) -> Font { style == .list ? listType.eyebrow : type.eyebrow }

    /// How far a ping row's ✕ sits from the row's trailing edge: just
    /// before the age, so the age stays readable.
    func dismissTrailing(_ style: PanelStyle) -> CGFloat {
        style == .list ? list.gutter + ListGrid.ageColumn + 2 : grid.gutter + Grid.ageColumn + 2
    }
}

/// The frame's and the tabs layout's grid. The columns are fixed; the
/// gutter, the heights and the radii follow the theme's density and shape.
struct Grid: Equatable {
    static let panelWidth: CGFloat = 400
    static let dotColumn: CGFloat = 10
    static let iconColumn: CGFloat = 16
    static let numberColumn: CGFloat = 30
    static let metaColumn: CGFloat = 74
    static let agentMark: CGFloat = 14
    static let ageColumn: CGFloat = 26
    static let chipGap: CGFloat = 6
    static let inset: CGFloat = 4
    static let maxListHeight: CGFloat = 560
    static let maxTabTitleWidth: CGFloat = 140
    static let tabFade: CGFloat = 24
    static let tabSlide: CGFloat = 40

    /// The panel's side padding.
    let gutter: CGFloat
    /// The header's height.
    let titleBarHeight: CGFloat
    /// One item.
    let rowHeight: CGFloat
    /// A project's header.
    let headerHeight: CGFloat
    /// A two-line tabs row's padding above and below: 5 pt at the regular
    /// row, half a point more or less for each point the row grows or shrinks.
    let tabRowPadding: CGFloat
    /// Rounded corners, each the theme's `[shape]` knob in points: small
    /// controls, cards and banners, and the panel itself.
    let smallRadius: CGFloat
    let radius: CGFloat
    let largeRadius: CGFloat

    init(_ knobs: ThemeKnobs) {
        gutter = knobs.gutter
        titleBarHeight = knobs.bar
        rowHeight = knobs.row
        headerHeight = knobs.header
        tabRowPadding = max(1, 5 + (knobs.row - ThemeKnobs.standard.row) / 2)
        smallRadius = knobs.small
        radius = knobs.medium
        largeRadius = knobs.large
    }
}

/// The list layout's tighter scale, from the frame's: rows 2 pt shorter,
/// project headers 4 pt shorter, narrower columns and smaller radii.
struct ListGrid: Equatable {
    static let dotColumn: CGFloat = 8
    static let iconColumn: CGFloat = 14
    static let numberColumn: CGFloat = 28
    static let metaColumn: CGFloat = 68
    static let agentMark: CGFloat = 12
    static let ageColumn: CGFloat = 24
    static let chipGap: CGFloat = 4

    let gutter: CGFloat
    let rowHeight: CGFloat
    let headerHeight: CGFloat
    /// The frame's radii, 2 pt smaller, never below square.
    let smallRadius: CGFloat
    let radius: CGFloat

    init(_ knobs: ThemeKnobs) {
        gutter = knobs.gutter
        rowHeight = knobs.row - 2
        headerHeight = knobs.header - 4
        smallRadius = max(0, knobs.small - 2)
        radius = max(0, knobs.medium - 2)
    }
}

/// Builds fonts from the theme's font knob: the system text styles when the
/// theme keeps the system families at 12 pt, and sized fonts of its family
/// otherwise.
enum FontKit {
    static func usesSystemStyles(_ knobs: ThemeKnobs) -> Bool {
        knobs.fontFamily == "system" && knobs.fontMono == "system" && knobs.fontSize == 12
    }

    /// The text style `style` at the default; otherwise the body size plus `offset`.
    static func style(
        _ knobs: ThemeKnobs,
        _ style: Font.TextStyle,
        offset: Double,
        _ weight: Font.Weight? = nil,
        mono: Bool = false
    ) -> Font {
        if usesSystemStyles(knobs) {
            return Font.system(style, design: mono ? .monospaced : nil, weight: weight)
        }
        return sized(knobs, knobs.fontSize + offset, weight ?? .regular, mono: mono)
    }

    static func sized(_ knobs: ThemeKnobs, _ size: Double, _ weight: Font.Weight = .regular, mono: Bool = false) -> Font {
        switch mono ? knobs.fontMono : knobs.fontFamily {
        case "system": Font.system(size: size, weight: weight, design: mono ? .monospaced : .default)
        case "rounded": Font.system(size: size, weight: weight, design: .rounded)
        case "mono": Font.system(size: size, weight: weight, design: .monospaced)
        case let family: Font.custom(family, size: size).weight(weight)
        }
    }
}

/// The frame's and the tabs layout's type: the system text styles under the
/// Shipyard theme, sized from the theme's body size otherwise.
struct TypeScale: Equatable {
    /// The panel's heading, and a screen's title.
    let title: Font
    /// A larger heading, on the connect screen and the pickers.
    let display: Font
    /// Body text: a row's title, a screen's message.
    let body: Font
    let bodyEmphasis: Font
    let button: Font
    /// Numbers, authors, ages; banner text.
    let meta: Font
    /// A project's title.
    let section: Font
    /// A small header over a kind's rows.
    let eyebrow: Font
    /// The footer, and small print.
    let caption: Font
    let captionEmphasis: Font
    /// A count in a capsule.
    let badge: Font
    /// A command to copy, and a run's branch.
    let code: Font
    let branch: Font

    init(_ knobs: ThemeKnobs) {
        title = FontKit.style(knobs, .headline, offset: 1, .semibold)
        display = FontKit.style(knobs, .title3, offset: 3, .semibold)
        body = FontKit.style(knobs, .callout, offset: 0)
        bodyEmphasis = FontKit.style(knobs, .callout, offset: 0, .semibold)
        button = FontKit.style(knobs, .callout, offset: 0, .medium)
        meta = FontKit.style(knobs, .subheadline, offset: -1).monospacedDigit()
        section = FontKit.style(knobs, .subheadline, offset: -1, .semibold)
        eyebrow = FontKit.style(knobs, .caption, offset: -2, .semibold)
        caption = FontKit.style(knobs, .footnote, offset: -2).monospacedDigit()
        captionEmphasis = FontKit.style(knobs, .footnote, offset: -2, .medium)
        badge = FontKit.style(knobs, .caption, offset: -2, .bold).monospacedDigit()
        code = FontKit.style(knobs, .callout, offset: 0, .medium, mono: true)
        branch = FontKit.style(knobs, .footnote, offset: -2, .medium, mono: true)
    }
}

/// The list layout's type: smaller steps from the theme's body size, with
/// hierarchy by weight and by the text tiers.
struct ListType: Equatable {
    let body: Font
    let bodyEmphasis: Font
    let meta: Font
    let section: Font
    let eyebrow: Font
    let caption: Font
    let badge: Font
    let branch: Font

    init(_ knobs: ThemeKnobs) {
        let base = knobs.fontSize
        body = FontKit.sized(knobs, base)
        bodyEmphasis = FontKit.sized(knobs, base, .semibold)
        meta = FontKit.sized(knobs, base - 1.5).monospacedDigit()
        section = FontKit.sized(knobs, base - 0.5, .semibold)
        eyebrow = FontKit.sized(knobs, base - 2.5, .semibold)
        caption = FontKit.sized(knobs, base - 2).monospacedDigit()
        badge = FontKit.sized(knobs, base - 2, .medium).monospacedDigit()
        branch = FontKit.sized(knobs, base - 2, mono: true)
    }
}

private struct PanelScaleKey: EnvironmentKey {
    static let defaultValue = PanelScale.shipyard
}

extension EnvironmentValues {
    /// The sizes and type of the environment's theme. Setting the theme sets it.
    var panelScale: PanelScale {
        get { self[PanelScaleKey.self] }
        set { self[PanelScaleKey.self] = newValue }
    }
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

/// The SF Symbol for what a row shows: its kind and state, a ping's icon.
enum ItemSymbol {
    static func name(_ state: ItemState, kind: ItemKind) -> String {
        switch (kind, state) {
        case (.pullRequest, .merged): "arrow.triangle.merge"
        case (.issue, .closed): "checkmark.circle"
        case (.workflowRun, .running): "arrow.triangle.2.circlepath.circle.fill"
        case (.workflowRun, .failed): "xmark.circle.fill"
        case (.workflowRun, _): "checkmark.circle.fill"
        default: name(kind)
        }
    }

    static func name(_ kind: ItemKind) -> String {
        switch kind {
        case .pullRequest: "arrow.triangle.pull"
        case .issue: "smallcircle.filled.circle"
        case .workflowRun: "arrow.triangle.2.circlepath"
        case .ping: "bell.fill"
        case .note: "note.text"
        }
    }

    static func name(_ icon: PingIcon) -> String {
        switch icon {
        case .link: "link"
        case .app: "macwindow"
        case .terminal: "terminal"
        case .noAction: "bell.fill"
        }
    }
}
