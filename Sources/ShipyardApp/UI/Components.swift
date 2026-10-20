import AppKit
import ShipyardConfig
import ShipyardCore
import SwiftUI

private struct PanelNowKey: EnvironmentKey {
    static var defaultValue: Date { .now }
}

extension EnvironmentValues {
    var panelNow: Date {
        get { self[PanelNowKey.self] }
        set { self[PanelNowKey.self] = newValue }
    }
}

struct MeasuredScrollView<Content: View>: View {
    var maxHeight: CGFloat = Grid.maxListHeight
    @ViewBuilder var content: Content
    @State private var height: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                    if let next = MeasuredHeight.next(current: height, measured: measured, maxHeight: maxHeight) {
                        height = next
                    }
                }
        }
        .frame(height: height)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle().fill(ThemeColor.separator).frame(height: 1)
    }
}

struct CountBadge: View {
    let count: Int
    var muted = false

    var body: some View {
        ZStack {
            number.foregroundStyle(.secondary).opacity(muted ? 1 : 0)
            number.foregroundStyle(Color.white).opacity(muted ? 0 : 1)
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 5)
        .frame(minWidth: 17, minHeight: 15)
        .background {
            ZStack {
                Capsule().fill(Color.primary.opacity(0.09)).opacity(muted ? 1 : 0)
                Capsule().fill(Palette.accent).opacity(muted ? 0 : 1)
            }
        }
        .animation(Motion.tint, value: muted)
        .animation(Motion.count, value: count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PanelText.attentionCount(count))
    }

    private var number: some View {
        Text(String(count))
            .font(TypeScale.badge)
            .contentTransition(.numericText(value: Double(count)))
    }
}

struct BannerDismissButton: View {
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .semibold))
        }
        .buttonStyle(IconButtonStyle(compact: true))
        .hoverHelp(PanelText.dismissBanner)
        .accessibilityLabel(PanelText.dismissBanner)
        .padding(.vertical, -2)
        .padding(.trailing, -4)
    }
}

struct Banner: View {
    let symbol: String
    let text: String
    let tint: ThemeColor
    var action: (title: String, run: () -> Void)?
    var trailing = false
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: trailing ? .center : .top, spacing: 8) {
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(ThemeColor.textPrimary.opacity(0.78))
                    .lineSpacing(1)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let action, !trailing {
                    button(action)
                }
            }
            Spacer(minLength: 0)
            if let action, trailing {
                button(action)
                    .fixedSize()
                    .layoutPriority(1)
            }
            if let dismiss {
                BannerDismissButton(dismiss: dismiss)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).fill(tint.opacity(0.11)))
        .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
    }

    private func button(_ action: (title: String, run: () -> Void)) -> some View {
        Button(action.title, action: action.run)
            .buttonStyle(TextButtonStyle(tint: tint))
    }
}

struct StateSymbol: View {
    let row: MenuRow

    var body: some View {
        Image(systemName: row.pingIcon.map { Palette.symbol($0) } ?? Palette.symbol(row.state, kind: row.kind))
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Palette.color(row.state, kind: row.kind))
            .symbolEffect(.pulse, options: .repeating, isActive: row.state == .running)
            .accessibilityLabel(PanelText.stateLabel(row))
    }
}

struct AgentMarkView: View {
    let agent: KnownAgent
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let image = AgentLogoImage.image(for: agent, dark: colorScheme == .dark) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(.primary)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct CheckDot: View {
    let checks: ChecksState?

    var body: some View {
        if let checks, let color = Palette.color(checks) {
            ZStack {
                Circle().fill(Palette.panel).frame(width: 8, height: 8)
                Circle().fill(color).frame(width: 5.5, height: 5.5)
            }
            .accessibilityLabel(PanelText.checks(checks) ?? "")
        }
    }
}

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

extension View {
    func itemRow(
        _ row: MenuRow,
        at place: MenuRowPlace,
        highlight: Binding<RowHighlight>,
        showsRepository: Bool,
        actions: LayoutActions
    ) -> some View {
        modifier(ItemRow(row: row, place: place, highlight: highlight, showsRepository: showsRepository, actions: actions))
    }
}

private struct ItemRow: ViewModifier {
    let row: MenuRow
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let showsRepository: Bool
    let actions: LayoutActions
    @Environment(\.panelNow) private var now

    func body(content: Content) -> some View {
        Button(action: click) { content }
            .buttonStyle(RowButtonStyle())
            .overlay(alignment: .trailing) {
                if row.item.ping != nil, highlight.isHighlighted(place) {
                    DismissButton { withAnimation(Motion.seen) { actions.dismiss(row) } }
                        .padding(.trailing, Grid.inset)
                }
            }
            .accessibilityAction(named: PanelText.markRowSeen) { actions.markSeen(row) }
            .hoverHelp(PanelText.rowCard(row, now: now), leadingInset: HoverHelp.rowInset)
            .animation(Motion.seen, value: row.needsAttention)
            .highlightable(place, $highlight)
    }

    private func click() {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        withAnimation(Motion.seen) {
            if flags.contains(.option) { actions.markSeen(row) } else { actions.open(row) }
        }
    }
}

private struct DismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
        }
        .buttonStyle(IconButtonStyle(compact: true))
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.hover))
        )
        .hoverHelp(PanelText.dismissPing)
        .accessibilityLabel(PanelText.dismissPing)
    }
}

struct NoteRow: View {
    let note: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.system(size: 10.5))
                .frame(width: Grid.iconColumn)
            Text(note)
                .font(TypeScale.meta)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.leading, Grid.gutter + Grid.dotColumn - 6)
        .padding(.trailing, Grid.gutter)
        .padding(.vertical, 5)
        .frame(minHeight: Grid.rowHeight)
    }
}

struct ErrorRow: View {
    let error: MenuErrorRow
    private static let maxLines = 3

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Palette.amber)
                .font(.system(size: 10.5))
                .frame(width: Grid.iconColumn)
            Text(error.message)
                .font(TypeScale.meta)
                .foregroundStyle(.primary.opacity(0.75))
                .lineLimit(Self.maxLines)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.leading, Grid.gutter + Grid.dotColumn - 6)
        .padding(.trailing, Grid.gutter)
        .padding(.vertical, 5)
        .frame(minHeight: Grid.rowHeight)
    }
}

struct CommandBox: View {
    let command: String
    var prompt = true
    var font = TypeScale.code
    @State private var copiedAt: Date?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if prompt {
                Text("$").font(font).foregroundStyle(ThemeColor.textTertiary)
            }
            Text(command)
                .font(font)
                .foregroundStyle(ThemeColor.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            CopyButton(text: command, copiedAt: $copiedAt)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).fill(ThemeColor.field))
        .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(ThemeColor.border, lineWidth: 0.5))
        .onChange(of: command) { copiedAt = nil }
    }
}

struct CopyButton: View {
    static let resetDelay: Duration = .seconds(10)

    static func copied(_ copiedAt: Binding<Date?>) {
        withAnimation(.spring(duration: 0.3)) { copiedAt.wrappedValue = Date() }
    }

    let text: String
    var label = PanelText.copy
    var copiedLabel = PanelText.copied
    var title: String? = nil
    var copiedTitle: String? = nil
    @Binding var copiedAt: Date?

    private var copied: Bool { copiedAt != nil }

    var body: some View {
        Button {
            Clipboard.copy(text)
            Self.copied($copiedAt)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
                if let title {
                    let after = copiedTitle ?? title
                    ZStack(alignment: .leading) {
                        Text(title.count > after.count ? title : after).hidden()
                        Text(copied ? after : title)
                            .contentTransition(.numericText())
                            .animation(Motion.count, value: copied)
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .buttonStyle(IconButtonStyle(labeled: title != nil))
        .accessibilityLabel(copied ? copiedLabel : label)
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            do { try await Task.sleep(for: Self.resetDelay) } catch { return }
            withAnimation(.spring(duration: 0.3)) { copiedAt = nil }
        }
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: Grid.radius + 1, style: .continuous).fill(ThemeColor.field))
            .overlay(RoundedRectangle(cornerRadius: Grid.radius + 1, style: .continuous).strokeBorder(ThemeColor.border, lineWidth: 0.5))
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}

/// What a command printed, in a filled box: a setup card's and a setup view's output.
struct OutputBox: View {
    let output: String

    var body: some View {
        Text(output)
            .font(TypeScale.branch)
            .foregroundStyle(ThemeColor.textPrimary)
            .textSelection(.enabled)
            .lineLimit(8)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).fill(ThemeColor.field))
    }
}

struct IconButtonStyle: ButtonStyle {
    var labeled = false
    var compact = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        IconButtonBody(configuration: configuration, labeled: labeled, compact: compact)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let labeled: Bool
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hover && isEnabled ? ThemeColor.textPrimary : ThemeColor.textSecondary)
            .opacity(isEnabled ? 1 : 0.4)
            .padding(.horizontal, labeled ? 6 : 0)
            .frame(width: labeled ? nil : compact ? 16 : 24, height: compact ? 16 : 22)
            .background(
                RoundedRectangle(cornerRadius: compact ? 4 : 6, style: .continuous)
                    .fill(configuration.isPressed ? ThemeColor.rowPressed : ThemeColor.rowHover.opacity(hover && isEnabled ? 1 : 0))
            )
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .animation(Motion.hover, value: hover)
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var height: CGFloat = 24

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        PillButtonBody(configuration: configuration, prominent: prominent, height: height)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    let height: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(TypeScale.button)
            .foregroundStyle(prominent ? ThemeColor.textOnAccent : ThemeColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(prominent ? ThemeColor.accent : ThemeColor.textPrimary.opacity(0.07))
                    .brightness(configuration.isPressed ? -0.08 : hover && isEnabled ? 0.04 : 0)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(ThemeColor.textPrimary.opacity(prominent ? 0 : 0.08), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.5)
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}

struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .background {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.hover)
                        .padding(.horizontal, Grid.inset)
                }
            }
    }
}

extension View {
    func rowHighlight(_ highlight: RowHighlight, in list: AnyHashable? = nil) -> some View {
        backgroundPreferenceValue(RowBoundsKey.self) { bounds in
            GeometryReader { proxy in
                if let place = highlight.place, let anchor = bounds[RowSlot(list: list, place: place)] {
                    let rect = proxy[anchor]
                    RowHighlightShape()
                        .frame(width: max(rect.width - 2 * Grid.inset, 0), height: rect.height)
                        .offset(x: rect.minX + Grid.inset, y: rect.minY)
                        .transition(.opacity)
                        .id(list)
                }
            }
            .animation(Motion.highlight, value: highlight.place)
        }
    }
}

struct HighlightLayer<Content: View>: View {
    @Binding var highlight: RowHighlight
    var list: AnyHashable? = nil
    @ViewBuilder let content: Content

    var body: some View {
        content.rowHighlight(highlight, in: list)
    }
}

struct RowHighlightShape: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.hover)
    }
}

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

struct NewNoteIcon: View {
    let project: String
    let state: NewNoteButton
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 9, weight: .semibold))
                .offset(x: -0.5, y: -0.5)
                .opacity(state == .starting ? 0 : 1)
                .overlay {
                    if state == .starting { ProgressView().controlSize(.mini).scaleEffect(0.8) }
                }
        }
        .buttonStyle(IconButtonStyle(compact: true))
        .disabled(state == .starting)
        .hoverHelp(PanelText.newNoteHelp(project))
        .accessibilityLabel(PanelText.newNoteHelp(project))
    }
}

struct MarkSeenButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle")
                Text(title)
            }
        }
        .buttonStyle(TextButtonStyle())
    }
}

struct TextButtonStyle<Tint: ShapeStyle>: ButtonStyle {
    var tint: Tint
    var font: Font = TypeScale.captionEmphasis

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        TextButtonBody(configuration: configuration, tint: tint, font: font)
    }
}

extension TextButtonStyle where Tint == ThemeColor {
    /// A text button in the accent.
    init(font: Font = TypeScale.captionEmphasis) {
        self.init(tint: ThemeColor.accent, font: font)
    }
}

private struct TextButtonBody<Tint: ShapeStyle>: View {
    let configuration: ButtonStyleConfiguration
    let tint: Tint
    let font: Font
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(font)
            .foregroundStyle(hover && isEnabled ? AnyShapeStyle(tint) : AnyShapeStyle(ThemeColor.textSecondary))
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

enum CodeText {
    /// The chip behind a code span.
    static let chip = ThemeColor.textPrimary.opacity(0.09)
    static let padding = "\u{2009}"

    /// `markdown` at `size`, each code span monospaced on `chip`: an
    /// attributed string takes a `Color`, so the caller resolves `CodeText.chip`.
    static func attributed(_ markdown: String, size: CGFloat, weight: Font.Weight = .regular, chip: Color) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        let parsed = (try? AttributedString(markdown: markdown, options: options)) ?? AttributedString(markdown)
        let code = Font.system(size: size, weight: weight, design: .monospaced)
        var text = AttributedString()
        for run in parsed.runs {
            var piece = AttributedString(parsed[run.range])
            piece.font = .system(size: size, weight: weight)
            if run.inlinePresentationIntent?.contains(.code) == true {
                piece.font = code
                piece.backgroundColor = chip
                var pad = AttributedString(padding)
                pad.font = .system(size: size, weight: weight)
                pad.backgroundColor = chip
                piece = pad + piece + pad
            }
            text += piece
        }
        return text
    }
}

/// Inline Markdown from `PanelText` as the panel draws it (`CodeText`), its
/// code chips in the environment's theme and appearance. The font is in the
/// runs, so a `.font(_:)` on the view doesn't change it.
struct MarkdownText: View {
    let markdown: String
    let size: CGFloat
    var weight: Font.Weight = .regular
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    init(_ markdown: String, size: CGFloat, weight: Font.Weight = .regular) {
        self.markdown = markdown
        self.size = size
        self.weight = weight
    }

    var body: some View {
        let chip = CodeText.chip.color(in: theme, ThemeAppearance(scheme))
        Text(CodeText.attributed(markdown, size: size, weight: weight, chip: chip))
    }
}

struct ToneIcon: View {
    let tone: PanelText.SkillInstall.Tone
    let neutral: String
    let neutralTint: ThemeColor

    var body: some View {
        Group {
            switch tone {
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(ThemeColor.success)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ThemeColor.pending)
            case .neutral:
                Image(systemName: neutral).foregroundStyle(neutralTint)
            }
        }
        .symbolRenderingMode(.hierarchical)
        .font(.system(size: 12, weight: .semibold))
    }
}
