import AppKit
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
    func makeBody(configuration: Configuration) -> some View {
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

    func makeBody(configuration: Configuration) -> some View {
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

/// A small text button ("Mark all seen", "Quit"): quiet until hovered,
/// then tinted.
struct TextButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    var font: Font = TypeScale.captionEmphasis

    func makeBody(configuration: Configuration) -> some View {
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
