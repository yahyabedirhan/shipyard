import AppKit
import ShipyardCore
import SwiftUI

struct RowSlot: Hashable {
    var list: AnyHashable?
    var place: MenuRowPlace
}

struct RowBoundsKey: PreferenceKey {
    static var defaultValue: [RowSlot: Anchor<CGRect>] { [:] }

    static func reduce(value: inout [RowSlot: Anchor<CGRect>], nextValue: () -> [RowSlot: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

@MainActor
final class RowFrames {
    nonisolated static let space = "row-frames"
    var visibleHeight: Double = 0
    private var spans: [RowSlot: (span: RowSpan, owner: UUID)] = [:]
    var rowsMoved: (() -> Void)?

    func span(at slot: RowSlot) -> RowSpan? {
        spans[slot]?.span
    }

    func report(_ span: RowSpan, at slot: RowSlot, by owner: UUID) {
        spans[slot] = (span, owner)
        rowsMoved?()
    }

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
    fileprivate var rowFrames: RowFrames? {
        get { self[RowFramesKey.self] }
        set { self[RowFramesKey.self] = newValue }
    }

    fileprivate var rowList: AnyHashable? {
        get { self[RowListKey.self] }
        set { self[RowListKey.self] = newValue }
    }
}

struct RowListTop: View {
    static let id = "row-list-top"

    var body: some View {
        Color.clear.frame(height: 0).id(Self.id)
    }
}

struct RowListBottom: View {
    static let id = "row-list-bottom"

    var body: some View {
        Color.clear.frame(height: 0).id(Self.id)
    }
}

extension View {
    func highlightable(_ place: MenuRowPlace, _ highlight: Binding<RowHighlight>, drawsOwnHighlight: Bool = false) -> some View {
        modifier(Highlightable(place: place, highlight: highlight, drawsOwnHighlight: drawsOwnHighlight))
    }

    func rowList(_ list: some Hashable) -> some View {
        environment(\.rowList, AnyHashable(list))
    }

    /// Tags the rows below as `list`'s, or as no list's when it's `nil`.
    func rowsTagged(_ list: AnyHashable?) -> some View {
        environment(\.rowList, list)
    }

    func clearsRowHighlight(_ highlight: Binding<RowHighlight>) -> some View {
        onHover { inside in
            if inside { highlight.wrappedValue.pointerLeftRows() }
        }
    }

    func rowKeys(
        _ highlight: Binding<RowHighlight>,
        places: [MenuRowPlace],
        in list: AnyHashable? = nil,
        pinnedHeader: CGFloat = 0,
        scroll: ScrollViewProxy,
        left: @escaping (inout RowHighlight) -> RowKeyMove,
        right: @escaping (inout RowHighlight) -> RowKeyMove,
        dismiss: @escaping (MenuRowPlace) -> Bool,
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
            dismiss: dismiss,
            activate: activate
        ))
    }
}

enum RowKeyMove {
    case ignored
    case moved
    case newList
}

private struct Highlightable: ViewModifier {
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let drawsOwnHighlight: Bool
    @Environment(\.rowFrames) private var frames
    @Environment(\.rowList) private var list
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
            .onDisappear { frames?.forget(slot, by: report.owner) }
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

private struct RowKeys: ViewModifier {
    @Binding var highlight: RowHighlight
    let places: [MenuRowPlace]
    let list: AnyHashable?
    let pinnedHeader: CGFloat
    let scroll: ScrollViewProxy
    let left: (inout RowHighlight) -> RowKeyMove
    let right: (inout RowHighlight) -> RowKeyMove
    let dismiss: (MenuRowPlace) -> Bool
    let activate: (MenuRowPlace, Bool) -> Bool
    @FocusState private var focused: Bool
    @State private var frames = RowFrames()
    @State private var pointer = PointerLocation()
    @State private var latest = LatestRowKeys()

    func body(content: Content) -> some View {
        latest.update(self)
        return content
            .coordinateSpace(.named(RowFrames.space))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { frames.visibleHeight = $0 }
            .environment(\.rowFrames, frames)
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
            .onKeyPress(.delete, phases: .down) { _ in latest.keys?.dismissHighlighted() ?? .ignored }
            .onContinuousHover(coordinateSpace: .global) { phase in
                guard case .active(let location) = phase, location != pointer.location else { return }
                pointer.location = location
                latest.landing = nil
                if !highlight.followsPointer { highlight.pointerMoved() }
            }
    }

    private var current: RowHighlight {
        latest.unrendered ?? highlight
    }

    private func set(_ next: RowHighlight) {
        highlight = next
        latest.unrendered = next
    }

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
            scroll.scrollTo(RowListTop.id, anchor: .top)
        }
        return .handled
    }

    private func activate(markSeenOnly: Bool) -> KeyPress.Result {
        guard let place = current.place, activate(place, markSeenOnly) else { return .ignored }
        return .handled
    }

    private func dismissHighlighted() -> KeyPress.Result {
        guard let place = current.place, dismiss(place) else { return .ignored }
        return .handled
    }

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
            rowsMoved()
        }
    }

    private func scrollToEnd(_ end: RowScroll) {
        if end == .wrapToTop {
            scroll.scrollTo(RowListTop.id, anchor: .top)
        } else {
            scroll.scrollTo(RowListBottom.id, anchor: .bottom)
        }
    }

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
    var unrendered: RowHighlight?
    var landing: RowWrapLanding?
    var checkQueued = false

    func update(_ keys: RowKeys) {
        self.keys = keys
        unrendered = nil
    }
}

private final class RowReport {
    let owner = UUID()
    var last: RowSpan?
}

private final class PointerLocation {
    var location: CGPoint?
}

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

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
