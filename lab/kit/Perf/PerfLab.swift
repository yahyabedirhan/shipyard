import LabHost
import SwiftUI

/// The stress window: the panel as the app draws it (`LabPanel`, on the
/// copied, unfixed layouts) beside a meter of what drawing it costs, and
/// the controls that load a volume or run a scenario. The meter updates
/// twice a second in its own view, so its own redraws never reach the panel.
public struct PerfLab: View {
    @State private var store: LabStore

    public init(volume: FixtureVolume, layout: MenuLayout = .tabs, tab: MenuTab = .all) {
        _store = State(initialValue: LabStore(volume: volume, layout: layout, tab: tab))
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            LabPanel(store: store)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
                .padding(16)
            Divider()
            PerfMeter(store: store)
                .frame(width: 300)
        }
        .onAppear { MainThreadMeter.shared.start() }
    }
}

/// The meter and the controls.
struct PerfMeter: View {
    let store: LabStore

    @State private var reading = MainThreadMeter.Reading(busy: 0, worstStall: 0, droppedFrames: 0)
    @State private var counts: [Probe.Point: Int] = [:]
    @State private var scenario = ""
    @State private var running = false
    @State private var menuPanel = false
    private let tick = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Panel cost").font(.headline)
            volumePicker
            VStack(alignment: .leading, spacing: 6) {
                gauge("Main thread busy", value: reading.busy, unit: "%", warn: 25, bad: 60).labID("meter-busy")
                gauge("Worst stall", value: reading.worstStall, unit: "ms", warn: 16.7, bad: 50).labID("meter-stall")
                gauge("Frames late", value: Double(reading.droppedFrames), unit: "/0.5 s", warn: 1, bad: 10)
            }
            Divider()
            Text("Work per second").font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Probe.Point.allCases, id: \.self) { point in
                    HStack {
                        Text(point.rawValue).font(.system(size: 11, design: .monospaced))
                        Spacer()
                        Text("\((counts[point] ?? 0) * 2)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle((counts[point] ?? 0) > 0 ? .primary : .tertiary)
                    }
                }
            }
            Divider()
            Text("Scenarios").font(.subheadline.weight(.semibold))
            Toggle("Running workflow runs (pulsing rows)", isOn: Binding(get: { store.runningRuns }, set: { store.setRunningRuns($0) }))
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .labID("running-runs")
            HStack {
                Button("Switch tabs ×10") { Task { await switchTabs() } }.disabled(running).labID("switch-tabs")
                Button("Reload") { reload() }.disabled(running).labID("reload")
            }
            Toggle("Also host it in a menu-bar-style panel (self-sizing, behind other windows)", isOn: Binding(
                get: { menuPanel },
                set: { on in
                    menuPanel = on
                    if on { MenuPanelHost.shared.open(store: store) } else { MenuPanelHost.shared.close() }
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .labID("menu-panel")
            HStack {
                Button("Show All") { show(.all) }.labID("show-all")
                Button("Show a project") { show(store.model.tabs.dropFirst().first ?? .all) }.labID("show-project")
            }
            if !scenario.isEmpty {
                Text(scenario)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .labID("scenario-result")
            }
            Spacer(minLength: 0)
            Text("Readings log to $TMPDIR/\(PerfLog.url.lastPathComponent)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .textSelection(.enabled)
            Text(store.lastAction.isEmpty ? "Hover, scroll and click the panel." : store.lastAction)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .onReceive(tick) { _ in
            reading = MainThreadMeter.shared.read()
            counts = Probe.drain()
            PerfLog.append([
                "volume": store.volume.name,
                "layout": store.model.layout.rawValue,
                "tab": store.model.tabTitle(store.model.resolved(store.panel.selectedTab)),
                "runningRuns": store.runningRuns,
                "menuPanel": menuPanel,
                "busy": (reading.busy * 10).rounded() / 10,
                "worstStall": (reading.worstStall * 10).rounded() / 10,
                "framesLate": reading.droppedFrames,
                "counts": Dictionary(uniqueKeysWithValues: counts.map { ($0.key.rawValue, $0.value * 2) }),
            ])
        }
    }

    private var volumePicker: some View {
        Picker("Volume", selection: Binding(get: { store.volume }, set: { store.load($0) })) {
            ForEach(FixtureVolume.all, id: \.self) { volume in
                Text("\(volume.name) · \(volume.projects) projects · ~\(volume.allTabRows) rows").tag(volume)
            }
        }
        .labelsHidden()
        .labID("volume")
    }

    private func gauge(_ title: String, value: Double, unit: String, warn: Double, bad: Double) -> some View {
        let color: Color = value >= bad ? .red : value >= warn ? .orange : .green
        return HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 12))
            Spacer()
            Text(String(format: value < 10 && unit == "ms" ? "%.1f %@" : "%.0f %@", value, unit))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    /// Steps through All and the first projects' tabs, as ← and → or a
    /// click on a pill do, timing the longest stall after each switch.
    @MainActor
    private func switchTabs() async {
        running = true
        defer { running = false }
        var stalls: [Double] = []
        let tabs = Array(store.model.tabs.prefix(6))
        for step in 0..<10 {
            let next = step.isMultiple(of: 2) ? tabs[(step / 2) % max(tabs.count - 1, 1) + 1] : .all
            MainThreadMeter.shared.beginEpisode()
            let from = store.model.resolved(store.panel.selectedTab)
            withAnimation(Motion.tab) { store.panel.select(next, from: from, in: store.model.tabs) }
            try? await Task.sleep(for: .milliseconds(450))
            stalls.append(MainThreadMeter.shared.endEpisode())
        }
        let toAll = stalls.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element)
        let toProject = stalls.enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        PerfLog.append(["scenario": "switch-tabs", "volume": store.volume.name, "toAll": toAll, "toProject": toProject])
        scenario = String(
            format: "%@, %d rows in All\nto All:     avg %.0f ms, worst %.0f ms\nto project: avg %.0f ms, worst %.0f ms",
            store.volume.name, store.model.tabContent(for: .all).groups.reduce(0) { $0 + $1.rows.count },
            toAll.reduce(0, +) / Double(max(toAll.count, 1)), toAll.max() ?? 0,
            toProject.reduce(0, +) / Double(max(toProject.count, 1)), toProject.max() ?? 0
        )
    }

    /// Selects `tab`, as a click on its pill does.
    @MainActor
    private func show(_ tab: MenuTab) {
        let from = store.model.resolved(store.panel.selectedTab)
        withAnimation(Motion.tab) { store.panel.select(tab, from: from, in: store.model.tabs) }
    }

    /// Loads the same volume again, as a refresh that brings back new rows.
    @MainActor
    private func reload() {
        MainThreadMeter.shared.beginEpisode()
        store.load(store.volume)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            let worst = MainThreadMeter.shared.endEpisode()
            PerfLog.append(["scenario": "reload", "volume": store.volume.name, "worstStall": worst])
            scenario = String(format: "%@ reload: worst stall %.0f ms", store.volume.name, worst)
        }
    }
}

/// Each meter reading and scenario result as one JSON line, so a script
/// driving the window with the lab's `interact` command can read what it cost.
enum PerfLog {
    static let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("shipyard-lab-perf.jsonl")

    static func append(_ entry: [String: Any]) {
        var entry = entry
        entry["time"] = Date().timeIntervalSince1970
        guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data + Data("\n".utf8))
            try? handle.close()
        } else {
            try? (data + Data("\n".utf8)).write(to: url)
        }
    }
}
