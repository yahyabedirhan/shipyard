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
    /// Called after a row reports a new span: the rows moved.
    var rowsMoved: (() -> Void)?

    /// Where the row at `slot` sits, if it's laid out.
    func span(at slot: RowSlot) -> RowSpan? {
        spans[slot]?.span
    }

    /// The row view `owner` at `slot` is at `span`.
    func report(_ span: RowSpan, at slot: RowSlot, by owner: UUID) {
        spans[slot] = (span, owner)
        rowsMoved?()
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

/// The top of a layout's scrolling list, outside the lazy stack and above
/// anything that transitions: where `rowKeys(…)` scrolls when ↓ wraps to
/// the first row, and when ← or → moves the highlight to a new list
/// (another tab). It's always laid out, unlike a row the lazy stack hasn't
/// made yet, a new tab's rows, or a row the outgoing tab shares.
struct RowListTop: View {
    static let id = "row-list-top"

    var body: some View {
        Color.clear.frame(height: 0).id(Self.id)
    }
}

/// The bottom of a layout's scrolling list, below the rows and outside the
/// lazy stack: where `rowKeys(…)` scrolls when ↑ wraps to the last row,
/// which the lazy stack usually hasn't laid out.
struct RowListBottom: View {
    static let id = "row-list-bottom"

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
    /// move `highlight` through `places`, wrapping at the ends, and repeat
    /// while held; `left` and `right` are the layout's ← and →, which move
    /// the highlight they're given. The highlighted row is kept in
    /// view, clear of a `pinnedHeader` that tall, without animating the
    /// scroll; a wrap goes to the list's `RowListTop` or `RowListBottom`,
    /// which the layout puts around its rows. Return calls `activate(place, false)` and ⌥Return
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
        left: @escaping (inout RowHighlight) -> RowKeyMove,
        right: @escaping (inout RowHighlight) -> RowKeyMove,
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
    /// This row view, among others at the same slot (the outgoing tab's
    /// row, or one the lazy list dropped and made again), and the span it
    /// last saw.
    @State private var report = RowReport()

    private var slot: RowSlot { RowSlot(list: list, place: place) }

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: RowBoundsKey.self, value: .bounds) { drawsOwnHighlight ? [:] : [slot: $0] }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(RowFrames.space)) } action: { frame in
                let span = RowSpan(top: frame.minY, bottom: frame.maxY)
                report.last = span
                frames?.report(span, at: slot, by: report.owner)
            }
            // A row the lazy list dropped isn't where it last was.
            .onDisappear { frames?.forget(slot, by: report.owner) }
            // A row the lazy list kept and shows again, where it was when
            // it went (a wrap back to the list's end it wrapped from),
            // sees no geometry change, so it reports its span again here.
            .onAppear {
                if let last = report.last { frames?.report(last, at: slot, by: report.owner) }
            }
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
    let left: (inout RowHighlight) -> RowKeyMove
    let right: (inout RowHighlight) -> RowKeyMove
    let activate: (MenuRowPlace, Bool) -> Bool
    @FocusState private var focused: Bool
    @State private var frames = RowFrames()
    /// Where the pointer last was, in the window. Kept out of the view's
    /// state: it changes on every move and draws nothing.
    @State private var pointer = PointerLocation()
    @State private var latest = LatestRowKeys()

    func body(content: Content) -> some View {
        latest.update(self)
        return content
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
            .onAppear {
                focused = true
                frames.rowsMoved = { [latest] in latest.keys?.rowsMoved() }
            }
            .background(WindowBecameKey { focused = true })
            // Held down, ↑ and ↓ repeat at the system's rate: `onKeyPress`
            // calls the handler it had at the key-down for each repeat, so
            // the handlers act through `latest`, the modifier as last
            // drawn. Each step scrolls without animating. ←, → and Return
            // act once per press.
            .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in latest.keys?.step(down: true) ?? .ignored }
            .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in latest.keys?.step(down: false) ?? .ignored }
            .onKeyPress(.leftArrow, phases: .down) { _ in latest.keys?.side(\.left) ?? .ignored }
            .onKeyPress(.rightArrow, phases: .down) { _ in latest.keys?.side(\.right) ?? .ignored }
            .onKeyPress(.return, phases: .down) { press in
                latest.keys?.activate(markSeenOnly: press.modifiers.contains(.option)) ?? .ignored
            }
            .onContinuousHover(coordinateSpace: .global) { phase in
                // Scrolling moves the rows under a resting pointer, not the
                // pointer: only a new location hands the highlight back.
                guard case .active(let location) = phase, location != pointer.location else { return }
                pointer.location = location
                latest.landing = nil
                if !highlight.followsPointer { highlight.pointerMoved() }
            }
    }

    /// The highlight as the keys last left it: a binding reads the value
    /// from the view's last update, not one just written to it.
    private var current: RowHighlight {
        latest.unrendered ?? highlight
    }

    private func set(_ next: RowHighlight) {
        highlight = next
        latest.unrendered = next
    }

    /// ↓ (`down`) or ↑: the next or previous row, wrapping, scrolled into view.
    private func step(down: Bool) -> KeyPress.Result {
        latest.landing = nil
        var next = current
        let previous = next.place
        if down { next.moveDown(in: places) } else { next.moveUp(in: places) }
        set(next)
        guard let place = next.place else { return .ignored }
        reveal(place, from: previous)
        return .handled
    }

    /// ← or →, as the layout's `move` has it.
    private func side(_ move: KeyPath<RowKeys, (inout RowHighlight) -> RowKeyMove>) -> KeyPress.Result {
        latest.landing = nil
        var next = current
        let previous = next.place
        let result = self[keyPath: move](&next)
        guard result != .ignored else { return .ignored }
        set(next)
        switch result {
        case .ignored, .moved:
            if let place = next.place { reveal(place, from: previous) }
        case .newList:
            // Not to the highlighted row: the new tab isn't laid out yet,
            // and the outgoing one has a row with the same id.
            scroll.scrollTo(RowListTop.id, anchor: .top)
        }
        return .handled
    }

    /// Return: acts on the highlighted row, if there is one and it acts.
    private func activate(markSeenOnly: Bool) -> KeyPress.Result {
        guard let place = current.place, activate(place, markSeenOnly) else { return .ignored }
        return .handled
    }

    /// Scrolls `place` into view, as far as it takes and no further; a
    /// wrap goes straight to the list's other end.
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
        case .wrapToTop, .wrapToBottom:
            scrollToEnd(move)
            latest.landing = RowWrapLanding(move, to: place)
            // Checked once this scroll is laid out, even if no row moved.
            rowsMoved()
        }
    }

    /// The list's top (`RowListTop`) for `.wrapToTop`, its bottom
    /// (`RowListBottom`) for `.wrapToBottom`.
    private func scrollToEnd(_ end: RowScroll) {
        if end == .wrapToTop {
            scroll.scrollTo(RowListTop.id, anchor: .top)
        } else {
            scroll.scrollTo(RowListBottom.id, anchor: .bottom)
        }
    }

    /// Rows moved while a wrap is landing: once they're all laid out (after
    /// this update), checks the wrap's row and scrolls to the end again if
    /// it's short of it.
    fileprivate func rowsMoved() {
        guard latest.landing != nil, !latest.checkQueued else { return }
        latest.checkQueued = true
        DispatchQueue.main.async { [latest] in
            latest.checkQueued = false
            latest.keys?.checkLanding()
        }
    }

    private func checkLanding() {
        guard var landing = latest.landing else { return }
        let frame = frames.span(at: RowSlot(list: list, place: landing.target))
        switch landing.check(frame: frame, visibleHeight: frames.visibleHeight) {
        case .landed, .giveUp:
            latest.landing = nil
        case .scrollAgain:
            latest.landing = landing
            scrollToEnd(landing.scroll)
        }
    }
}

/// The `RowKeys` last drawn, for its key handlers, and the highlight a key
/// set since. SwiftUI calls a key-down's handler again for each repeat,
/// with that handler's copy of the modifier: its rows, and its binding's
/// value, from before the first step, so every repeat would take the same
/// step. A reference kept out of view state: it changes on every update
/// and draws nothing.
@MainActor
private final class LatestRowKeys {
    private(set) var keys: RowKeys?
    /// The highlight a key set that the view hasn't been updated with yet,
    /// for a repeat that comes before the update.
    var unrendered: RowHighlight?
    /// A wrap still scrolling to the list's far end, until its row lands;
    /// any key or pointer move ends it.
    var landing: RowWrapLanding?
    /// Whether a check of `landing` is already waiting for the rows to
    /// be laid out.
    var checkQueued = false

    /// The view was updated with `keys`, whose binding has the highlight.
    func update(_ keys: RowKeys) {
        self.keys = keys
        unrendered = nil
    }
}

/// `Highlightable`'s row view and the span it last saw. Kept out of view
/// state: it changes on every scroll and draws nothing.
private final class RowReport {
    let owner = UUID()
    var last: RowSpan?
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
