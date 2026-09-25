import ShipyardCore
import SwiftUI

/// The panel the menu bar icon opens: the frame every layout shares (the
/// header, the banners and the footer) around what fits the lifecycle
/// phase; once ready, the layout `[menu] layout` picks. It draws the core's
/// `Shipyard` directly (it's observable) and redraws the ages every 30 s.
struct Panel: View {
    let shipyard: Shipyard
    let actions: AppServices
    /// The header's "Install agent skill…" shows the install card above the footer.
    @State private var showsSkillInstall = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                header
                banners
                Hairline()
                content
                if showsSkillInstall, shipyard.phase != .needsProjects {
                    SkillInstallCard(installation: actions.skillInstallation) { showsSkillInstall = false }
                        .padding(Grid.gutter - 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Hairline()
                footer(now: context.date)
            }
            .environment(\.panelNow, context.date)
        }
        .frame(width: Grid.panelWidth)
        .animation(Motion.banner, value: showsSkillInstall)
        .onAppear { actions.panelOpened() }
    }

    // MARK: - Header

    private var header: some View {
        let attention = shipyard.phase == .ready ? shipyard.menu.attention.total : 0
        return HStack(spacing: 8) {
            Text(PanelText.title).font(TypeScale.title)
            if let summary = PanelText.attentionSummary(attention) {
                Text(summary)
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(attention)))
                    .transition(.opacity)
            }
            Spacer()
            Button(action: actions.refresh) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(shipyard.isRefreshing ? 360 : 0))
                    .animation(
                        shipyard.isRefreshing
                            ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                            : .spring(duration: 0.3),
                        value: shipyard.isRefreshing
                    )
            }
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut("r")
            // The model's pause, as the banner and the menu bar icon show it.
            .disabled(!shipyard.menu.canRefreshNow || shipyard.phase != .ready)
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
            Menu {
                Button("Open configuration file", action: actions.openConfigurationFile)
                Button(PanelText.installSkill) { showsSkillInstall = true }
                    // Onboarding shows the card under the picker already.
                    .disabled(shipyard.phase == .needsProjects)
                // Once signed in: while `start()` still asks GitHub, the
                // token is picked but the panel says it's connecting.
                if shipyard.phase != .signedOut, shipyard.tokenSource != nil {
                    Divider()
                    Button("Sign out") { shipyard.signOut() }
                }
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 24, height: 22)
            .help("Settings")
        }
        .padding(.leading, Grid.gutter)
        .padding(.trailing, 8)
        .frame(height: Grid.titleBarHeight)
        .animation(Motion.count, value: attention)
    }

    // MARK: - Banners

    private struct BannerItem: Identifiable {
        let id: String
        let symbol: String
        let text: String
        let tint: Color
        var action: (title: String, run: () -> Void)?
    }

    /// Configuration error, configuration warnings (gray), refresh delay (stretched or backed off: amber;
    /// paused: red), fetch error, notifications off: each slides in and out.
    private var bannerItems: [BannerItem] {
        var items: [BannerItem] = []
        if let error = shipyard.configError {
            items.append(BannerItem(id: "config", symbol: "exclamationmark.octagon.fill", text: PanelText.configError(error), tint: Palette.red))
        }
        if let text = PanelText.configWarnings(shipyard.configWarnings) {
            items.append(BannerItem(id: "config-warnings", symbol: "info.circle.fill", text: text, tint: Palette.gray))
        }
        guard shipyard.phase == .ready else { return items }
        let menu = shipyard.menu
        if let text = PanelText.refreshDelay(
            menu.refreshDelay,
            sharePercent: shipyard.configStore.lastValid.rateLimit.maxSharePercent
        ) {
            items.append(menu.canRefreshNow
                ? BannerItem(id: "delay", symbol: "tortoise.fill", text: text, tint: Palette.amber)
                : BannerItem(id: "paused", symbol: "pause.circle.fill", text: text, tint: Palette.red))
        }
        if let error = menu.bannerFetchError {
            // The rows are kept; the footer says how old they are.
            items.append(BannerItem(id: "fetch", symbol: "wifi.exclamationmark", text: PanelText.fetchError(error), tint: Palette.amber))
        }
        if actions.notificationsAreOff {
            items.append(BannerItem(
                id: "notifications",
                symbol: "bell.slash.fill",
                text: PanelText.notificationsOff,
                tint: Palette.gray,
                action: (PanelText.openNotificationSettings, actions.openNotificationSettings)
            ))
        }
        return items
    }

    private var banners: some View {
        let items = bannerItems
        return VStack(spacing: 6) {
            ForEach(items) { item in
                Banner(symbol: item.symbol, text: item.text, tint: item.tint, action: item.action)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, items.isEmpty ? 0 : 8)
        .animation(Motion.banner, value: items.map(\.id))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch shipyard.phase {
        case .connecting:
            // Only the device flow connects this way, and 0.0.x doesn't
            // offer it (#22).
            ProgressView()
                .controlSize(.small)
                .padding(Grid.gutter)
                .frame(maxWidth: .infinity)
        case .signedOut:
            ConnectView(shipyard: shipyard)
        case .needsProjects:
            // Onboarding's second step, and its offer to install the skill.
            ProjectPicker(shipyard: shipyard)
            SkillInstallCard(installation: actions.skillInstallation)
                .padding(.horizontal, Grid.gutter)
                .padding(.bottom, Grid.gutter)
        case .ready:
            layout
        }
    }

    /// The configured layout, drawing the menu model. Each layout measures
    /// its own scrolling area (#27).
    @ViewBuilder
    private var layout: some View {
        switch shipyard.menu.layout {
        case .list:
            ListLayout(model: shipyard.menu, actions: actions.layoutActions)
        case .tabs:
            TabsLayout(model: shipyard.menu, actions: actions.layoutActions)
        }
    }

    // MARK: - Footer

    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if shipyard.isRefreshing {
                    ProgressView().controlSize(.mini)
                    Text("Refreshing…")
                        .font(TypeScale.caption)
                        .foregroundStyle(.secondary)
                } else if let updated = PanelText.lastUpdated(shipyard.menu.lastUpdated, now: now) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(updated)
                        .font(TypeScale.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if shipyard.phase == .ready, shipyard.menu.attention.total > 0 {
                    Button(PanelText.markAllSeen) {
                        withAnimation(.spring(duration: 0.45, bounce: 0.15)) {
                            actions.layoutActions.markAllSeen(nil)
                        }
                    }
                    .buttonStyle(TextButtonStyle())
                }
                Button(action: actions.quit) {
                    HStack(spacing: 4) {
                        Text("Quit")
                        Text("⌘Q").foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(TextButtonStyle(tint: .primary, font: TypeScale.caption))
                .keyboardShortcut("q")
            }
            if shipyard.phase == .ready, let indicator = shipyard.menu.rateIndicator {
                ForEach(indicator.apis, id: \.api) { usage in
                    RateLine(usage: usage)
                }
            }
        }
        .padding(.leading, Grid.gutter)
        .padding(.trailing, Grid.gutter - 6)
        .padding(.vertical, 8)
        .background(Palette.chrome)
        .animation(.spring(duration: 0.5), value: shipyard.menu.rateIndicator)
    }
}

/// One API's rate limit: a bar of what's left, remaining / limit and the
/// reset time; amber when low, red when exhausted.
private struct RateLine: View {
    let usage: RateUsage

    private var fraction: Double {
        Double(max(0, usage.remaining)) / Double(max(1, usage.limit))
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule().fill(Palette.bar(usage.level)).frame(width: 26 * fraction)
            }
            .frame(width: 26, height: 4)
            .accessibilityHidden(true)
            Text(PanelText.rateUsage(usage))
                .font(TypeScale.caption)
                .foregroundStyle(usage.level == .normal ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Palette.color(usage.level)))
        }
    }
}
