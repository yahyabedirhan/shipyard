import AppKit
import ShipyardConfig
import ShipyardCore
import SwiftUI

/// `[menu] layout = "list"`: every project in one scrolling list, one line
/// per item in columns (number, title, author or repository, age), under
/// project headers that stay pinned while their rows scroll by. A header
/// collapses its project, shows a count chip per kind and, on hover, Mark
/// all seen.
///
/// The keys: ↑ and ↓ step through headers, subheaders and items, wrapping
/// at the ends; ← goes from an item to its subheader (or header) and folds
/// an open subheader or collapses an expanded header; → expands or unfolds
/// and goes from an open one to what's first under it; Return opens the
/// highlighted item (⌥Return marks it seen) or the header's repository, and
/// folds or unfolds a subheader. Every row is a direct child of the
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
                dismiss: dismiss,
                activate: activate
            )
        }
        .onChange(of: model.listRowPlaces) { _, places in highlight.keep(in: places) }
    }

    /// After ← or →: collapses or expands the project, or folds or unfolds
    /// the subsection, it asks for, not animated (see `lineTransition`).
    private func fold(_ change: MenuFold?) -> RowKeyMove {
        switch change {
        case nil:
            break
        case .collapse(let project), .expand(let project):
            if let section = model.sections.first(where: { $0.name == project }) {
                actions.toggleCollapsed(section)
            }
        case .fold(let id), .unfold(let id):
            if let group = model.subsection(id) {
                actions.toggleGroup(group)
            }
        }
        return .moved
    }

    /// Return: opens the item (⌥Return: marks it seen) or the header's
    /// repository, folds or unfolds a subsection, or toggles Show more.
    /// ⌥Return on a header, a subheader or a Show more row does nothing.
    private func activate(_ place: MenuRowPlace, markSeenOnly: Bool) -> Bool {
        switch model.listTarget(at: place) {
        case .group(let group):
            guard !markSeenOnly else { return false }
            actions.toggleGroup(group)
            return true
        case .showMore(let group):
            guard !markSeenOnly else { return false }
            actions.toggleShowMore(group)
            return true
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

    /// ⌫: removes the highlighted row when it's a ping's.
    private func dismiss(_ place: MenuRowPlace) -> Bool {
        guard case .item(let row) = model.listTarget(at: place), row.item.ping != nil else { return false }
        withAnimation(Motion.seen) { actions.dismiss(row) }
        return true
    }

    /// An expanded project's lines, each its own child of the lazy stack:
    /// placeholders while it loads, its error rows, then its groups' rows,
    /// each group under its subheader or after a line, and a capped group's
    /// Show more row after its rows.
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
        ForEach(section.notes, id: \.self) {
            NoteRow(note: $0).clearsRowHighlight($highlight).transition(Self.lineTransition)
        }
        ForEach(Array(section.groups.enumerated()), id: \.element.id) { index, group in
            if group.showsHeader {
                let place = MenuRowPlace.groupHeader(group.id, in: section.name)
                GroupHeader(group: group, place: place, highlight: $highlight, actions: actions)
                    .id(place)
                    .transition(Self.lineTransition)
            }
            // Every row's number column holds the group's longest number, so
            // its titles line up even past the column's width: "WORK-27"
            // over "WORK-1".
            let widestNumber = group.rows.map(PanelText.number).max { $0.count < $1.count } ?? ""
            // A folded subsection shows its subheader alone.
            ForEach(Array((group.isFolded ? [] : group.rows).enumerated()), id: \.element.id) { position, row in
                let place = MenuRowPlace(section: section.name, row: row.id)
                VStack(spacing: 0) {
                    if index > 0, position == 0, !group.showsHeader {
                        // A line where one group ends and the next begins:
                        // by default pull requests | issues | runs.
                        GroupDivider()
                    }
                    ListRow(row: row, showsRepository: section.showsRepository, widestNumber: widestNumber)
                        .itemRow(row, at: place, highlight: $highlight, showsRepository: section.showsRepository, actions: actions)
                }
                .id(place)
                .transition(Self.lineTransition)
            }
            if group.hasShowMore, !group.isFolded {
                let place = MenuRowPlace.showMore(group.id, in: section.name)
                ShowMoreRow(group: group, place: place, highlight: $highlight, actions: actions)
                    .id(place)
                    .transition(Self.lineTransition)
            }
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

/// The chevron and the project's name, then right beside the name the
/// open-in-browser icon, shown on hover while the project has a
/// repository; then, right-aligned, Mark all seen's check, shown on hover
/// while anything needs attention; then a count chip per kind the project
/// has rows of (`MenuSection.headerCounts`), each as wide as its content
/// and, for a kind with a page on GitHub, a button that opens it (in a
/// project of several repositories, a menu of each one's page and count),
/// or what the project says in their place ("Nothing open"); and last the new-note icon, when the project has
/// one. Nothing keeps a fixed slot. Highlighted by the pointer or the
/// keys, it draws the highlight over its own background, since it pins
/// above the rows: a square band the header's full width.
private struct ListSectionHeader: View {
    let section: MenuSection
    let isHighlighted: Bool
    let actions: LayoutActions
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            // The fold button fills the header's left part; the chevron,
            // folder and name are drawn over it and let clicks through,
            // so only the open-in-browser icon beside the name takes its own.
            ZStack(alignment: .leading) {
                Button {
                    // Not animated (see `ListLayout.lineTransition`): the chevron, the chips and the lines animate themselves.
                    actions.toggleCollapsed(section)
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                // No hover help: the chevron says it collapses. VoiceOver hears what a click does.
                .accessibilityLabel(section.name)
                .accessibilityValue(section.isCollapsed ? "Collapsed" : "Expanded")
                .accessibilityHint(PanelText.sectionFoldHelp(section.name, isCollapsed: section.isCollapsed))
                HStack(spacing: 6) {
                    Group {
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
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    if let repository = section.repositories.first {
                        OpenRepositoryIcon(repository: repository) { actions.openRepository(section) }
                            .fixedSize()
                            .opacity(hover ? 1 : 0)
                    }
                }
                .padding(.trailing, 8)
            }
            if let empty = PanelText.emptySection(section) {
                // In place of the chips, right-aligned.
                Text(empty)
                    .font(TypeScale.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                // The check stays laid out while hidden, so the chips
                // never move on hover.
                if section.attentionCount > 0 {
                    MarkAllSeenIcon {
                        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { actions.markAllSeen(section) }
                    }
                    .opacity(hover ? 1 : 0)
                }
                HStack(spacing: Grid.chipGap) {
                    ForEach(section.headerCounts) { chip in
                        let links = section.pageLinks(for: chip.kind)
                        if !links.isEmpty {
                            Button {
                                if links.count == 1 {
                                    actions.openPage(links[0])
                                } else {
                                    PageLinkMenu.show(links, kind: chip.kind, open: actions.openPage)
                                }
                            } label: {
                                HeaderCountChip(chip: chip)
                            }
                                .buttonStyle(ChipButtonStyle())
                                .hoverHelp(PanelText.headerCountPage(chip.kind))
                                .accessibilityHint(PanelText.headerCountPage(chip.kind))
                        } else {
                            HeaderCountChip(chip: chip)
                        }
                    }
                }
            }
            if let newNote = section.newNote {
                NewNoteIcon(project: section.name, state: newNote) { actions.startNote(section) }
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

/// A project header's Mark all seen: a checkmark alone at the chips' icon
/// size and weight, secondary gray from `IconButtonStyle` (primary on
/// hover), its name in the hover help and for VoiceOver, in the style's
/// button frame. `action` brings its own animation.
private struct MarkAllSeenIcon: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "checkmark")
                .font(.system(size: 8.5, weight: .semibold))
        }
        .buttonStyle(IconButtonStyle(compact: true))
        .hoverHelp(PanelText.markAllSeen)
        .accessibilityLabel(PanelText.markAllSeen)
    }
}

/// A project header's open-in-browser icon: opens the project's first
/// repository on GitHub, as Return on the header does, in the compact
/// button the check and a ping row's ✕ use. Its hover help and VoiceOver
/// label name the repository.
private struct OpenRepositoryIcon: View {
    let repository: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(IconButtonStyle(compact: true))
        .hoverHelp(PanelText.openRepository(repository))
        .accessibilityLabel(PanelText.openRepository(repository))
    }
}

/// One kind's count in a project's header: its icon and number, in the
/// accent while any of its rows needs attention (expanded or collapsed
/// alike), else secondary gray, with no background in either state, so the
/// color alone marks it. As wide as its content: the model gives no chip
/// at 0.
private struct HeaderCountChip: View {
    let chip: HeaderCount

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: Palette.symbol(chip.kind))
                .font(.system(size: 9, weight: .semibold))
            Text(String(chip.count))
                .font(TypeScale.badge)
                .contentTransition(.numericText(value: Double(chip.count)))
        }
        .lineLimit(1)
        .foregroundStyle(chip.needsAttention ? AnyShapeStyle(Palette.accent) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 4)
        .frame(height: 16)
        .animation(Motion.tint, value: chip.needsAttention)
        .animation(Motion.count, value: chip.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PanelText.headerCount(chip))
    }
}

/// A count chip's menu in a project of several repositories: under a
/// heading naming the page ("Open pull requests on GitHub"), one item per
/// repository, named without its owner, with its count as the item's
/// badge (none at 0). Native, at the pointer, so it reads like any menu;
/// choosing an item opens that repository's page.
@MainActor
private enum PageLinkMenu {
    static func show(_ links: [PageLink], kind: ItemKind, open: @escaping (PageLink) -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(.sectionHeader(title: PanelText.headerCountPage(kind)))
        for link in links {
            let item = ActionMenuItem(title: PanelText.repositoryName(link.repository)) { open(link) }
            if link.count > 0 { item.badge = NSMenuItemBadge(count: link.count) }
            item.toolTip = link.repository
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }
}

/// A menu item that runs a closure when chosen.
private final class ActionMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(choose), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("not decoded") }

    @objc private func choose() { run() }
}

/// A count chip that opens its kind's page: the chip on a faint capsule
/// while hovered, darker while pressed.
private struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        ChipButtonBody(configuration: configuration)
    }
}

private struct ChipButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hover = false

    var body: some View {
        configuration.label
            .background {
                Capsule().fill(configuration.isPressed ? Palette.pressed : hover ? Palette.hover : .clear)
            }
            .contentShape(Capsule())
            .onHover { hover = $0 }
            .animation(Motion.hover, value: hover)
    }
}

// MARK: - Rows

/// One item on one line: the attention dot, the state icon (with a pull
/// request's check dot on it), the number, the title (bold when it needs
/// attention; a run's is its workflow's name, followed by its branch as a
/// chip), the author or, in a multi-repository project, the repository,
/// and the age. What a click does, its hover help and its highlight come
/// from `itemRow(…)`.
private struct ListRow: View {
    let row: MenuRow
    let showsRepository: Bool
    /// The longest number in the row's group, which the number column
    /// keeps room for.
    let widestNumber: String
    @Environment(\.panelNow) private var now

    var body: some View {
        HStack(spacing: 0) {
            AttentionDot(isOn: row.needsAttention)
                .frame(width: Grid.dotColumn, alignment: .leading)
            stateIcon
            // A ping written before pings were numbered has none (0); the
            // column stays, so titles line up. A note's carries its prefix.
            // Digits of one width make the group's longest number the
            // widest, since a project's notes share one prefix. A note's
            // reference reads from its prefix, so it starts at the left,
            // a little apart from the icon; a plain number ends at the right.
            ZStack(alignment: numberAlignment) {
                Text(widestNumber).hidden()
                Text(PanelText.number(row))
            }
            .font(TypeScale.meta)
            .monospacedDigit()
            .foregroundStyle(.tertiary)
            .frame(minWidth: Grid.numberColumn, alignment: numberAlignment)
            .fixedSize()
            .padding(.leading, row.kind == .note ? 4 : 0)
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
                // A known agent's logo sits a little apart from its name.
                HStack(spacing: metaAgent == nil ? 3 : 5) {
                    if let agent = metaAgent {
                        AgentMarkView(agent: agent, size: Grid.agentMark)
                    } else if let symbol = metaSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Text(meta)
                        .font(TypeScale.meta)
                        .foregroundStyle(row.actionError == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Palette.red))
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

    private var numberAlignment: Alignment {
        row.kind == .note ? .leading : .trailing
    }

    private var stateIcon: some View {
        StateSymbol(row: row)
            .frame(width: Grid.iconColumn, alignment: .center)
            // The check dot rides on the state icon, like a status badge.
            .overlay(alignment: .bottomTrailing) { CheckDot(checks: row.checks).offset(x: 2, y: 2) }
    }

    /// The author, or in a project of several repositories, the repository
    /// (without its owner); a run names no author. A ping names its sender,
    /// or why its action failed, while it has (the hover card has it whole);
    /// one filed with `--project` has no repository, so it names its
    /// sender there too. A remote ping names its machine first, wherever
    /// it's listed. A note names its labels.
    private var meta: String? {
        if let error = row.actionError { return error }
        if row.machine != nil { return PanelText.pingMeta(row) }
        if showsRowRepository { return PanelText.repositoryName(row.repository) }
        if row.kind == .ping { return PanelText.sender(row) }
        if row.kind == .note { return PanelText.noteLabels(row) }
        return row.kind == .workflowRun ? nil : row.author
    }

    private var metaSymbol: String? {
        if row.actionError != nil { return "exclamationmark.triangle.fill" }
        if row.machine != nil { return "server.rack" }
        if showsRowRepository { return "shippingbox" }
        if row.kind == .note { return "tag" }
        return row.authorKind == .bot ? "cpu" : nil
    }

    /// A known agent's logo before its name, when the column names the
    /// sender.
    private var metaAgent: KnownAgent? {
        guard row.actionError == nil, !showsRowRepository else { return nil }
        return row.agent
    }

    /// Whether the meta column names this row's repository: in a project of
    /// several, when the row has one (a ping may not).
    private var showsRowRepository: Bool {
        showsRepository && !row.repository.isEmpty
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
