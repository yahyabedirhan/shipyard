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

    /// Where the help is, which decides its timing.
    enum Context {
        /// The header's buttons, the account and the tabs: small targets
        /// people move between on purpose, so help comes quickly and
        /// glides from one to the next, as native tooltips do.
        case toolbar
        /// The item rows: the pointer crosses them on its way elsewhere,
        /// so help waits longer, closes as the pointer leaves, and each row
        /// waits again rather than the card following the pointer down.
        case row
    }

    /// When help shows and hides.
    struct Timing {
        /// How long the pointer rests on a view before its help shows.
        let delay: Duration
        /// How long after help hides that the next in the same context
        /// shows without `delay`; zero makes every view wait `delay`, and
        /// the card never glides from one to the next.
        let warmth: TimeInterval
        /// How long help waits after the pointer leaves a view before
        /// hiding, so moving to the next glides the card rather than
        /// blinking it.
        let grace: Duration
    }

    static func timing(_ context: Context) -> Timing {
        switch context {
        case .toolbar: Timing(delay: .milliseconds(500), warmth: 0.6, grace: .milliseconds(90))
        case .row: Timing(delay: .milliseconds(1000), warmth: 0, grace: .zero)
        }
    }
    /// A row card's avatar.
    static let avatarSize: CGFloat = 20
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
    /// `context` sets its timing. A view wider than the help (a row) lines
    /// the help up `leadingInset` in from its leading edge; a narrower one
    /// centres it.
    func hoverHelp(
        _ text: String?,
        context: HoverHelp.Context = .toolbar,
        leadingInset: CGFloat = Grid.gutter
    ) -> some View {
        modifier(HoverHelpSource(content: text.map(HoverHelpContent.text), context: context, leadingInset: leadingInset))
    }

    /// Shows a row's card when the pointer rests on it, lined up
    /// `leadingInset` in from the row's leading edge, with the row's timing.
    func hoverHelp(_ card: RowCard, leadingInset: CGFloat) -> some View {
        modifier(HoverHelpSource(content: .row(card), context: .row, leadingInset: leadingInset))
    }

    /// Draws the hover help of the views inside it: once, on the panel, so
    /// the card can reach past a scroll view's clip and stays inside the panel.
    func hoverHelpHost() -> some View {
        overlayPreferenceValue(HoverHelpKey.self) { source in
            GeometryReader { proxy in
                HoverHelpOverlay(request: source.map {
                    HoverHelpRequest(
                        id: $0.id,
                        content: $0.content,
                        context: $0.context,
                        target: proxy[$0.anchor],
                        leadingInset: $0.leadingInset
                    )
                })
            }
        }
    }
}

// MARK: - The source: a view with help

/// What a hover card shows: a line or two of help, or a row's card.
enum HoverHelpContent: Hashable {
    case text(String)
    case row(RowCard)

    /// What VoiceOver reads as the view's hint.
    var spoken: String {
        switch self {
        case .text(let text): text
        case .row(let card): card.spoken
        }
    }
}

/// The hovered view's help, handed up to `hoverHelpHost()`.
private struct HoverHelpAnchor {
    let id: UUID
    let content: HoverHelpContent
    let context: HoverHelp.Context
    let anchor: Anchor<CGRect>
    let leadingInset: CGFloat
}

private struct HoverHelpKey: PreferenceKey {
    static var defaultValue: HoverHelpAnchor? { nil }

    static func reduce(value: inout HoverHelpAnchor?, nextValue: () -> HoverHelpAnchor?) {
        value = value ?? nextValue()
    }
}

/// `hoverHelp(_:context:leadingInset:)`.
private struct HoverHelpSource: ViewModifier {
    let content: HoverHelpContent?
    let context: HoverHelp.Context
    let leadingInset: CGFloat
    @State private var id = UUID()
    @State private var hovering = false
    @State private var presented = false

    func body(content: Content) -> some View {
        if let help = self.content {
            styled(content, help: help)
                .onHover { hovering = $0 }
                .onDisappear { hovering = false }
                .accessibilityHint(help.spoken)
        } else {
            content
        }
    }

    @ViewBuilder
    private func styled(_ content: Content, help: HoverHelpContent) -> some View {
        switch HoverHelp.style {
        case .card:
            content.anchorPreference(key: HoverHelpKey.self, value: .bounds) { anchor in
                hovering ? HoverHelpAnchor(id: id, content: help, context: context, anchor: anchor, leadingInset: leadingInset) : nil
            }
        case .popover:
            content
                .task(id: hovering) {
                    guard hovering else { presented = false; return }
                    try? await Task.sleep(for: HoverHelp.timing(context).delay)
                    if !Task.isCancelled { presented = true }
                }
                .popover(isPresented: $presented, arrowEdge: .trailing) {
                    HoverHelpBody(content: help)
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
    let content: HoverHelpContent
    let context: HoverHelp.Context
    let target: CGRect
    let leadingInset: CGFloat

    /// What changes the help: a new view, or new words on the same one.
    struct Key: Hashable {
        let id: UUID
        let content: HoverHelpContent
    }

    var key: Key { Key(id: id, content: content) }
}

/// The card, shown its context's delay after the pointer rests on a view
/// with help (at once while it's warm), gliding to the next view where the
/// context allows it, fading out when the pointer leaves. It never takes
/// the pointer from the rows under it.
private struct HoverHelpOverlay: View {
    let request: HoverHelpRequest?
    @State private var shown: HoverHelpRequest?
    @State private var hidden: (context: HoverHelp.Context, at: Date)?

    var body: some View {
        HoverHelpLayout(target: shown?.target ?? .zero, leadingInset: shown?.leadingInset ?? 0) {
            if let shown {
                HoverHelpCard(content: shown.content)
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
            guard let current = shown else { return }
            try? await Task.sleep(for: HoverHelp.timing(current.context).grace)
            guard !Task.isCancelled else { return }
            hide()
            return
        }
        let timing = HoverHelp.timing(request.context)
        // Glide from the card on show only within a context that glides;
        // otherwise it goes before the next view's delay starts.
        if let current = shown, current.context != request.context || timing.warmth == 0 {
            hide()
        }
        let warm = shown != nil || hidden.map {
            $0.context == request.context && Date.now.timeIntervalSince($0.at) < timing.warmth
        } ?? false
        if !warm {
            try? await Task.sleep(for: timing.delay)
            guard !Task.isCancelled else { return }
        }
        withAnimation(shown == nil ? Motion.hover : Motion.highlight) { shown = request }
    }

    private func hide() {
        guard let current = shown else { return }
        withAnimation(Motion.hover) { shown = nil }
        hidden = (current.context, .now)
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

/// The card: the help on the system's popover material, with the panel's
/// hairline and a soft shadow.
private struct HoverHelpCard: View {
    let content: HoverHelpContent

    var body: some View {
        HoverHelpBody(content: content)
            .padding(.horizontal, HoverHelp.horizontalPadding)
            .padding(.vertical, content.isRow ? 7 : 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Grid.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
    }
}

extension HoverHelpContent {
    fileprivate var isRow: Bool {
        if case .row = self { true } else { false }
    }
}

/// What the card shows: the help's words, or a row's card.
private struct HoverHelpBody: View {
    let content: HoverHelpContent

    var body: some View {
        switch content {
        case .text(let text): HoverHelpText(text: text)
        case .row(let card): RowCardView(card: card)
        }
    }
}

/// A row's card: the author's avatar beside the full title, why the row
/// needs attention as tags under it, then the facts.
private struct RowCardView: View {
    let card: RowCard

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AuthorAvatar(url: card.avatarURL)
            VStack(alignment: .leading, spacing: 3) {
                Text(card.headline)
                    .font(TypeScale.meta.weight(.semibold))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if !card.reasons.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(card.reasons, id: \.self) { AttentionTag(reason: $0, kind: card.kind) }
                    }
                    .padding(.top, 3)
                }
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(card.facts, id: \.self) { line in
                        HStack(spacing: 10) {
                            ForEach(line, id: \.self) { FactView(fact: $0) }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }
}

/// A reason the row needs attention, as a tinted tag: a review request
/// amber, failed checks red.
private struct AttentionTag: View {
    let reason: Attention.Reason
    let kind: ItemKind

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(PanelText.attentionWord(reason, kind: kind))
        }
        .font(TypeScale.meta.weight(.medium))
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.14), in: Capsule())
    }

    private var symbol: String {
        switch reason {
        case .unseen: "sparkle"
        case .changed: "arrow.triangle.2.circlepath"
        case .reviewRequested: "eye.fill"
        case .checksFailed: "xmark.circle.fill"
        }
    }

    private var tint: Color {
        switch reason {
        case .unseen, .changed: Palette.accent
        case .reviewRequested: Palette.amber
        case .checksFailed: Palette.red
        }
    }
}

/// One fact: its icon, tinted where it says how things stand (review,
/// checks, a run's time), and its words, short where the icon says the rest.
private struct FactView: View {
    let fact: RowCard.Fact

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(tint ?? .secondary)
                .frame(width: 13)
            label
        }
        .font(TypeScale.meta)
        .lineLimit(1)
    }

    @ViewBuilder
    private var label: some View {
        switch fact {
        case .branches(let head, let base):
            HStack(spacing: 3) {
                Text(head).truncationMode(.middle)
                Image(systemName: "arrow.right").imageScale(.small).foregroundStyle(.tertiary)
                Text(base)
            }
            .fontDesign(.monospaced)
            .foregroundStyle(.secondary)
        case .size(let additions, let deletions):
            HStack(spacing: 4) {
                Text("+\(additions)").foregroundStyle(Palette.green)
                Text("−\(deletions)").foregroundStyle(Palette.red)
            }
            .monospacedDigit()
        case .comments(let count), .reviews(let count):
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
        case .updated(let age):
            Text(age == "now" ? "now" : "\(age) ago").foregroundStyle(.secondary)
        case .duration(let time, _):
            Text(time).monospacedDigit().foregroundStyle(.secondary)
        default:
            Text(PanelText.fact(fact)).foregroundStyle(tint ?? .secondary)
        }
    }

    private var symbol: String {
        switch fact {
        case .branches: "arrow.triangle.branch"
        case .size: "plus.forwardslash.minus"
        case .files: "doc.on.doc"
        case .review(.approved): "checkmark.seal.fill"
        case .review(.changesRequested): "exclamationmark.bubble.fill"
        case .review(.reviewRequired): "eye"
        case .checks(.passed): "checkmark.circle.fill"
        case .checks(.failed): "xmark.circle.fill"
        case .checks: "clock.fill"
        case .comments: "bubble.left"
        case .reviews: "person.crop.circle.badge.checkmark"
        case .updated: "clock.arrow.circlepath"
        case .trigger(let event, _): Self.symbol(event: event)
        case .attempt: "arrow.clockwise"
        case .duration(_, let running): running ? "hourglass" : "timer"
        }
    }

    private var tint: Color? {
        switch fact {
        case .review(.approved): Palette.green
        case .review(.changesRequested): Palette.red
        case .review(.reviewRequired): Palette.amber
        case .checks(let state): Palette.color(state)
        case .duration(_, running: true): Palette.amber
        default: nil
        }
    }

    /// What started a run, as an icon.
    private static func symbol(event: String?) -> String {
        switch event {
        case "push": "arrow.up.circle"
        case "pull_request", "pull_request_target": "arrow.triangle.pull"
        case "schedule": "calendar"
        case "workflow_dispatch": "hand.tap"
        case "release": "shippingbox"
        case "merge_group": "arrow.triangle.merge"
        default: "bolt"
        }
    }
}

/// The author's avatar, a circle; a person glyph while it loads or when
/// GitHub gave none.
private struct AuthorAvatar: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url.map(AvatarCache.downloadURL(for:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.quaternary)
        }
        .frame(width: HoverHelp.avatarSize, height: HoverHelp.avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
    }
}

/// The help's words: its first line in the primary colour, the lines under
/// it quieter.
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
