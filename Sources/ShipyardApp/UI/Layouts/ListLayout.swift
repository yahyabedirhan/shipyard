import AppKit
import ShipyardConfig
import ShipyardCore
import SwiftUI

struct ListLayout: View {
    let model: MenuModel
    let actions: LayoutActions
    @State private var highlight = RowHighlight()
    @Environment(\.panelScale) private var scale

    var body: some View {
        ScrollViewReader { proxy in
            MeasuredScrollView {
                VStack(spacing: 0) {
                    RowListTop()
                    HighlightLayer(highlight: $highlight) {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(model.sections) { section in
                                Section {
                                    if !section.isCollapsed {
                                        lines(section)
                                    }
                                } header: {
                                    let place = MenuRowPlace.header(section.name)
                                    HighlightedSectionHeader(section: section, place: place, highlight: $highlight, actions: actions)
                                        .highlightable(place, $highlight, drawsOwnHighlight: true)
                                        .id(place)
                                }
                            }
                        }
                    }
                    RowListBottom()
                }
            }
            .onHover { inside in
                if !inside { highlight.pointerLeftRows() }
            }
            .rowKeys(
                $highlight,
                places: model.listRowPlaces,
                pinnedHeader: scale.list.headerHeight,
                scroll: proxy,
                left: { fold($0.moveLeft(in: model)) },
                right: { fold($0.moveRight(in: model)) },
                dismiss: dismiss,
                activate: activate
            )
        }
        .onChange(of: model.listRowPlaces) { _, places in highlight.keep(in: places) }
        .environment(\.panelStyle, .list)
    }

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

    private func dismiss(_ place: MenuRowPlace) -> Bool {
        guard case .item(let row) = model.listTarget(at: place), row.item.ping != nil else { return false }
        withAnimation(Motion.seen) { actions.dismiss(row) }
        return true
    }

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
            let widestNumber = group.rows.map(PanelText.number).max { $0.count < $1.count } ?? ""
            ForEach(Array((group.isFolded ? [] : group.rows).enumerated()), id: \.element.id) { position, row in
                let place = MenuRowPlace(section: section.name, row: row.id)
                VStack(spacing: 0) {
                    if index > 0, position == 0, !group.showsHeader {
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

    private static let lineTransition = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: -6)).animation(Motion.collapse),
        removal: .identity
    )
}

private struct HighlightedSectionHeader: View {
    let section: MenuSection
    let place: MenuRowPlace
    @Binding var highlight: RowHighlight
    let actions: LayoutActions

    var body: some View {
        ListSectionHeader(section: section, isHighlighted: highlight.isHighlighted(place), actions: actions)
    }
}

private struct ListSectionHeader: View {
    let section: MenuSection
    let isHighlighted: Bool
    let actions: LayoutActions
    @State private var hover = false
    @Environment(\.panelScale) private var scale

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Button {
                    actions.toggleCollapsed(section)
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityValue(section.isCollapsed ? "Collapsed" : "Expanded")
                .accessibilityHint(PanelText.sectionFoldHelp(section.title, isCollapsed: section.isCollapsed))
                HStack(spacing: 6) {
                    Group {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(ThemeColor.textTertiary)
                            .animation(Motion.collapse) { $0.rotationEffect(.degrees(section.isCollapsed ? 0 : 90)) }
                            .frame(width: ListGrid.dotColumn)
                        Image(systemName: "folder")
                            .font(.system(size: 10.5))
                            .foregroundStyle(ThemeColor.textTertiary)
                        Text(section.title)
                            .font(scale.listType.section)
                            .foregroundStyle(ThemeColor.textPrimary)
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
                Text(empty)
                    .font(scale.listType.caption)
                    .foregroundStyle(ThemeColor.textTertiary)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                if section.attentionCount > 0 {
                    MarkAllSeenIcon {
                        withAnimation(.spring(duration: 0.45, bounce: 0.15)) { actions.markAllSeen(section) }
                    }
                    .opacity(hover ? 1 : 0)
                }
                HStack(spacing: ListGrid.chipGap) {
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
                NewNoteIcon(project: section.title, state: newNote) { actions.startNote(section) }
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: scale.list.headerHeight)
        .background {
            ZStack {
                Rectangle().fill(ThemeColor.header)
                if isHighlighted {
                    Rectangle()
                        .fill(ThemeColor.rowHover)
                        .transition(.opacity)
                }
            }
            .animation(Motion.hover, value: isHighlighted)
        }
        .overlay(alignment: .bottom) { Hairline() }
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
        .animation(Motion.count, value: section.attentionCount)
    }
}

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

private struct HeaderCountChip: View {
    let chip: HeaderCount
    @Environment(\.panelScale) private var scale

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: ItemSymbol.name(chip.kind))
                .font(.system(size: 8.5, weight: .semibold))
            Text(String(chip.count))
                .font(scale.listType.badge)
                .contentTransition(.numericText(value: Double(chip.count)))
        }
        .lineLimit(1)
        .foregroundStyle(chip.needsAttention ? ThemeColor.accent : ThemeColor.textSecondary)
        .padding(.horizontal, 3)
        .frame(height: 14)
        .animation(Motion.tint, value: chip.needsAttention)
        .animation(Motion.count, value: chip.count)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PanelText.headerCount(chip))
    }
}

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
                Capsule().fill(configuration.isPressed ? ThemeColor.rowPressed : ThemeColor.rowHover.opacity(hover ? 1 : 0))
            }
            .contentShape(Capsule())
            .onHover { hover = $0 }
            .animation(Motion.hover, value: hover)
    }
}

private struct ListRow: View {
    let row: MenuRow
    let showsRepository: Bool
    let widestNumber: String
    @Environment(\.panelNow) private var now
    @Environment(\.panelScale) private var scale

    var body: some View {
        HStack(spacing: 0) {
            AttentionDot(isOn: row.needsAttention)
                .frame(width: ListGrid.dotColumn, alignment: .leading)
            stateIcon
            ZStack(alignment: numberAlignment) {
                Text(widestNumber).hidden()
                Text(PanelText.number(row))
            }
            .font(scale.listType.meta)
            .monospacedDigit()
            .foregroundStyle(ThemeColor.textTertiary)
            .frame(minWidth: ListGrid.numberColumn, alignment: numberAlignment)
            .fixedSize()
            .padding(.leading, row.kind == .note ? 4 : 0)
            .padding(.trailing, 8)
            Text(row.title)
                .font(row.needsAttention ? scale.listType.bodyEmphasis : scale.listType.body)
                .foregroundStyle(row.state.isActive ? ThemeColor.textPrimary : ThemeColor.textSeen)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if let branch = row.branch {
                BranchChip(branch: branch).padding(.leading, 6)
            }
            Spacer(minLength: 8)
            if let meta {
                HStack(spacing: metaAgent == nil ? 3 : 5) {
                    if let agent = metaAgent {
                        AgentMarkView(agent: agent, size: ListGrid.agentMark)
                    } else if let symbol = metaSymbol {
                        Image(systemName: symbol)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(ThemeColor.textTertiary)
                    }
                    Text(meta)
                        .font(scale.listType.meta)
                        .foregroundStyle(row.actionError == nil ? ThemeColor.textTertiary : ThemeColor.failed)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(width: ListGrid.metaColumn, alignment: .leading)
                .padding(.leading, 6)
            }
            Text(PanelText.age(row.age(at: now)))
                .font(scale.listType.meta)
                .foregroundStyle(ThemeColor.textSecondary)
                .frame(width: ListGrid.ageColumn, alignment: .trailing)
        }
        .padding(.leading, scale.list.gutter - 4)
        .padding(.trailing, scale.list.gutter)
        .frame(height: scale.list.rowHeight)
        .contentShape(Rectangle())
    }

    private var numberAlignment: Alignment {
        row.kind == .note ? .leading : .trailing
    }

    private var stateIcon: some View {
        StateSymbol(row: row)
            .frame(width: ListGrid.iconColumn, alignment: .center)
            .overlay(alignment: .bottomTrailing) { CheckDot(checks: row.checks).offset(x: 2, y: 2) }
    }

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

    private var metaAgent: KnownAgent? {
        guard row.actionError == nil, !showsRowRepository else { return nil }
        return row.agent
    }

    private var showsRowRepository: Bool {
        showsRepository && !row.repository.isEmpty
    }
}

private struct BranchChip: View {
    let branch: String
    @Environment(\.panelScale) private var scale

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.branch").font(.system(size: 8.5, weight: .semibold))
            Text(branch)
                .font(scale.listType.branch)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(ThemeColor.textSecondary)
        .padding(.horizontal, 4)
        .frame(height: 14)
        .background(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(ThemeColor.field))
    }
}

private struct SkeletonRow: View {
    let width: CGFloat
    @State private var pulse = false
    @Environment(\.panelScale) private var scale

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(ThemeColor.textPrimary.opacity(0.08)).frame(width: 12, height: 12)
            RoundedRectangle(cornerRadius: 3).fill(ThemeColor.textPrimary.opacity(0.08)).frame(width: width, height: 9)
            Spacer()
            RoundedRectangle(cornerRadius: 3).fill(ThemeColor.textPrimary.opacity(0.06)).frame(width: 44, height: 9)
        }
        .padding(.leading, scale.list.gutter + ListGrid.dotColumn)
        .padding(.trailing, scale.list.gutter)
        .frame(height: scale.list.rowHeight)
        .opacity(pulse ? 0.5 : 1)
        .onAppear { withAnimation(.easeInOut(duration: 0.9).repeatForever()) { pulse = true } }
        .accessibilityHidden(true)
    }
}
