import ShipyardCore
import SwiftUI

// The panel's hover help, in place of macOS's native tooltips (`.help`):
// `hoverHelp(_:)` on a view, and `hoverHelpHost()` once on the panel, which
// draws it. The style is chosen in one place, `HoverHelp.style`.

/// How the hover help looks and when it shows.
enum HoverHelp {
    enum Style {
        /// A small card drawn in the panel (`hoverHelpHost()`), under or
        /// over the hovered view, gliding from row to row like the row
        /// highlight. The recommended style (see
        /// `docs/references/macos-hover-help.md`).
        case card
        /// SwiftUI's own popover, beside the hovered view (outside the
        /// panel for a row). The runner-up, kept to try against the card.
        case popover
    }

    /// The style every `hoverHelp(_:)` uses.
    static let style: Style = .card

    /// How long the pointer rests on a view before its help shows.
    static let delay: Duration = .milliseconds(500)
    /// How long after help hides that the next shows without `delay`, so
    /// moving along the rows reads each at once, as native tooltips do.
    static let warmth: TimeInterval = 0.6
    /// How long help waits after the pointer leaves a view before hiding,
    /// so moving to the next row glides the card rather than blinking it.
    static let grace: Duration = .milliseconds(90)
    /// The widest the card gets; longer lines wrap.
    static let maxWidth: CGFloat = 320
    /// How far the card stays in from the panel's edges.
    static let margin: CGFloat = 6
    /// The card's padding, so a row's help can line its text up with the
    /// row's title.
    static let horizontalPadding: CGFloat = 8
    /// How far in from a row's leading edge its help starts: the card's
    /// text under the row's title.
    static let rowInset = Grid.gutter + Grid.dotColumn + Grid.iconColumn - horizontalPadding
}

extension View {
    /// Shows `text` when the pointer rests on this view, and gives it to
    /// VoiceOver as the view's hint (as `.help` did); `nil` shows nothing.
    /// A view wider than the help (a row) lines the help up `leadingInset`
    /// in from its leading edge; a narrower one centres it.
    func hoverHelp(_ text: String?, leadingInset: CGFloat = Grid.gutter) -> some View {
        modifier(HoverHelpSource(text: text, leadingInset: leadingInset))
    }

    /// Draws the hover help of the views inside it: once, on the panel, so
    /// the card can reach past a scroll view's clip and stays inside the panel.
    func hoverHelpHost() -> some View {
        overlayPreferenceValue(HoverHelpKey.self) { source in
            GeometryReader { proxy in
                HoverHelpOverlay(request: source.map {
                    HoverHelpRequest(id: $0.id, text: $0.text, target: proxy[$0.anchor], leadingInset: $0.leadingInset)
                })
            }
        }
    }
}

// MARK: - The source: a view with help

/// The hovered view's help, handed up to `hoverHelpHost()`.
private struct HoverHelpAnchor {
    let id: UUID
    let text: String
    let anchor: Anchor<CGRect>
    let leadingInset: CGFloat
}

private struct HoverHelpKey: PreferenceKey {
    static var defaultValue: HoverHelpAnchor? { nil }

    static func reduce(value: inout HoverHelpAnchor?, nextValue: () -> HoverHelpAnchor?) {
        value = value ?? nextValue()
    }
}

/// `hoverHelp(_:leadingInset:)`.
private struct HoverHelpSource: ViewModifier {
    let text: String?
    let leadingInset: CGFloat
    @State private var id = UUID()
    @State private var hovering = false
    @State private var presented = false

    func body(content: Content) -> some View {
        if let text {
            styled(content, text: text)
                .onHover { hovering = $0 }
                .onDisappear { hovering = false }
                .accessibilityHint(text)
        } else {
            content
        }
    }

    @ViewBuilder
    private func styled(_ content: Content, text: String) -> some View {
        switch HoverHelp.style {
        case .card:
            content.anchorPreference(key: HoverHelpKey.self, value: .bounds) { anchor in
                hovering ? HoverHelpAnchor(id: id, text: text, anchor: anchor, leadingInset: leadingInset) : nil
            }
        case .popover:
            content
                .task(id: hovering) {
                    guard hovering else { presented = false; return }
                    try? await Task.sleep(for: HoverHelp.delay)
                    if !Task.isCancelled { presented = true }
                }
                .popover(isPresented: $presented, arrowEdge: .trailing) {
                    HoverHelpText(text: text)
                        .padding(.horizontal, HoverHelp.horizontalPadding + 2)
                        .padding(.vertical, 7)
                        .frame(maxWidth: HoverHelp.maxWidth)
                }
        }
    }
}

// MARK: - The host: the card

/// The hovered view's help, placed in the host's space.
private struct HoverHelpRequest: Equatable {
    let id: UUID
    let text: String
    let target: CGRect
    let leadingInset: CGFloat

    /// What changes the help: a new view, or new words on the same one.
    struct Key: Hashable {
        let id: UUID
        let text: String
    }

    var key: Key { Key(id: id, text: text) }
}

/// The card, shown `HoverHelp.delay` after the pointer rests on a view with
/// help (at once while it's warm), gliding to the next view, fading out
/// when the pointer leaves. It never takes the pointer from the rows under it.
private struct HoverHelpOverlay: View {
    let request: HoverHelpRequest?
    @State private var shown: HoverHelpRequest?
    @State private var hiddenAt = Date.distantPast

    var body: some View {
        HoverHelpLayout(target: shown?.target ?? .zero, leadingInset: shown?.leadingInset ?? 0) {
            if let shown {
                HoverHelpCard(text: shown.text)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        // VoiceOver reads the text as the hovered view's hint.
        .accessibilityHidden(true)
        .task(id: request?.key) { await follow(request) }
        .onChange(of: request) { _, request in
            // The same view moved under a resting pointer (the list scrolled).
            if let request, request.key == shown?.key { shown = request }
        }
        // The panel closed: open it again without the last card.
        .onDisappear { shown = nil }
    }

    private func follow(_ request: HoverHelpRequest?) async {
        guard let request else {
            guard shown != nil else { return }
            try? await Task.sleep(for: HoverHelp.grace)
            guard !Task.isCancelled else { return }
            withAnimation(Motion.hover) { shown = nil }
            hiddenAt = .now
            return
        }
        let warm = shown != nil || Date.now.timeIntervalSince(hiddenAt) < HoverHelp.warmth
        if !warm {
            try? await Task.sleep(for: HoverHelp.delay)
            guard !Task.isCancelled else { return }
        }
        withAnimation(shown == nil ? Motion.hover : Motion.highlight) { shown = request }
    }
}

/// Places the card by `HoverHelpPlacement`: under or over `target`, inside
/// the host, as wide as its text up to `HoverHelp.maxWidth`.
private struct HoverHelpLayout: Layout {
    let target: CGRect
    let leadingInset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let card = subviews.first else { return }
        let width = min(HoverHelp.maxWidth, max(bounds.width - 2 * HoverHelp.margin, 0))
        let size = card.sizeThatFits(ProposedViewSize(width: width, height: nil))
        let frame = HoverHelpPlacement.frame(
            width: size.width,
            height: size.height,
            target: HoverHelpPlacement.Rect(target.offsetBy(dx: bounds.minX, dy: bounds.minY)),
            bounds: HoverHelpPlacement.Rect(bounds),
            margin: HoverHelp.margin,
            leadingInset: leadingInset
        )
        card.place(
            at: CGPoint(x: frame.x, y: frame.y),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: frame.width, height: frame.height)
        )
    }
}

extension HoverHelpPlacement.Rect {
    init(_ rect: CGRect) {
        self.init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

/// The card: the help's text on the system's popover material, with the
/// panel's hairline and a soft shadow.
private struct HoverHelpCard: View {
    let text: String

    var body: some View {
        HoverHelpText(text: text)
            .padding(.horizontal, HoverHelp.horizontalPadding)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Grid.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
    }
}

/// The help's words: its first line in the primary colour, the lines under
/// it (a row's checks and ⌥-click hint) quieter.
private struct HoverHelpText: View {
    let text: String

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(TypeScale.meta)
                    .foregroundStyle(index == 0 ? .primary : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
