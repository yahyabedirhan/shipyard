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

extension View {
    /// An item's row at `place`, in either layout: clicking opens it and
    /// marks it seen, ⌥-click (or the VoiceOver action) only marks it seen;
    /// the tooltip holds its state and full second line; the attention
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
            // ⌥-click's equivalent for the keyboard and VoiceOver.
            .accessibilityAction(named: PanelText.markRowSeen) { actions.markSeen(row) }
            .help(PanelText.rowHelp(row, showingRepository: showsRepository, now: now))
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

/// Where the laid-out rows sit in a layout's scrolling list, in its
/// visible area, and how tall that area is: what `RowScroll` needs to
/// keep the keys' highlight in view (#45). A reference kept out of view
/// state: it changes on every scroll and draws nothing.
@MainActor
final class RowFrames {
    /// The coordinate space of the list's visible area.
    nonisolated static let space = "row-frames"
    var spans: [MenuRowPlace: RowSpan] = [:]
    var visibleHeight: Double = 0
}

private struct RowFramesKey: EnvironmentKey {
    static var defaultValue: RowFrames? { nil }
}

extension EnvironmentValues {
    /// The list's `RowFrames`, set by `rowKeys(…)` for the rows inside it.
    fileprivate var rowFrames: RowFrames? {
        get { self[RowFramesKey.self] }
        set { self[RowFramesKey.self] = newValue }
    }
}

extension View {
    /// A row at `place`: reports its bounds to the layout's highlight
    /// (unless it draws its own, like a pinned project header), reports
    /// where it sits in the list for scrolling it into view, and feeds the
    /// pointer's enter and exit to `highlight` (#44, #45). The layout puts
    /// `.id(place)` on the list's own child for the row, so the keys can
    /// scroll to a row the lazy list hasn't laid out.
    func highlightable(_ place: MenuRowPlace, _ highlight: Binding<RowHighlight>, drawsOwnHighlight: Bool = false) -> some View {
        modifier(Highlightable(place: place, highlight: highlight, drawsOwnHighlight: drawsOwnHighlight))
    }

    /// Something among the rows that isn't one (an error row, a
    /// placeholder, a tab's kind header): the pointer on it highlights
    /// nothing, even if the row it came from never reported its exit.
    func clearsRowHighlight(_ highlight: Binding<RowHighlight>) -> some View {
        onHover { inside in
            if inside { highlight.wrappedValue.pointerLeftRows() }
        }
    }

    /// The keys for a layout's rows (#45), on its scrolling list. ↑ and ↓
    /// move `highlight` through `places`, wrapping at the ends; `left` and
    /// `right` are the layout's ← and →. The highlighted row is kept in
    /// view, clear of a `pinnedHeader` that tall, without animating the
    /// scroll. Return calls `activate(place, false)` and ⌥Return
    /// `activate(place, true)`; `activate` says whether it acted. The list
    /// takes the keyboard focus each time its window becomes key (each
    /// time the menu opens), and moving the pointer hands the highlight
    /// back to it.
    func rowKeys(
        _ highlight: Binding<RowHighlight>,
        places: [MenuRowPlace],
        pinnedHeader: CGFloat = 0,
        scroll: ScrollViewProxy,
        left: @escaping () -> RowKeyMove,
        right: @escaping () -> RowKeyMove,
        activate: @escaping (MenuRowPlace, _ markSeenOnly: Bool) -> Bool
    ) -> some View {
        modifier(RowKeys(
            highlight: highlight,
            places: places,
            pinnedHeader: pinnedHeader,
            scroll: scroll,
            left: left,
            right: right,
            activate: activate
        ))
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
                    RowHighlightShape()
                        .frame(width: max(rect.width - 2 * Grid.inset, 0), height: rect.height)
                        .offset(x: rect.minX + Grid.inset, y: rect.minY)
                        .transition(.opacity)
                }
            }
            .animation(Motion.highlight, value: highlight.place)
        }
    }
}

/// The highlight's shape: the rows' one, and a project header's own.
struct RowHighlightShape: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.hover)
    }
}

/// What ← or → did in a layout, for `rowKeys(…)`: nothing, moved the
/// highlight within the list (which then scrolls it into view as ↑ and ↓
/// do), or moved it to a new list (another tab), which scrolls to its top.
enum RowKeyMove {
    case ignored
    case moved
    case newList
}

/// `highlightable(_:_:drawsOwnHighlight:)`.
private struct Highlightable: ViewModifier {
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let drawsOwnHighlight: Bool
    @Environment(\.rowFrames) private var frames

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: RowBoundsKey.self, value: .bounds) { drawsOwnHighlight ? [:] : [place: $0] }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(RowFrames.space)) } action: { frame in
                frames?.spans[place] = RowSpan(top: frame.minY, bottom: frame.maxY)
            }
            // A row the lazy list dropped isn't where it last was.
            .onDisappear { frames?.spans[place] = nil }
            .onHover { inside in
                if inside {
                    highlight.pointerEntered(place)
                } else {
                    highlight.pointerExited(place)
                }
            }
    }
}

/// `rowKeys(_:places:pinnedHeader:scroll:left:right:activate:)`.
private struct RowKeys: ViewModifier {
    @Binding var highlight: RowHighlight
    let places: [MenuRowPlace]
    let pinnedHeader: CGFloat
    let scroll: ScrollViewProxy
    let left: () -> RowKeyMove
    let right: () -> RowKeyMove
    let activate: (MenuRowPlace, Bool) -> Bool
    @FocusState private var focused: Bool
    @State private var frames = RowFrames()
    /// Where the pointer last was, in the window. Kept out of the view's
    /// state: it changes on every move and draws nothing.
    @State private var pointer = PointerLocation()

    func body(content: Content) -> some View {
        content
            .coordinateSpace(.named(RowFrames.space))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frames.visibleHeight = $0 }
            .environment(\.rowFrames, frames)
            // The panel's window is key while the menu is open, so the
            // focused list gets the keys; closed, the panel isn't on
            // screen and takes none. `.onAppear` alone isn't enough: the
            // view outlives a closed menu, and focus set before its window
            // is key is lost, so it's set again each time it becomes key.
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .background(WindowBecameKey { focused = true })
            // Held down, a key repeats at the system's rate (`onKeyPress`
            // gets the repeats), and each step scrolls without animating.
            .onKeyPress(.downArrow) { step { $0.moveDown(in: places) } }
            .onKeyPress(.upArrow) { step { $0.moveUp(in: places) } }
            .onKeyPress(.leftArrow) { side(left) }
            .onKeyPress(.rightArrow) { side(right) }
            .onKeyPress(keys: [.return]) { press in
                guard let place = highlight.place,
                      activate(place, press.modifiers.contains(.option)) else { return .ignored }
                return .handled
            }
            .onContinuousHover(coordinateSpace: .global) { phase in
                // Scrolling moves the rows under a resting pointer, not the
                // pointer: only a new location hands the highlight back.
                guard case .active(let location) = phase, location != pointer.location else { return }
                pointer.location = location
                if !highlight.followsPointer { highlight.pointerMoved() }
            }
    }

    private func step(_ move: (inout RowHighlight) -> Void) -> KeyPress.Result {
        let previous = highlight.place
        move(&highlight)
        guard let place = highlight.place else { return .ignored }
        reveal(place, from: previous)
        return .handled
    }

    private func side(_ move: () -> RowKeyMove) -> KeyPress.Result {
        let previous = highlight.place
        switch move() {
        case .ignored:
            return .ignored
        case .moved:
            if let place = highlight.place { reveal(place, from: previous) }
        case .newList:
            if let place = highlight.place { scroll.scrollTo(place, anchor: .top) }
        }
        return .handled
    }

    /// Scrolls `place` into view, as far as it takes and no further.
    private func reveal(_ place: MenuRowPlace, from previous: MenuRowPlace?) {
        let move = RowScroll.reveal(
            place,
            from: previous,
            in: places,
            frame: frames.spans[place],
            visibleHeight: frames.visibleHeight,
            pinnedHeader: pinnedHeader
        )
        switch move {
        case .stay: break
        case .alignTop(let anchor): scroll.scrollTo(place, anchor: UnitPoint(x: 0.5, y: anchor))
        case .alignBottom: scroll.scrollTo(place, anchor: .bottom)
        }
    }
}

private final class PointerLocation {
    var location: CGPoint?
}

/// Calls `action` each time the window this view is in becomes key, and
/// once when it's placed in a window that already is: the moment the menu
/// opens. It changes nothing about when the window becomes key.
private struct WindowBecameKey: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Observer {
        Observer()
    }

    func updateNSView(_ view: Observer, context: Context) {
        view.action = action
    }

    final class Observer: NSView {
        var action: (() -> Void)?
        private var observation: NSObjectProtocol?

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if let observation { NotificationCenter.default.removeObserver(observation) }
            observation = nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            observation = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                // After SwiftUI has made the window's content key-ready.
                DispatchQueue.main.async { self?.action?() }
            }
            if window.isKeyWindow {
                DispatchQueue.main.async { [weak self] in self?.action?() }
            }
        }

        // Not in the way of the pointer.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
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
