import ShipyardConfig
import ShipyardCore
import SwiftUI

enum HoverHelp {
    enum Context {
        case toolbar
        case row
    }

    struct Timing {
        let delay: Duration
        let warmth: TimeInterval
        let grace: Duration
    }

    static func timing(_ context: Context) -> Timing {
        switch context {
        case .toolbar: Timing(delay: .milliseconds(500), warmth: 0.6, grace: .milliseconds(90))
        case .row: Timing(delay: .milliseconds(1000), warmth: 0, grace: .zero)
        }
    }
    static let avatarSize: CGFloat = 20
    static let avatarGap: CGFloat = 8
    static let maxWidth: CGFloat = 320
    static let margin: CGFloat = 6
    static let horizontalPadding: CGFloat = 8
    /// A row card's inset from the panel's leading edge, under the row's title.
    static func rowInset(_ grid: Grid) -> CGFloat {
        grid.gutter + Grid.dotColumn + Grid.iconColumn - horizontalPadding
    }
}

extension View {
    func hoverHelp(
        _ text: String?,
        context: HoverHelp.Context = .toolbar,
        leadingInset: CGFloat? = nil
    ) -> some View {
        modifier(HoverHelpSource(content: text.map(HoverHelpContent.text), context: context, leadingInset: leadingInset))
    }

    func hoverHelp(markdown text: String, context: HoverHelp.Context = .toolbar) -> some View {
        modifier(HoverHelpSource(content: .markdown(text), context: context, leadingInset: nil))
    }

    func hoverHelp(_ card: RowCard, leadingInset: CGFloat) -> some View {
        modifier(HoverHelpSource(content: .row(card), context: .row, leadingInset: leadingInset))
    }

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

enum HoverHelpContent: Hashable {
    case text(String)
    case markdown(String)
    case row(RowCard)

    var spoken: String {
        switch self {
        case .text(let text): text
        case .markdown(let text): text.replacingOccurrences(of: "`", with: "")
        case .row(let card): card.spoken
        }
    }
}

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

private struct HoverHelpSource: ViewModifier {
    let content: HoverHelpContent?
    let context: HoverHelp.Context
    /// How far the card sits in from the panel's leading edge; `nil` is the gutter.
    let leadingInset: CGFloat?
    @Environment(\.panelScale) private var scale
    @State private var id = UUID()
    @State private var hovering = false

    func body(content: Content) -> some View {
        if let help = self.content {
            let inset = leadingInset ?? scale.grid.gutter
            content
                .anchorPreference(key: HoverHelpKey.self, value: .bounds) { anchor in
                    hovering ? HoverHelpAnchor(id: id, content: help, context: context, anchor: anchor, leadingInset: inset) : nil
                }
                .onHover { hovering = $0 }
                .onDisappear { hovering = false }
                .accessibilityHint(help.spoken)
        } else {
            content
        }
    }
}

private struct HoverHelpRequest: Equatable {
    let id: UUID
    let content: HoverHelpContent
    let context: HoverHelp.Context
    let target: CGRect
    let leadingInset: CGFloat

    struct Key: Hashable {
        let id: UUID
        let content: HoverHelpContent
    }

    var key: Key { Key(id: id, content: content) }
}

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
        .accessibilityHidden(true)
        .task(id: request?.key) { await follow(request) }
        .onChange(of: request) { _, request in
            if let request, request.key == shown?.key { shown = request }
        }
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

private struct HoverHelpCard: View {
    let content: HoverHelpContent
    @Environment(\.panelScale) private var scale

    var body: some View {
        HoverHelpBody(content: content)
            .padding(.horizontal, HoverHelp.horizontalPadding)
            .padding(.vertical, content.isRow ? 7 : 5)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: scale.grid.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: scale.grid.radius, style: .continuous).strokeBorder(ThemeColor.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
    }
}

extension HoverHelpContent {
    fileprivate var isRow: Bool {
        if case .row = self { true } else { false }
    }
}

private struct HoverHelpBody: View {
    let content: HoverHelpContent

    var body: some View {
        switch content {
        case .text(let text): HoverHelpText(text: text)
        case .markdown(let text):
            MarkdownText(text, size: 11)
                .foregroundStyle(ThemeColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        case .row(let card): RowCardView(card: card)
        }
    }
}

private struct RowCardView: View {
    let card: RowCard
    @Environment(\.panelScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .center, spacing: HoverHelp.avatarGap) {
                if let agent = card.agent {
                    AgentMarkView(agent: agent, size: HoverHelp.avatarSize)
                } else {
                    AuthorAvatar(url: card.avatarURL)
                }
                Text(card.headline)
                    .font(scale.type.meta.weight(.semibold))
                    .foregroundStyle(ThemeColor.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 3) {
                if !card.reasons.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(card.reasons, id: \.self) { AttentionTag(reason: $0, kind: card.kind) }
                    }
                    .padding(.top, 3)
                }
                if !card.facts.isEmpty {
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
            .padding(.leading, HoverHelp.avatarSize + HoverHelp.avatarGap)
        }
    }
}

private struct AttentionTag: View {
    let reason: Attention.Reason
    let kind: ItemKind
    @Environment(\.panelScale) private var scale

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).imageScale(.small)
            Text(PanelText.attentionWord(reason, kind: kind))
        }
        .font(scale.type.meta.weight(.medium))
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

    private var tint: ThemeColor {
        switch reason {
        case .unseen, .changed: ThemeColor.accent
        case .reviewRequested: ThemeColor.review(.reviewRequired)
        case .checksFailed: ThemeColor.state(.check, "failed")
        }
    }
}

private struct FactView: View {
    let fact: RowCard.Fact
    @Environment(\.panelScale) private var scale

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .imageScale(.small)
                .foregroundStyle(tint ?? ThemeColor.textSecondary)
                .frame(width: 13)
            label
        }
        .font(scale.type.meta)
        .lineLimit(1)
    }

    @ViewBuilder
    private var label: some View {
        switch fact {
        case .branches(let head, let base):
            HStack(spacing: 3) {
                Text(head).truncationMode(.middle)
                Image(systemName: "arrow.right").imageScale(.small).foregroundStyle(ThemeColor.textTertiary)
                Text(base)
            }
            .fontDesign(.monospaced)
            .foregroundStyle(ThemeColor.textSecondary)
        case .size(let additions, let deletions):
            HStack(spacing: 4) {
                Text("+\(additions)").foregroundStyle(ThemeColor.active)
                Text("−\(deletions)").foregroundStyle(ThemeColor.failed)
            }
            .monospacedDigit()
        case .comments(let count), .reviews(let count):
            Text("\(count)").monospacedDigit().foregroundStyle(ThemeColor.textSecondary)
        case .updated(let age):
            Text(PanelText.updatedAge(age)).foregroundStyle(ThemeColor.textSecondary)
        case .duration(let time, _):
            Text(time).monospacedDigit().foregroundStyle(ThemeColor.textSecondary)
        case .body(let text):
            Text(text)
                .foregroundStyle(ThemeColor.textPrimary.opacity(0.78))
                .lineLimit(8)
                .fixedSize(horizontal: false, vertical: true)
        case .action, .noAction:
            Text(PanelText.fact(fact)).foregroundStyle(ThemeColor.textSecondary).truncationMode(.middle)
        default:
            Text(PanelText.fact(fact)).foregroundStyle(tint ?? ThemeColor.textSecondary)
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
        case .body: "text.alignleft"
        case .action(let action): ItemSymbol.name(action.icon)
        case .noAction: "checkmark.circle"
        case .failure: "exclamationmark.triangle.fill"
        }
    }

    private var tint: ThemeColor? {
        switch fact {
        case .review(let decision): ThemeColor.review(decision)
        case .checks(let checks): ThemeColor.checks(checks)
        case .duration(_, running: true): ThemeColor.state(.run, "running")
        case .failure: ThemeColor.failed
        default: nil
        }
    }

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

private struct AuthorAvatar: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url.map(AvatarCache.downloadURL(for:))) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(ThemeColor.textTertiary.opacity(0.6))
        }
        .frame(width: HoverHelp.avatarSize, height: HoverHelp.avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ThemeColor.border, lineWidth: 0.5))
    }
}

private struct HoverHelpText: View {
    let text: String
    @Environment(\.panelScale) private var scale

    var body: some View {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(scale.type.meta)
                    .foregroundStyle(index == 0 ? ThemeColor.textPrimary : ThemeColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
