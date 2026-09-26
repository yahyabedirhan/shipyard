import AppKit
import ShipyardCore
import SwiftUI

// The row highlight's and the keys' plumbing, which the layouts share:
// where each row is (for the highlight shape and for scrolling), the
// pointer's enter and exit, the keys, and the focus on each open. What the highlight looks like is in `Components.swift`.

/// A row's place in the list it's in: a tab (`list`), or the list
/// layout's one list (`nil`). Tabs list a row at the same place, and while
/// the list slides from one tab to the next both are on screen, so what
/// their rows report is kept apart by tab.
struct RowSlot: Hashable {
    var list: AnyHashable?
    var place: MenuRowPlace
}

/// Each row's bounds, by its slot, for the one highlight shape.
struct RowBoundsKey: PreferenceKey {
    static var defaultValue: [RowSlot: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [RowSlot: Anchor<CGRect>], nextValue: () -> [RowSlot: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Where the laid-out rows sit in a layout's scrolling list, in its
/// visible area, and how tall that area is: what `RowScroll` needs to
/// keep the keys' highlight in view. A reference kept out of view
/// state: it changes on every scroll and draws nothing.
@MainActor
final class RowFrames {
    /// The coordinate space of the list's visible area.
    nonisolated static let space = "row-frames"
    var visibleHeight: Double = 0
    /// Each laid-out row's span, and which row view reported it.
    private var spans: [RowSlot: (span: RowSpan, owner: UUID)] = [:]

    /// Where the row at `slot` sits, if it's laid out.
    func span(at slot: RowSlot) -> RowSpan? {
        spans[slot]?.span
    }

    /// The row view `owner` at `slot` is at `span`.
    func report(_ span: RowSpan, at slot: RowSlot, by owner: UUID) {
        spans[slot] = (span, owner)
    }

    /// The row view `owner` at `slot` is gone. A span another view has
    /// reported since (the same row in a new tab, or recreated by the lazy
    /// list) is kept.
    func forget(_ slot: RowSlot, by owner: UUID) {
        if spans[slot]?.owner == owner { spans[slot] = nil }
    }
}

private struct RowFramesKey: EnvironmentKey {
    static var defaultValue: RowFrames? { nil }
}

private struct RowListKey: EnvironmentKey {
    static var defaultValue: AnyHashable? { nil }
}

extension EnvironmentValues {
    /// The list's `RowFrames`, set by `rowKeys(…)` for the rows inside it.
    fileprivate var rowFrames: RowFrames? {
        get { self[RowFramesKey.self] }
        set { self[RowFramesKey.self] = newValue }
    }

    /// The list the rows are in (a tab), set by `rowList(_:)`.
    fileprivate var rowList: AnyHashable? {
        get { self[RowListKey.self] }
        set { self[RowListKey.self] = newValue }
    }
}

/// The top of a layout's scrolling list, above anything that transitions:
/// where `rowKeys(…)` scrolls when ← or → moves the highlight to a new
/// list (another tab). It's there before the new tab is laid out, and
/// unlike a row it can't be the outgoing tab's.
struct RowListTop: View {
    static let id = "row-list-top"

    var body: some View {
        Color.clear.frame(height: 0).id(Self.id)
    }
}

extension View {
    /// A row at `place`: reports its bounds to the layout's highlight
    /// (unless it draws its own, like a pinned project header), reports
    /// where it sits in the list for scrolling it into view, and feeds the
    /// pointer's enter and exit to `highlight`. The layout puts
    /// `.id(place)` on the list's own child for the row, so the keys can
    /// scroll to a row the lazy list hasn't laid out.
    func highlightable(_ place: MenuRowPlace, _ highlight: Binding<RowHighlight>, drawsOwnHighlight: Bool = false) -> some View {
        modifier(Highlightable(place: place, highlight: highlight, drawsOwnHighlight: drawsOwnHighlight))
    }

    /// The rows in this view are in list `list` (a tab): what they report
    /// is kept apart from another tab's rows at the same places, which
    /// share the screen while the list slides between tabs.
    func rowList(_ list: some Hashable) -> some View {
        environment(\.rowList, AnyHashable(list))
    }

    /// Something among the rows that isn't one (an error row, a
    /// placeholder, a tab's kind header): the pointer on it highlights
    /// nothing, even if the row it came from never reported its exit.
    func clearsRowHighlight(_ highlight: Binding<RowHighlight>) -> some View {
        onHover { inside in
            if inside { highlight.wrappedValue.pointerLeftRows() }
        }
    }

    /// The keys for a layout's rows, on its scrolling list. ↑ and ↓
    /// move `highlight` through `places`, wrapping at the ends; `left` and
    /// `right` are the layout's ← and →. The highlighted row is kept in
    /// view, clear of a `pinnedHeader` that tall, without animating the
    /// scroll. Return calls `activate(place, false)` and ⌥Return
    /// `activate(place, true)`; `activate` says whether it acted. `list`
    /// is the list the highlight is in (the selected tab, as its rows'
    /// `rowList(_:)`; `nil` in the list layout). The list
    /// takes the keyboard focus each time its window becomes key (each
    /// time the menu opens), and moving the pointer hands the highlight
    /// back to it.
    func rowKeys(
        _ highlight: Binding<RowHighlight>,
        places: [MenuRowPlace],
        in list: AnyHashable? = nil,
        pinnedHeader: CGFloat = 0,
        scroll: ScrollViewProxy,
        left: @escaping () -> RowKeyMove,
        right: @escaping () -> RowKeyMove,
        activate: @escaping (MenuRowPlace, _ markSeenOnly: Bool) -> Bool
    ) -> some View {
        modifier(RowKeys(
            highlight: highlight,
            places: places,
            list: list,
            pinnedHeader: pinnedHeader,
            scroll: scroll,
            left: left,
            right: right,
            activate: activate
        ))
    }
}

/// What ← or → did in a layout, for `rowKeys(…)`: nothing, moved the
/// highlight within the list (which then scrolls it into view as ↑ and ↓
/// do), or moved it to a new list (another tab), which scrolls to its top
/// (`RowListTop`).
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
    @Environment(\.rowList) private var list
    /// This row view, among others at the same slot: the outgoing tab's
    /// row, or one the lazy list dropped and made again.
    @State private var owner = UUID()

    private var slot: RowSlot { RowSlot(list: list, place: place) }

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: RowBoundsKey.self, value: .bounds) { drawsOwnHighlight ? [:] : [slot: $0] }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(RowFrames.space)) } action: { frame in
                frames?.report(RowSpan(top: frame.minY, bottom: frame.maxY), at: slot, by: owner)
            }
            // A row the lazy list dropped isn't where it last was.
            .onDisappear { frames?.forget(slot, by: owner) }
            .onHover { inside in
                if inside {
                    highlight.pointerEntered(place)
                } else {
                    highlight.pointerExited(place)
                }
            }
    }
}

/// `rowKeys(_:places:in:pinnedHeader:scroll:left:right:activate:)`.
private struct RowKeys: ViewModifier {
    @Binding var highlight: RowHighlight
    let places: [MenuRowPlace]
    let list: AnyHashable?
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
            // Not to the highlighted row: the new tab isn't laid out yet,
            // and the outgoing one has a row with the same id.
            scroll.scrollTo(RowListTop.id, anchor: .top)
        }
        return .handled
    }

    /// Scrolls `place` into view, as far as it takes and no further.
    private func reveal(_ place: MenuRowPlace, from previous: MenuRowPlace?) {
        let move = RowScroll.reveal(
            place,
            from: previous,
            in: places,
            frame: frames.span(at: RowSlot(list: list, place: place)),
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
