import AppKit
import ShipyardCore
import SwiftUI

/// `[menu] layout = "list"`: every project in one scrolling list, one line
/// per item in columns (number, title, author or repository, age), under
/// project headers that stay pinned while their rows scroll by. A header
/// collapses its project, shows its attention count and, on hover, Mark
/// all seen.
struct ListLayout: View {
    let model: MenuModel
    let actions: LayoutActions
    /// The row under the pointer; one highlight glides between rows.
    @State private var hovered: String?
    @Namespace private var hoverSpace

    var body: some View {
        MeasuredScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(model.sections) { section in
                    Section {
                        if !section.isCollapsed {
                            rows(section)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: -6)),
                                    removal: .opacity.animation(.easeOut(duration: 0.12))
                                ))
                        }
                    } header: {
                        ListSectionHeader(section: section, actions: actions)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func rows(_ section: MenuSection) -> some View {
        let hasContent = !section.isLoaded || !section.rows.isEmpty || !section.errors.isEmpty
        if hasContent {
            VStack(spacing: 0) {
                if !section.isLoaded {
                    SkeletonRow(width: 190)
                    SkeletonRow(width: 140)
                }
                ForEach(section.errors) { ListErrorRow(error: $0) }
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    ListRow(
                        row: row,
                        showsRepository: section.showsRepository,
                        actions: actions,
                        hovered: $hovered,
                        hoverSpace: hoverSpace
                    )
                    if index < section.rows.count - 1, row.kind != section.rows[index + 1].kind {
                        // A line only where the kind changes: pull requests | issues | runs.
                        Hairline()
                            .padding(.leading, Grid.gutter + Grid.dotColumn + Grid.iconColumn)
                            .padding(.trailing, Grid.gutter)
                    }
                }
            }
            .padding(.vertical, 3)
            .clipped()
        }
    }
}

// MARK: - A project's header

/// The chevron, the project's name and attention count, then what the
/// project says in place of rows ("Nothing open") or, on hover, Mark all seen.
private struct ListSectionHeader: View {
    let section: MenuSection
    let actions: LayoutActions
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(Motion.collapse) { actions.toggleCollapsed(section) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(section.isCollapsed ? 0 : 90))
                        .frame(width: Grid.dotColumn)
                    Image(systemName: "folder.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(section.name)
                        .font(TypeScale.section)
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)
                    if section.attentionCount > 0 {
                        // Muted while its rows are in view; the accent once collapsed.
                        CountBadge(count: section.attentionCount, muted: !section.isCollapsed)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
                    }
                    Spacer(minLength: 8)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(section.isCollapsed ? "Expand \(section.name)" : "Collapse \(section.name)")
            .accessibilityLabel(section.name)
            .accessibilityValue(section.isCollapsed ? "Collapsed" : "Expanded")
            if let empty = PanelText.emptySection(section) {
                Text(empty)
                    .font(TypeScale.caption)
                    .foregroundStyle(.tertiary)
            } else if section.attentionCount > 0 {
                Button {
                    withAnimation(.spring(duration: 0.45, bounce: 0.15)) { actions.markAllSeen(section) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle")
                        Text("Mark all seen")
                    }
                }
                .buttonStyle(TextButtonStyle())
                .opacity(hover ? 1 : 0)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: Grid.headerHeight)
        .background(Palette.header)
        .overlay(alignment: .bottom) { Hairline() }
        .overlay(alignment: .top) { Hairline().opacity(0.6) }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(Motion.count, value: section.attentionCount)
    }
}

// MARK: - Rows

/// One item on one line: the attention dot, the state icon (with a pull
/// request's check dot on it), the number, the title (bold when it needs
/// attention; a run's is its workflow's name, followed by its branch as a
/// chip), the author or, in a multi-repository project, the repository,
/// and the age. Clicking opens it and marks it seen; ⌥-click only marks it seen.
private struct ListRow: View {
    let row: MenuRow
    let showsRepository: Bool
    let actions: LayoutActions
    @Binding var hovered: String?
    let hoverSpace: Namespace.ID
    @Environment(\.panelNow) private var now

    private var isHovered: Bool { hovered == row.id }

    var body: some View {
        Button(action: click) {
            HStack(spacing: 0) {
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 6, height: 6)
                    .opacity(row.needsAttention ? 1 : 0)
                    .scaleEffect(row.needsAttention ? 1 : 0.2)
                    .frame(width: Grid.dotColumn, alignment: .leading)
                    .accessibilityHidden(!row.needsAttention)
                    .accessibilityLabel("Needs attention")
                stateIcon
                Text(String(row.number))
                    .font(TypeScale.meta)
                    .foregroundStyle(.tertiary)
                    .frame(minWidth: Grid.numberColumn, alignment: .trailing)
                    .fixedSize()
                    .padding(.trailing, 8)
                Text(row.title)
                    .font(row.needsAttention ? TypeScale.bodyEmphasis : TypeScale.body)
                    .foregroundStyle(row.state.isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                if let branch = row.branch {
                    BranchChip(branch: branch).padding(.leading, 6)
                }
                Spacer(minLength: 8)
                if let meta {
                    HStack(spacing: 3) {
                        if let symbol = metaSymbol {
                            Image(systemName: symbol)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                        }
                        Text(meta)
                            .font(TypeScale.meta)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(width: Grid.metaColumn, alignment: .leading)
                    .padding(.leading, 6)
                }
                Text(PanelText.age(row.age(at: now)))
                    .font(TypeScale.meta)
                    .foregroundStyle(.secondary)
                    .frame(width: Grid.ageColumn, alignment: .trailing)
            }
            .padding(.leading, Grid.gutter - 4)
            .padding(.trailing, Grid.gutter)
            .frame(height: Grid.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ListRowButtonStyle(isHovered: isHovered, hoverSpace: hoverSpace))
        .onHover { inside in
            if inside { hovered = row.id } else if hovered == row.id { hovered = nil }
        }
        // ⌥-click's equivalent for the keyboard and VoiceOver.
        .accessibilityAction(named: "Mark seen") { actions.markSeen(row) }
        .help(help)
        .animation(Motion.seen, value: row.needsAttention)
        .animation(.spring(duration: 0.3, bounce: 0.15), value: hovered)
    }

    private var stateIcon: some View {
        Image(systemName: Palette.symbol(row.state, kind: row.kind))
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Palette.color(row.state, kind: row.kind))
            .symbolEffect(.pulse, options: .repeating, isActive: row.state == .running)
            .frame(width: Grid.iconColumn, alignment: .center)
            .overlay(alignment: .bottomTrailing) {
                // The check dot rides on the state icon, like a status badge.
                if let checks = row.checks, let color = Palette.color(checks) {
                    ZStack {
                        Circle().fill(Palette.panel).frame(width: 8, height: 8)
                        Circle().fill(color).frame(width: 5.5, height: 5.5)
                    }
                    .offset(x: 2, y: 2)
                    .accessibilityLabel(checksLabel(checks))
                }
            }
            .accessibilityLabel(PanelText.stateLabel(row))
    }

    /// The author, or in a project of several repositories, the repository
    /// (without its owner); a run names no author.
    private var meta: String? {
        if showsRepository { return row.repository.split(separator: "/").last.map(String.init) ?? row.repository }
        return row.kind == .workflowRun ? nil : row.author
    }

    private var metaSymbol: String? {
        if showsRepository { return "shippingbox" }
        return row.authorKind == .bot ? "cpu" : nil
    }

    /// The row's state and its full second line, and the ⌥-click hint.
    private var help: String {
        let detail = "\(PanelText.stateLabel(row)) · \(PanelText.rowDetail(row, showingRepository: showsRepository, now: now))"
        return row.needsAttention ? "\(detail)\n⌥-click to mark seen" : detail
    }

    /// ⌥ held: mark seen without opening; otherwise open (which marks seen).
    private func click() {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        withAnimation(Motion.seen) {
            if flags.contains(.option) { actions.markSeen(row) } else { actions.open(row) }
        }
    }

    private func checksLabel(_ checks: ChecksState) -> String {
        switch checks {
        case .none: ""
        case .pending: "Checks running"
        case .passed: "Checks passed"
        case .failed: "Checks failed"
        }
    }
}

/// The row's hover highlight, one shape gliding between rows, darker while pressed.
private struct ListRowButtonStyle: ButtonStyle {
    let isHovered: Bool
    let hoverSpace: Namespace.ID

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label
            .background {
                if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(configuration.isPressed ? Palette.pressed : Palette.hover)
                        .matchedGeometryEffect(id: "hover", in: hoverSpace)
                        .padding(.horizontal, Grid.inset)
                }
            }
    }
}

/// A run's branch, after its workflow's name.
private struct BranchChip: View {
    let branch: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.branch").font(.system(size: 8.5, weight: .semibold))
            Text(branch)
                .font(TypeScale.branch)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Palette.fill))
    }
}

/// A repository of the project that couldn't be fetched.
private struct ListErrorRow: View {
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

/// A placeholder row, pulsing, while a project isn't loaded yet.
private struct SkeletonRow: View {
    let width: CGFloat
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color.primary.opacity(0.08)).frame(width: 12, height: 12)
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)).frame(width: width, height: 9)
            Spacer()
            RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.06)).frame(width: 44, height: 9)
        }
        .padding(.leading, Grid.gutter + Grid.dotColumn)
        .padding(.trailing, Grid.gutter)
        .frame(height: Grid.rowHeight)
        .opacity(pulse ? 0.5 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
        .accessibilityHidden(true)
    }
}
