import ShipyardCore
import SwiftUI

struct TabsLayout: View {
    let model: MenuModel
    let panel: PanelState
    let actions: LayoutActions

    @State private var highlight = RowHighlight()

    private var tab: MenuTab { model.resolved(panel.selectedTab) }
    private var forward: Bool { panel.movedForward }

    var body: some View {
        let content = model.tabContent(for: tab)
        VStack(spacing: 0) {
            TabStrip(model: model, selection: tab, select: select)
                .padding(.horizontal, Grid.gutter)
                .padding(.top, 8)
            summary(content)
            Hairline()
            list(content)
        }
        .frame(maxWidth: .infinity)
        .onChange(of: content.rowPlaces) { _, places in highlight.keep(in: places) }
        .onChange(of: model.tabs) {
            if model.resolved(panel.selectedTab) != panel.selectedTab {
                withAnimation(Motion.tab) { panel.select(.all, from: tab, in: model.tabs) }
            }
        }
    }

    private func select(_ next: MenuTab) {
        withAnimation(Motion.tab) { panel.select(next, from: tab, in: model.tabs) }
    }

    private func summary(_ content: MenuTabContent) -> some View {
        HStack(spacing: 4) {
            if content.isCaughtUp {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(ThemeColor.success)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(PanelText.tabSummary(
                attention: content.attentionCount,
                projects: content.projectCount,
                isLoaded: content.isLoaded,
                tab: tab
            ))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(content.attentionCount)))
                .foregroundStyle(ThemeColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if content.attentionCount > 0 {
                MarkSeenButton(title: PanelText.markTabSeen(tab)) {
                    withAnimation(Motion.seen) { actions.markAllSeen(section(for: tab)) }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
            }
            if let section = section(for: tab), let newNote = section.newNote {
                NewNoteIcon(project: section.title, state: newNote) { actions.startNote(section) }
            }
        }
        .font(TypeScale.meta)
        .frame(height: 22)
        .padding(.horizontal, Grid.gutter)
        .padding(.vertical, 4)
        .animation(Motion.count, value: content.attentionCount)
    }

    private func section(for tab: MenuTab) -> MenuSection? {
        switch tab {
        case .all: nil
        case .project(let name): model.sections.first { $0.name == name }
        }
    }

    private func list(_ content: MenuTabContent) -> some View {
        ScrollViewReader { proxy in
            MeasuredScrollView {
                VStack(spacing: 0) {
                    RowListTop()
                    HighlightLayer(highlight: $highlight, list: tab) {
                        ZStack(alignment: .top) {
                            TabList(content: content, actions: actions, highlight: $highlight)
                                .rowList(tab)
                                .id(tab)
                                // The old tab's rows go at once, so the two lists never draw over each other.
                                .transition(.asymmetric(
                                    insertion: .offset(x: forward ? Grid.tabSlide : -Grid.tabSlide).combined(with: .opacity),
                                    removal: .identity
                                ))
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                    RowListBottom()
                }
                .clipped()
            }
            .onHover { inside in
                if !inside { highlight.pointerLeftRows() }
            }
            .rowKeys(
                $highlight,
                places: content.rowPlaces,
                in: tab,
                scroll: proxy,
                left: { side(&$0, content, by: -1) },
                right: { side(&$0, content, by: 1) },
                dismiss: { place in
                    guard let row = content.row(at: place), row.item.ping != nil else { return false }
                    withAnimation(Motion.seen) { actions.dismiss(row) }
                    return true
                }
            ) { place, markSeenOnly in
                if let group = content.subsection(at: place) {
                    guard !markSeenOnly else { return false }
                    actions.toggleGroup(group)
                    return true
                }
                if let group = content.showMoreGroup(at: place) {
                    guard !markSeenOnly else { return false }
                    actions.toggleShowMore(group)
                    return true
                }
                guard let row = content.row(at: place) else { return false }
                withAnimation(Motion.seen) {
                    if markSeenOnly { actions.markSeen(row) } else { actions.open(row) }
                }
                return true
            }
        }
    }

    private func side(_ highlight: inout RowHighlight, _ content: MenuTabContent, by step: Int) -> RowKeyMove {
        guard highlight.place?.group != nil else { return switchTab(&highlight, by: step) }
        let change = step < 0 ? highlight.moveLeft(in: content) : highlight.moveRight(in: content)
        switch change {
        case .fold(let id), .unfold(let id):
            if let group = content.groups.first(where: { $0.id == id }) { actions.toggleGroup(group) }
        case .collapse, .expand, nil:
            break
        }
        return .moved
    }

    private func switchTab(_ highlight: inout RowHighlight, by step: Int) -> RowKeyMove {
        let next = model.tab(beside: tab, by: step)
        guard next != tab else { return .ignored }
        select(next)
        highlight.moveToFirst(in: model.tabContent(for: next).rowPlaces)
        return .newList
    }
}

private struct TabStrip: View {
    let model: MenuModel
    let selection: MenuTab
    let select: (MenuTab) -> Void

    @State private var height: CGFloat = 0
    @State private var content: CGRect = .zero
    @State private var visibleWidth: CGFloat = 0
    @State private var tabFrames: [MenuTab: CGRect] = [:]

    private var hidesLeading: Bool { content.minX < -0.5 }
    private var hidesTrailing: Bool { content.maxX > visibleWidth + 0.5 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(model.tabs, id: \.self) { tab in
                        TabPill(
                            title: model.tabTitle(tab),
                            count: model.attentionCount(for: tab),
                            isOn: tab == selection
                        ) { select(tab) }
                        .id(tab)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tab-row")) } action: {
                            tabFrames[tab] = $0
                        }
                    }
                }
                .padding(3)
                .coordinateSpace(.named("tab-row"))
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("tab-strip")) } action: {
                    height = $0.height
                    content = $0
                }
            }
            .scrollIndicators(.never)
            .frame(height: height)
            .coordinateSpace(.named("tab-strip"))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { visibleWidth = $0 }
            .mask(edgeFade)
            .background(ThemeColor.track, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onChange(of: selection) { reveal(selection, with: proxy) }
        }
    }

    private func reveal(_ tab: MenuTab, with proxy: ScrollViewProxy) {
        guard let frame = tabFrames[tab] else { return }
        let shown = frame.offsetBy(dx: content.minX, dy: 0)
        guard let anchor = TabStripScroll.anchor(revealing: shown.minX...shown.maxX, in: visibleWidth, fade: Grid.tabFade) else { return }
        withAnimation(Motion.tab) { proxy.scrollTo(tab, anchor: anchor) }
    }

    private var edgeFade: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(hidesLeading ? 0 : 1), .black], startPoint: .leading, endPoint: .trailing)
                .frame(width: Grid.tabFade)
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .black.opacity(hidesTrailing ? 0 : 1)], startPoint: .leading, endPoint: .trailing)
                .frame(width: Grid.tabFade)
        }
        .animation(.easeOut(duration: 0.15), value: hidesLeading)
        .animation(.easeOut(duration: 0.15), value: hidesTrailing)
    }
}

private struct TabPill: View {
    let title: String
    let count: Int
    let isOn: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var isTruncated = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(TypeScale.button)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Grid.maxTabTitleWidth)
                    .background {
                        Text(title)
                            .font(TypeScale.button)
                            .fixedSize()
                            .hidden()
                            .onGeometryChange(for: Bool.self) { $0.size.width > Grid.maxTabTitleWidth } action: { isTruncated = $0 }
                    }
                if count > 0 {
                    CountBadge(count: count, muted: !isOn)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .foregroundStyle(isOn ? ThemeColor.textPrimary : ThemeColor.textSecondary)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            // The pill stays under its title: it fades onto the picked tab, never sliding across the others.
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(ThemeColor.raised)
                        .shadow(color: .black.opacity(0.14), radius: 1, y: 0.5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(ThemeColor.textPrimary.opacity(0.06), lineWidth: 0.5)
                        )
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(ThemeColor.rowHover)
                }
            }
            .contentShape(Rectangle())
            .animation(Motion.tab, value: count)
        }
        .buttonStyle(PressButtonStyle())
        .hoverHelp(isTruncated ? title : nil)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .onHover { isHovered = $0 }
        .animation(Motion.hover, value: isHovered)
    }
}

private struct TabList: View {
    let content: MenuTabContent
    let actions: LayoutActions
    @Binding var highlight: RowHighlight

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(content.errors) { ErrorRow(error: $0).clearsRowHighlight($highlight) }
            ForEach(content.notes, id: \.self) { NoteRow(note: $0).clearsRowHighlight($highlight) }
            ForEach(Array(content.groups.enumerated()), id: \.element.id) { index, group in
                if group.showsHeader {
                    let place = MenuRowPlace.groupHeader(group.id, in: nil)
                    GroupHeader(group: group, place: place, highlight: $highlight, actions: actions)
                        .id(place)
                } else if index > 0 {
                    GroupDivider().padding(.vertical, 2)
                }
                ForEach(group.isFolded ? [] : group.rows) { row in
                    let place = MenuRowPlace(section: nil, row: row.id)
                    TabRow(row: row, showsRepository: content.showsRepository)
                        .itemRow(row, at: place, highlight: $highlight, showsRepository: content.showsRepository, actions: actions)
                        .id(place)
                }
                if group.hasShowMore, !group.isFolded {
                    let place = MenuRowPlace.showMore(group.id, in: nil)
                    ShowMoreRow(group: group, place: place, highlight: $highlight, actions: actions)
                        .id(place)
                }
            }
            if let empty = PanelText.emptyTab(content) {
                EmptyTab(text: empty, isLoaded: content.isLoaded)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

private struct TabRow: View {
    let row: MenuRow
    let showsRepository: Bool
    @Environment(\.panelNow) private var now

    var body: some View {
        HStack(spacing: 0) {
            AttentionDot(isOn: row.needsAttention)
                .frame(width: Grid.dotColumn, alignment: .leading)
            StateSymbol(row: row)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Grid.smallRadius + 1, style: .continuous)
                        .fill(ThemeColor.state(row.state, kind: row.kind).opacity(0.14))
                )
                .overlay(alignment: .bottomTrailing) { CheckDot(checks: row.checks).offset(x: 2, y: 2) }
                .padding(.trailing, 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(row.needsAttention ? TypeScale.bodyEmphasis : TypeScale.body)
                    .foregroundStyle(row.state.isActive || row.needsAttention ? ThemeColor.textPrimary : ThemeColor.textSeen)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 5) {
                    if row.actionError == nil, let agent = row.agent {
                        AgentMarkView(agent: agent, size: Grid.agentMark)
                    }
                    Text(PanelText.rowDetail(row, showingRepository: showsRepository))
                        .font(TypeScale.meta)
                        .foregroundStyle(row.actionError == nil ? ThemeColor.textSecondary : ThemeColor.failure)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(PanelText.age(row.age(at: now)))
                .font(TypeScale.meta)
                .foregroundStyle(row.needsAttention ? ThemeColor.textSecondary : ThemeColor.textTertiary)
                .padding(.leading, 8)
        }
        .padding(.leading, Grid.gutter - 4)
        .padding(.trailing, Grid.gutter)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}

private struct EmptyTab: View {
    let text: String
    let isLoaded: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isLoaded ? "checkmark.seal.fill" : "clock")
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isLoaded ? ThemeColor.success : ThemeColor.textTertiary)
            Text(text)
                .font(TypeScale.button)
                .foregroundStyle(ThemeColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

enum TabStripScroll {
    static func anchor(revealing tab: ClosedRange<CGFloat>, in width: CGFloat, fade: CGFloat) -> UnitPoint? {
        let tolerance: CGFloat = 0.5
        let cutLeading = tab.lowerBound < fade - tolerance
        let cutTrailing = tab.upperBound > width - fade + tolerance
        guard cutLeading || cutTrailing else { return nil }
        // `scrollTo` lines up the point at `x` of the tab with the point at `x` of the visible
        // width, so the tab's leading edge lands at `x * (width - its width)`; the scroll view
        // clamps the result to the strip's ends.
        let room = width - (tab.upperBound - tab.lowerBound)
        guard room > 2 * fade else { return .leading }
        let x = cutLeading ? fade / room : 1 - fade / room
        return UnitPoint(x: x, y: 0.5)
    }
}
