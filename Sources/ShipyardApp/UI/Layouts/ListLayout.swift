import ShipyardCore
import SwiftUI

/// `[menu] layout = "list"`: every project in one scrolling list, one line
/// per item in columns (number, title, author or repository, age), under
/// project headers that stay pinned while their rows scroll by. A header
/// collapses its project, shows its attention count and, on hover, Mark
/// all seen.
///
/// The keys: ↑ and ↓ step through headers and items, wrapping at
/// the ends; ← goes from an item to its header and collapses an expanded
/// header; → expands a collapsed header and goes from an expanded one to
/// its first item; Return opens the highlighted item (⌥Return marks it
/// seen) or the header's repository. Every row is a direct child of the
/// lazy stack, with its place as its id, so the keys can scroll to a row
/// that isn't laid out yet.
struct ListLayout: View {
    let model: MenuModel
    let actions: LayoutActions
    /// The row or header under the pointer or chosen with the keys; one
    /// highlight glides between rows, and a header draws its own.
    @State private var highlight = RowHighlight()

    var body: some View {
        ScrollViewReader { proxy in
            MeasuredScrollView {
                VStack(spacing: 0) {
                    // The list's ends, outside the lazy stack, for ↑ and ↓ to
                    // wrap to: always laid out, unlike the far end's rows.
                    RowListTop()
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(model.sections) { section in
                            Section {
                                if !section.isCollapsed {
                                    lines(section)
                                }
                            } header: {
                                let place = MenuRowPlace.header(section.name)
                                ListSectionHeader(
                                    section: section,
                                    isHighlighted: highlight.isHighlighted(place),
                                    actions: actions
                                )
                                .highlightable(place, $highlight, drawsOwnHighlight: true)
                                .id(place)
                            }
                        }
                    }
                    .rowHighlight(highlight)
                    RowListBottom()
                }
            }
            .onHover { inside in
                if !inside { highlight.pointerLeftRows() }
            }
            .rowKeys(
                $highlight,
                places: model.listRowPlaces,
                pinnedHeader: Grid.headerHeight,
                scroll: proxy,
                left: { fold($0.moveLeft(in: model)) },
                right: { fold($0.moveRight(in: model)) },
                activate: activate
            )
        }
        .onChange(of: model.listRowPlaces) { _, places in highlight.keep(in: places) }
    }

    /// After ← or →: collapses or expands the project it asks for, not
    /// animated (see `lineTransition`).
    private func fold(_ change: ProjectFold?) -> RowKeyMove {
        guard let change else { return .moved }
        if let section = model.sections.first(where: { $0.name == change.project }) {
            actions.toggleCollapsed(section)
        }
        return .moved
    }

    /// Return: opens the item (⌥Return: marks it seen) or the header's
    /// repository. ⌥Return on a header does nothing.
    private func activate(_ place: MenuRowPlace, markSeenOnly: Bool) -> Bool {
        switch model.listTarget(at: place) {
        case .item(let row):
            withAnimation(Motion.seen) {
                if markSeenOnly { actions.markSeen(row) } else { actions.open(row) }
            }
            return true
        case .project(let section):
            guard !markSeenOnly, section.repositoryURL != nil else { return false }
            actions.openRepository(section)
            return true
        case nil:
            return false
        }
    }

    /// An expanded project's lines, each its own child of the lazy stack:
    /// placeholders while it loads, its error rows, then its rows, with a
    /// line where the kind changes.
    @ViewBuilder
    private func lines(_ section: MenuSection) -> some View {
        let hasContent = !section.isLoaded || !section.rows.isEmpty || !section.errors.isEmpty
        if hasContent {
            Color.clear.frame(height: 3).transition(Self.lineTransition)
        }
        if !section.isLoaded {
            SkeletonRow(width: 190).clearsRowHighlight($highlight).transition(Self.lineTransition)
            SkeletonRow(width: 140).clearsRowHighlight($highlight).transition(Self.lineTransition)
        }
        ForEach(section.errors) {
            ErrorRow(error: $0).clearsRowHighlight($highlight).transition(Self.lineTransition)
        }
        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
            let place = MenuRowPlace(section: section.name, row: row.id)
            VStack(spacing: 0) {
                if index > 0, row.kind != section.rows[index - 1].kind {
                    // A line only where the kind changes: pull requests | issues | runs.
                    Hairline()
                        .padding(.leading, Grid.gutter + Grid.dotColumn + Grid.iconColumn)
                        .padding(.trailing, Grid.gutter)
                }
                ListRow(row: row, showsRepository: section.showsRepository)
                    .itemRow(row, at: place, highlight: $highlight, showsRepository: section.showsRepository, actions: actions)
            }
            .id(place)
            .transition(Self.lineTransition)
        }
        if hasContent {
            Color.clear.frame(height: 3).transition(Self.lineTransition)
        }
    }

    /// A project's lines coming in as it expands and going as it collapses,
    /// and any line a refresh adds or drops. A fold isn't animated, so the
    /// lazy stack puts the headers and rows below straight in their new
    /// places, even past the window, where an animated one holds a header
    /// over the new rows until its spring ends. The lines carry their own
    /// animation instead: they fade in where they land, and go at once,
    /// since the headers below have already moved up over them.
    private static let lineTransition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: -6)).animation(Motion.collapse),
        removal: .identity
    )
}

// MARK: - A project's header

/// The chevron, the project's name and attention count, then what the
/// project says in place of rows ("Nothing open") or, on hover, Mark all
/// seen. Highlighted by the pointer or the keys, it draws the highlight
/// over its own background, since it pins above the rows: a square band the header's full width.
private struct ListSectionHeader: View {
    let section: MenuSection
    let isHighlighted: Bool
    let actions: LayoutActions
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                // Not animated (see `ListLayout.lineTransition`): the chevron, the count and the lines animate themselves.
                actions.toggleCollapsed(section)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .animation(Motion.collapse) { $0.rotationEffect(.degrees(section.isCollapsed ? 0 : 90)) }
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
                            .animation(Motion.collapse, value: section.isCollapsed)
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
                MarkSeenButton(title: PanelText.markAllSeen) {
                    withAnimation(.spring(duration: 0.45, bounce: 0.15)) { actions.markAllSeen(section) }
                }
                .opacity(hover ? 1 : 0)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: Grid.headerHeight)
        .background {
            ZStack {
                Palette.header
                if isHighlighted {
                    // The header's whole band, square: not the rows' rounded, inset shape.
                    Rectangle()
                        .fill(Palette.hover)
                        .transition(.opacity)
                }
            }
            .animation(Motion.hover, value: isHighlighted)
        }
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
/// and the age. What a click does, its tooltip and its highlight come
/// from `itemRow(…)`.
private struct ListRow: View {
    let row: MenuRow
    let showsRepository: Bool
    @Environment(\.panelNow) private var now

    var body: some View {
        HStack(spacing: 0) {
            AttentionDot(isOn: row.needsAttention)
                .frame(width: Grid.dotColumn, alignment: .leading)
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

    private var stateIcon: some View {
        StateSymbol(row: row)
            .frame(width: Grid.iconColumn, alignment: .center)
            // The check dot rides on the state icon, like a status badge.
            .overlay(alignment: .bottomTrailing) { CheckDot(checks: row.checks).offset(x: 2, y: 2) }
    }

    /// The author, or in a project of several repositories, the repository
    /// (without its owner); a run names no author.
    private var meta: String? {
        if showsRepository { return PanelText.repositoryName(row.repository) }
        return row.kind == .workflowRun ? nil : row.author
    }

    private var metaSymbol: String? {
        if showsRepository { return "shippingbox" }
        return row.authorKind == .bot ? "cpu" : nil
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
