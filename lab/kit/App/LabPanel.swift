import LabHost
import AppKit
import Observation
import SwiftUI

/// The lab's stand-in for the app's orchestrator (`Shipyard`) and its
/// services: the menu model from fixtures, the panel's tab, and the
/// layout's actions as mock callbacks that change only this model, as a
/// click in the app would once its refresh came back.
@MainActor
@Observable
final class LabStore {
    var model: MenuModel
    let panel: PanelState
    var volume: FixtureVolume
    /// Whether some workflow runs are still running (their rows pulse).
    var runningRuns = true
    /// What the last action did, for the lab window's status line.
    var lastAction = ""

    init(volume: FixtureVolume = .maintainer, layout: MenuLayout = .tabs, tab: MenuTab = .all) {
        self.volume = volume
        model = Fixtures.model(volume, layout: layout)
        panel = PanelState(selectedTab: tab)
    }

    /// Loads `volume` again, keeping the layout: a refresh that brought
    /// back that many items.
    func load(_ volume: FixtureVolume) {
        self.volume = volume
        model = Fixtures.model(volume, layout: model.layout, runningRuns: runningRuns)
    }

    /// Finishes every running run, or brings them back.
    func setRunningRuns(_ on: Bool) {
        runningRuns = on
        model = Fixtures.model(volume, layout: model.layout, runningRuns: on)
    }

    func switchLayout() {
        model = Fixtures.model(volume, layout: model.layout.next, runningRuns: runningRuns)
    }

    var actions: LayoutActions {
        LayoutActions(
            open: { [weak self] row in self?.markSeen([row.id], "opened \(row.title)") },
            markSeen: { [weak self] row in self?.markSeen([row.id], "marked \(row.title) seen") },
            dismiss: { [weak self] row in self?.remove(row.id) },
            markAllSeen: { [weak self] section in
                guard let self else { return }
                let rows = section?.rows ?? model.sections.flatMap(\.rows)
                markSeen(Set(rows.map(\.id)), "marked \(section?.title ?? "everything") seen")
            },
            toggleCollapsed: { [weak self] section in
                guard let self, let index = model.sections.firstIndex(where: { $0.name == section.name }) else { return }
                model.sections[index].isCollapsed.toggle()
            },
            toggleGroup: { [weak self] group in self?.toggleFold(group.id) },
            toggleShowMore: { [weak self] _ in self?.lastAction = "show more" },
            openRepository: { [weak self] section in self?.lastAction = "open \(section.title) on GitHub" },
            openPage: { [weak self] link in self?.lastAction = "open \(link.url.absoluteString)" },
            startNote: { [weak self] section in self?.lastAction = "new note in \(section.title)" }
        )
    }

    private func markSeen(_ ids: Set<String>, _ what: String) {
        lastAction = what
        for s in model.sections.indices {
            for g in model.sections[s].groups.indices {
                for r in model.sections[s].groups[g].rows.indices where ids.contains(model.sections[s].groups[g].rows[r].id) {
                    model.sections[s].groups[g].rows[r].needsAttention = false
                    model.sections[s].groups[g].rows[r].attentionReasons = []
                }
                model.sections[s].groups[g].attentionCount = model.sections[s].groups[g].rows.filter(\.needsAttention).count
            }
            model.sections[s].attentionCount = model.sections[s].rows.filter(\.needsAttention).count
        }
        recount()
    }

    private func remove(_ id: String) {
        lastAction = "dismissed a ping"
        for s in model.sections.indices {
            for g in model.sections[s].groups.indices {
                model.sections[s].groups[g].rows.removeAll { $0.id == id }
            }
        }
        recount()
    }

    private func toggleFold(_ id: GroupID) {
        if model.foldedGroups.contains(id) { model.foldedGroups.remove(id) } else { model.foldedGroups.insert(id) }
        for s in model.sections.indices {
            for g in model.sections[s].groups.indices where model.sections[s].groups[g].id == id {
                model.sections[s].groups[g].isFolded = model.foldedGroups.contains(id)
            }
        }
    }

    private func recount() {
        var counts = AttentionCounts()
        var counted = Set<String>()
        for row in model.sections.flatMap(\.rows) where row.needsAttention && counted.insert(row.id).inserted {
            counts.add(row.kind)
        }
        model.attention = counts
    }
}

/// The panel the menu bar icon opens, as `Panel.swift` draws it once
/// ready: the header, the configured layout and the footer, under one
/// 30-second `TimelineView` that hands every row its `panelNow`, with the
/// hover help drawn once over all of it. The account is a fixed one; the
/// settings menu and banners are left out (they're the frame's, not the
/// layouts').
struct LabPanel: View {
    let store: LabStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                header
                Hairline()
                layout
                Hairline()
                footer(now: context.date)
            }
            .environment(\.panelNow, context.date)
            .hoverHelpHost()
        }
        .frame(width: Grid.panelWidth)
        .background(Palette.panel)
    }

    private var header: some View {
        let attention = store.model.attention.total
        return HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
                    .frame(width: 20, height: 20)
                Text(PanelText.title(for: Viewer(login: "shipyard-lab")))
                    .font(TypeScale.title)
                    .lineLimit(1)
            }
            if let summary = PanelText.attentionSummary(attention) {
                Text(summary)
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(attention)))
                    .transition(.opacity)
            }
            Spacer()
            Button(action: store.switchLayout) {
                Image(systemName: store.model.layout == .tabs ? "rectangle.split.3x1" : "list.bullet")
                    .frame(width: 16, height: 16)
                    .contentTransition(.symbolEffect(.replace, options: .speed(1.5)))
            }
            .buttonStyle(IconButtonStyle())
            .hoverHelp(PanelText.layoutButton(store.model.layout))
            .labID("layout")
            Button {} label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(IconButtonStyle())
                .hoverHelp(PanelText.refreshHelp)
            Image(systemName: "gearshape")
                .frame(width: 24, height: 22)
                .hoverHelp(PanelText.settings)
        }
        .padding(.leading, Grid.gutter)
        .padding(.trailing, 8)
        .frame(height: Grid.titleBarHeight)
        .animation(Motion.count, value: attention)
    }

    @ViewBuilder
    private var layout: some View {
        switch store.model.layout {
        case .list:
            ListLayout(model: store.model, actions: store.actions)
        case .tabs:
            TabsLayout(model: store.model, panel: store.panel, actions: store.actions)
        }
    }

    private func footer(now: Date) -> some View {
        HStack(spacing: 6) {
            if let updated = PanelText.lastUpdated(store.model.lastUpdated, now: now) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text(updated)
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.model.attention.total > 0 {
                Button(PanelText.markAllSeen) {
                    withAnimation(.spring(duration: 0.45, bounce: 0.15)) { store.actions.markAllSeen(nil) }
                }
                .buttonStyle(TextButtonStyle())
            }
            Button {} label: {
                HStack(spacing: 4) {
                    Text("Quit")
                    Text("⌘Q").foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(TextButtonStyle(tint: .primary, font: TypeScale.caption))
        }
        .padding(.leading, Grid.gutter)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Palette.chrome)
    }
}
