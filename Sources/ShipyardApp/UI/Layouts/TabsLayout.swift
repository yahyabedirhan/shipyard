import AppKit
import ShipyardCore
import SwiftUI

/// The tabs layout (`[menu] layout = "tabs"`): the menu's ready state from
/// below the header to above the footer. A pill strip with All and one tab
/// per project, each with its attention count; under it what the tab needs
/// and Mark all seen (or Mark seen); then the tab's rows grouped by kind.
///
/// More projects than fit: the strip scrolls sideways, and choosing a tab
/// scrolls it into view, with the cut-off edges faded. The selected tab is
/// kept while the menu is open and goes back to All when its project is
/// removed from the configuration.
struct TabsLayout: View {
    let model: MenuModel
    let actions: LayoutActions

    @State private var selection: MenuTab = .all
    /// Whether the latest tab change moved right, so the list slides that way.
    @State private var forward = true
    /// The row under the pointer, in the selected tab; one highlight glides
    /// between rows.
    @State private var highlight = RowHighlight()

    /// `selection`, or All while its project isn't there.
    private var tab: MenuTab { model.resolved(selection) }

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
        // A row gone from the tab (refreshed away, or another tab chosen) loses the highlight.
        .onChange(of: content.rowPlaces) { _, places in highlight.keep(in: places) }
        .onChange(of: model.tabs) {
            if model.resolved(selection) != selection {
                withAnimation(Motion.tab) { selection = .all }
            }
        }
    }

    private func select(_ next: MenuTab) {
        let tabs = model.tabs
        forward = (tabs.firstIndex(of: next) ?? 0) >= (tabs.firstIndex(of: tab) ?? 0)
        withAnimation(Motion.tab) { selection = next }
    }

    // MARK: - Under the strip

    /// What the tab needs, and Mark all seen (or Mark seen) for it.
    private func summary(_ content: MenuTabContent) -> some View {
        HStack(spacing: 4) {
            if content.attentionCount == 0 {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.green)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(PanelText.tabSummary(attention: content.attentionCount, projects: content.projectCount, tab: tab))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(content.attentionCount)))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if content.attentionCount > 0 {
                Button {
                    withAnimation(Motion.seen) { actions.markAllSeen(section(for: tab)) }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle")
                        Text(PanelText.markTabSeen(tab))
                    }
                }
                .buttonStyle(TextButtonStyle())
                .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .trailing)))
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

    // MARK: - The list

    /// As tall as the rows, scrolling past the maximum (#27). The rows
    /// slide in from the direction of travel when the tab changes.
    private func list(_ content: MenuTabContent) -> some View {
        MeasuredScrollView {
            ZStack(alignment: .top) {
                TabList(content: content, actions: actions, highlight: $highlight)
                    .id(tab)
                    .transition(.asymmetric(
                        insertion: .offset(x: forward ? Grid.tabSlide : -Grid.tabSlide).combined(with: .opacity),
                        removal: .offset(x: forward ? -Grid.tabSlide : Grid.tabSlide).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .clipped()
        }
        .onHover { inside in
            if !inside { highlight.pointerLeftRows() }
        }
    }
}

// MARK: - The tab strip

/// All and one pill per project on a track. The selected pill slides
/// between tabs; with more tabs than fit, the track scrolls sideways.
private struct TabStrip: View {
    let model: MenuModel
    let selection: MenuTab
    let select: (MenuTab) -> Void

    @Namespace private var pill
    /// The pills' height, measured: a scroll view in the menu window has
    /// no height of its own (#27).
    @State private var height: CGFloat = 0
    /// The pills' frame in the strip: its width and how far it's scrolled.
    @State private var content: CGRect = .zero
    @State private var visibleWidth: CGFloat = 0

    /// Tabs hidden past the leading edge.
    private var hidesLeading: Bool { content.minX < -0.5 }
    /// Tabs hidden past the trailing edge.
    private var hidesTrailing: Bool { content.maxX > visibleWidth + 0.5 }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(model.tabs, id: \.self) { tab in
                        TabPill(
                            title: PanelText.tabTitle(tab),
                            count: model.attentionCount(for: tab),
                            isOn: tab == selection,
                            namespace: pill
                        ) { select(tab) }
                        .id(tab)
                    }
                }
                .padding(3)
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
            .background(Palette.track, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .onChange(of: selection) {
                withAnimation(Motion.tab) { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }

    /// Fades an end past which tabs are hidden.
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

/// One tab: its title and attention badge, riding the shared pill.
private struct TabPill: View {
    let title: String
    let count: Int
    let isOn: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(TypeScale.button)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: Grid.maxTabTitleWidth)
                if count > 0 {
                    // The accent on the selected tab; muted on the others.
                    CountBadge(count: count, muted: !isOn)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .foregroundStyle(isOn ? .primary : .secondary)
            .fixedSize()
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Palette.raised)
                        .shadow(color: Palette.raisedShadow, radius: 1.5, y: 1)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.separator, lineWidth: 0.5))
                        .matchedGeometryEffect(id: "pill", in: namespace)
                } else if isHovered {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Palette.hover)
                }
            }
            .contentShape(Rectangle())
            .animation(Motion.tab, value: count)
        }
        .buttonStyle(PressButtonStyle())
        .help(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .onHover { isHovered = $0 }
        .animation(Motion.hover, value: isHovered)
    }
}

// MARK: - A tab's rows

/// The tab's error rows, then its rows grouped under small kind headers.
private struct TabList: View {
    let content: MenuTabContent
    let actions: LayoutActions
    @Binding var highlight: RowHighlight

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(content.errors) { ErrorRow(error: $0) }
            ForEach(content.groups) { group in
                KindHeader(kind: group.kind, count: group.rows.count)
                ForEach(group.rows) { row in
                    TabRow(row: row, showsRepository: content.showsRepository, actions: actions)
                        .highlightable(MenuRowPlace(section: nil, row: row.id), $highlight)
                }
            }
            if let empty = PanelText.emptyTab(content) {
                EmptyTab(text: empty, isLoaded: content.isLoaded)
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
        .rowHighlight(highlight)
    }
}

private struct KindHeader: View {
    let kind: ItemKind
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(PanelText.kindGroup(kind).uppercased())
                .font(TypeScale.eyebrow)
                .tracking(0.5)
            Text(String(count))
                .font(TypeScale.eyebrow.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.leading, Grid.gutter + Grid.dotColumn)
        .padding(.trailing, Grid.gutter)
        .padding(.top, Grid.gutter)
        .padding(.bottom, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One item: the attention dot, its state icon in a tinted square (with a
/// pull request's check dot on it), its title (bold while it needs
/// attention) over the second line, and its age on the right. Clicking
/// opens it and marks it seen; ⌥-click only marks it seen.
private struct TabRow: View {
    let row: MenuRow
    let showsRepository: Bool
    let actions: LayoutActions
    @Environment(\.panelNow) private var now

    var body: some View {
        Button(action: click) {
            HStack(spacing: 0) {
                AttentionDot(isOn: row.needsAttention)
                    .frame(width: Grid.dotColumn, alignment: .leading)
                StateSymbol(row: row)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: Grid.smallRadius + 1, style: .continuous)
                            .fill(Palette.color(row.state, kind: row.kind).opacity(0.14))
                    )
                    .overlay(alignment: .bottomTrailing) { CheckDot(checks: row.checks).offset(x: 2, y: 2) }
                    .padding(.trailing, 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .font(row.needsAttention ? TypeScale.bodyEmphasis : TypeScale.body)
                        .foregroundStyle(row.state.isActive || row.needsAttention ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(PanelText.rowDetail(row, showingRepository: showsRepository))
                        .font(TypeScale.meta)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        // A long branch or author gives way in the middle.
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(PanelText.age(row.age(at: now)))
                    .font(TypeScale.meta)
                    .foregroundStyle(row.needsAttention ? .secondary : .tertiary)
                    .padding(.leading, 8)
            }
            .padding(.leading, Grid.gutter - 4)
            .padding(.trailing, Grid.gutter)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        // ⌥-click's equivalent for the keyboard and VoiceOver.
        .accessibilityAction(named: PanelText.markRowSeen) { actions.markSeen(row) }
        .help(row.needsAttention ? "\(row.url.absoluteString)\n\(PanelText.optionClickHint)" : row.url.absoluteString)
        .animation(Motion.seen, value: row.needsAttention)
    }

    /// ⌥ held: mark seen without opening; otherwise open (which marks seen).
    private func click() {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        withAnimation(Motion.seen) {
            if flags.contains(.option) { actions.markSeen(row) } else { actions.open(row) }
        }
    }
}

/// A tab with nothing to list: nothing open, or not loaded yet.
private struct EmptyTab: View {
    let text: String
    let isLoaded: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isLoaded ? "checkmark.seal.fill" : "clock")
                .font(.system(size: 26))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isLoaded ? AnyShapeStyle(Palette.green) : AnyShapeStyle(.tertiary))
            Text(text)
                .font(TypeScale.button)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}
