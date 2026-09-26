import AppKit
import ShipyardCore
import SwiftUI

// The small pieces the frame and the layouts share, drawn from the tokens
// in `Design.swift`.

private struct PanelNowKey: EnvironmentKey {
    static var defaultValue: Date { .now }
}

extension EnvironmentValues {
    /// The time the panel draws ages against, ticking every 30 s.
    var panelNow: Date {
        get { self[PanelNowKey.self] }
        set { self[PanelNowKey.self] = newValue }
    }
}

/// A scroll view as tall as its content, up to `maxHeight`. The
/// `MenuBarExtra` window sizes the panel from a zero-height proposal, which a
/// plain scroll view (or `ViewThatFits`) takes as 0; so the content is
/// measured and the height fixed from it (#27).
struct MeasuredScrollView<Content: View>: View {
    var maxHeight: CGFloat = Grid.maxListHeight
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
        }
        .frame(height: min(height, maxHeight))
    }
}

/// A one-point line between the panel's parts.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: 1)
    }
}

/// A count in a capsule that rolls to its new number: the accent colour
/// when it asks to be seen, muted when the rows it counts are in view.
struct CountBadge: View {
    let count: Int
    var muted = false

    var body: some View {
        Text(String(count))
            .font(TypeScale.badge)
            .contentTransition(.numericText(value: Double(count)))
            .foregroundStyle(muted ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white))
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 15)
            .background(Capsule().fill(muted ? Color.primary.opacity(0.09) : Palette.accent))
            .animation(Motion.count, value: count)
            .accessibilityLabel("\(count) need attention")
    }
}

/// A note above the content: what's wrong or slowed down, tinted by how
/// much it matters, with an optional link-style action.
struct Banner: View {
    let symbol: String
    let text: String
    let tint: Color
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.78))
                    .lineSpacing(1)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.title, action: action.run)
                        .buttonStyle(TextButtonStyle(tint: tint))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).fill(tint.opacity(0.11)))
        .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
    }
}

// MARK: - A row's pieces

/// A row's state icon: its symbol in its state's colour, a running run
/// pulsing.
struct StateSymbol: View {
    let row: MenuRow

    var body: some View {
        Image(systemName: Palette.symbol(row.state, kind: row.kind))
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Palette.color(row.state, kind: row.kind))
            .symbolEffect(.pulse, options: .repeating, isActive: row.state == .running)
            .accessibilityLabel(PanelText.stateLabel(row))
    }
}

/// A pull request's check dot, cut out of what it sits on like a status
/// badge; nothing when there are no checks.
struct CheckDot: View {
    let checks: ChecksState?

    var body: some View {
        if let checks, let color = Palette.color(checks) {
            ZStack {
                Circle().fill(Palette.panel).frame(width: 8, height: 8)
                Circle().fill(color).frame(width: 5.5, height: 5.5)
            }
            .help(PanelText.checks(checks) ?? "")
            .accessibilityLabel(PanelText.checks(checks) ?? "")
        }
    }
}

/// The attention dot: shown while the row needs attention, shrinking away
/// once it's seen.
struct AttentionDot: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(Palette.accent)
            .frame(width: 6, height: 6)
            .opacity(isOn ? 1 : 0)
            .scaleEffect(isOn ? 1 : 0.2)
            .accessibilityHidden(!isOn)
            .accessibilityLabel(PanelText.needsAttention)
    }
}

/// A repository of a project that couldn't be fetched, in a row's place.
struct ErrorRow: View {
    let error: MenuErrorRow

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Palette.amber)
                .font(.system(size: 10.5))
                .frame(width: Grid.iconColumn)
            Text(error.message)
                .font(TypeScale.meta)
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(error.message)
            Spacer(minLength: 0)
        }
        .padding(.leading, Grid.gutter + Grid.dotColumn - 6)
        .padding(.trailing, Grid.gutter)
        .frame(height: Grid.rowHeight)
    }
}

/// A command to run in a terminal, in a box with a Copy button.
struct CommandBox: View {
    let command: String
    /// Whether it starts with a `$` prompt (a single-line shell command).
    var prompt = true
    var font = TypeScale.code
    @State private var copied = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if prompt {
                Text("$").font(font).foregroundStyle(.tertiary)
            }
            Text(command)
                .font(font)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                withAnimation(.spring(duration: 0.3)) { copied = true }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(IconButtonStyle())
            .help(copied ? "Copied" : "Copy")
            .accessibilityLabel(copied ? "Copied" : "Copy")
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).fill(Palette.fill))
        .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        .onChange(of: command) { copied = false }
    }
}

/// A card: a softly filled, bordered box (the skill install card).
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Grid.radius + 1, style: .continuous).fill(Palette.fill))
            .overlay(RoundedRectangle(cornerRadius: Grid.radius + 1, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

// MARK: - Buttons

/// A borderless icon button with hover and pressed states.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        IconButtonBody(configuration: configuration)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hover && isEnabled ? .primary : .secondary)
            .opacity(isEnabled ? 1 : 0.4)
            .frame(width: 24, height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Palette.pressed : hover && isEnabled ? Palette.hover : .clear)
            )
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .animation(Motion.hover, value: hover)
    }
}

/// A rounded button: prominent (the accent, for the screen's main action)
/// or quiet.
struct PillButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        PillButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(Color.primary.opacity(0.07)))
                    .brightness(configuration.isPressed ? -0.08 : hover && isEnabled ? 0.04 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.primary.opacity(prominent ? 0 : 0.08), lineWidth: 0.5)
            )
            .shadow(color: prominent ? Palette.accent.opacity(0.3) : .clear, radius: 2, y: 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

/// A row: darker while pressed. Its hover highlight isn't drawn here but
/// once per layout, behind the rows (`rowHighlight(_:)`), so it can glide.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    // Over the hover highlight, the two add up to `Palette.pressed`.
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.hover)
                        .padding(.horizontal, Grid.inset)
                }
            }
    }
}

// MARK: - The row highlight

/// Each row's bounds, by its place, for the one highlight shape.
private struct RowBoundsKey: PreferenceKey {
    static let defaultValue: [MenuRowPlace: Anchor<CGRect>] = [:]

    static func reduce(value: inout [MenuRowPlace: Anchor<CGRect>], nextValue: () -> [MenuRowPlace: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// A row at `place`: reports its bounds to the layout's highlight and
    /// feeds the pointer's enter and exit to `highlight` (#44).
    func highlightable(_ place: MenuRowPlace, _ highlight: Binding<RowHighlight>) -> some View {
        anchorPreference(key: RowBoundsKey.self, value: .bounds) { [place: $0] }
            .onHover { inside in
                if inside {
                    highlight.wrappedValue.pointerEntered(place)
                } else {
                    highlight.wrappedValue.pointerExited(place)
                }
            }
    }

    /// Draws `highlight` behind the rows in this view: one shape, at the
    /// highlighted row's bounds, gliding from row to row. It's one view
    /// moving rather than a shape matched between rows, so rows that a lazy
    /// stack creates and drops can't make it jump, and a row scrolled out of
    /// the stack takes the highlight with it.
    func rowHighlight(_ highlight: RowHighlight) -> some View {
        backgroundPreferenceValue(RowBoundsKey.self) { bounds in
            GeometryReader { proxy in
                if let place = highlight.place, let anchor = bounds[place] {
                    let rect = proxy[anchor]
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.hover)
                        .frame(width: max(rect.width - 2 * Grid.inset, 0), height: rect.height)
                        .offset(x: rect.minX + Grid.inset, y: rect.minY)
                        .transition(.opacity)
                }
            }
            .animation(Motion.highlight, value: highlight.place)
        }
    }
}

/// A plain button that dims and shrinks a hair while pressed (a tab).
struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

/// A small text button ("Mark all seen", "Quit"): quiet until hovered,
/// then tinted.
struct TextButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    var font: Font = TypeScale.captionEmphasis

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        TextButtonBody(configuration: configuration, tint: tint, font: font)
    }
}

private struct TextButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let font: Font
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(hover && isEnabled ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(
                RoundedRectangle(cornerRadius: Grid.smallRadius, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.18 : hover && isEnabled ? 0.1 : 0))
            )
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .animation(Motion.hover, value: hover)
    }
}
