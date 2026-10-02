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
/// measured and the height fixed from it, capped, and changed only when the
/// capped value really moves (`MeasuredHeight`), so a lazy stack's estimates
/// under each new viewport don't resize the panel forever.
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

/// A one-point line between the panel's parts.
struct Hairline: View {
    var body: some View {
        Rectangle().fill(Palette.separator).frame(height: 1)
    }
}

/// A count in a capsule that rolls to its new number: the accent colour
/// when it asks to be seen, muted when the rows it counts are in view.
///
/// Both colourings are drawn, one over the other, and muting fades between
/// them. Restyling the number instead would change the text itself, and
/// its numeric content transition would roll the digits on a colour change
/// alone; this way only a new count rolls them.
struct CountBadge: View {
    let count: Int
    var muted = false

    var body: some View {
        ZStack {
            number.foregroundStyle(.secondary).opacity(muted ? 1 : 0)
            number.foregroundStyle(Color.white).opacity(muted ? 0 : 1)
        }
        // Fixed, so a tab's label style changing around the badge doesn't
        // restyle the muted number either.
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
        .accessibilityLabel("\(count) need attention")
    }

    private var number: some View {
        Text(String(count))
            .font(TypeScale.badge)
            .contentTransition(.numericText(value: Double(count)))
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
/// pulsing; a ping's says what clicking it does.
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

/// A known agent's mark: its monogram in white on a circle of its hue,
/// shipyard's own drawing rather than the agent's logo. Decoration: the
/// sender's name beside it, or the card's words, say who sent the ping.
struct AgentMarkView: View {
    let agent: KnownAgent
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Palette.agent(agent.mark))
            .overlay {
                Text(agent.mark.monogram)
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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
            // Its words are in the row's hover card (`PanelText.rowCard`).
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

extension View {
    /// An item's row at `place`, in either layout: clicking opens it and
    /// marks it seen, ⌥-click (or the VoiceOver action) only marks it seen;
    /// its hover card holds what the row doesn't show (`PanelText.rowCard`); the attention
    /// dot and weight animate as it's seen; and it's `highlightable`. The
    /// layout still puts `.id(place)` on the lazy list's own child.
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

/// `itemRow(_:at:highlight:showsRepository:actions:)`.
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
            // A ping's ✕, over its age while the row is highlighted.
            .overlay(alignment: .trailing) {
                if row.item.ping != nil, highlight.isHighlighted(place) {
                    DismissButton { withAnimation(Motion.seen) { actions.dismiss(row) } }
                        .padding(.trailing, Grid.inset)
                }
            }
            // ⌥-click's equivalent for the keyboard and VoiceOver.
            .accessibilityAction(named: PanelText.markRowSeen) { actions.markSeen(row) }
            .hoverHelp(PanelText.rowCard(row, now: now), leadingInset: HoverHelp.rowInset)
            .animation(Motion.seen, value: row.needsAttention)
            .highlightable(place, $highlight)
    }

    /// ⌥ held: mark seen without opening; otherwise open (which marks seen).
    private func click() {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        withAnimation(Motion.seen) {
            if flags.contains(.option) { actions.markSeen(row) } else { actions.open(row) }
        }
    }
}

/// A ping row's ✕: removes the ping now. It sits over the row's age on
/// the row's own highlight, so its background is that highlight on the panel.
private struct DismissButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
        }
        .buttonStyle(IconButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Palette.panel)
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.hover))
        )
        .hoverHelp(PanelText.dismissPing)
        .accessibilityLabel(PanelText.dismissPing)
    }
}

/// A note about a project's list, in a row's place, such as the review
/// search's limit: information, not a failure. It wraps rather than
/// truncating, so it needs no hover help.
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

/// A repository of a project that couldn't be fetched, in a row's place.
/// Its message wraps, up to `maxLines`, rather than truncating, so it needs
/// no hover help; VoiceOver reads it whole.
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

/// A command to run in a terminal, in a box with a Copy button.
struct CommandBox: View {
    let command: String
    /// Whether it starts with a `$` prompt (a single-line shell command).
    var prompt = true
    var font = TypeScale.code
    @State private var copiedAt: Date?

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
            CopyButton(text: command, copiedAt: $copiedAt)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(minHeight: 30)
        .background(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).fill(Palette.fill))
        .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        .onChange(of: command) { copiedAt = nil }
    }
}

/// The copy icon beside text to copy (a `CommandBox`'s command, the
/// sign-in code): puts `text` on the clipboard and turns into a checkmark.
/// No hover help: the checkmark says it was copied. With a `title` it has a
/// short word beside the icon ("Copy"), which rolls to `copiedTitle`
/// ("Copied") with the counts' text transition. Ten seconds after the last
/// copy it turns back, with the same animations; another copy before then
/// starts the ten seconds again. `copiedAt` (when it was last copied; `nil`
/// shows the copy icon) is the caller's, so another way of copying the same
/// text can show it too, through `CopyButton.copied(_:)`, and new text can
/// reset it at once.
struct CopyButton: View {
    /// How long the checkmark stays after a copy.
    static let resetDelay: Duration = .seconds(10)

    /// Marks `copiedAt` as copied now, with the icon's animation.
    static func copied(_ copiedAt: Binding<Date?>) {
        withAnimation(.spring(duration: 0.3)) { copiedAt.wrappedValue = Date() }
    }

    let text: String
    /// VoiceOver's label before and after copying.
    var label = "Copy"
    var copiedLabel = "Copied"
    /// The word beside the icon before and after copying; none without it.
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
                    // Sized for the longer word, so the icon doesn't shift as it rolls.
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
        // Restarts with each copy and is cancelled when the button goes away.
        .task(id: copiedAt) {
            guard copiedAt != nil else { return }
            do { try await Task.sleep(for: Self.resetDelay) } catch { return }
            withAnimation(.spring(duration: 0.3)) { copiedAt = nil }
        }
    }
}

/// The general pasteboard, for text.
enum Clipboard {
    /// Puts exactly `text` on the clipboard, in place of what was there.
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
    /// An icon with a word beside it: as wide as both, rather than square.
    var labeled = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        IconButtonBody(configuration: configuration, labeled: labeled)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let labeled: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(hover && isEnabled ? .primary : .secondary)
            .opacity(isEnabled ? 1 : 0.4)
            .padding(.horizontal, labeled ? 6 : 0)
            .frame(width: labeled ? nil : 24, height: 22)
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
    /// 24 in a row of buttons; taller for a screen's stacked, full-width actions.
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
            .foregroundStyle(prominent ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .frame(height: height)
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

extension View {
    /// Draws `highlight` behind the rows in this view: one shape, at the
    /// highlighted row's bounds, gliding from row to row. It's one view
    /// moving rather than a shape matched between rows, so rows that a lazy
    /// stack creates and drops can't make it jump, and a row scrolled out of
    /// the stack takes the highlight with it. With tabs, `list` is the
    /// selected tab: only its rows are lit, not the outgoing tab's while
    /// the list slides, and the shape fades in on a new tab rather than
    /// gliding from the old one.
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

/// The rows' highlight shape, rounded and inset; a project header's is its whole band, square.
struct RowHighlightShape: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.hover)
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

/// A layout's Mark all seen (or Mark seen) for a project or a tab: a
/// checkmark and `title` as a text button. `action` brings its own animation.
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

/// Inline Markdown from `PanelText` (a command in backticks, a link) as
/// the panel draws it: `size` points, with each code span monospaced on a
/// faint chip. The chip is what makes it read as code: SF Mono's "g" and "h"
/// are drawn almost like SF Pro's, so a short command such as `gh` in the
/// monospaced font alone looks like the words around it.
enum CodeText {
    /// The chip behind a code span.
    static let chip = Color.primary.opacity(0.09)
    /// The chip's padding at each end: a thin space, so it doesn't hug the letters.
    static let padding = "\u{2009}"

    static func attributed(_ markdown: String, size: CGFloat, weight: Font.Weight = .regular) -> AttributedString {
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

extension Text {
    /// `CodeText.attributed(markdown, size:weight:)`: the font is in the
    /// runs, so a `.font(_:)` on the view doesn't change it.
    init(markdown: String, size: CGFloat, weight: Font.Weight = .regular) {
        self.init(CodeText.attributed(markdown, size: size, weight: weight))
    }
}
