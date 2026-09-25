import ShipyardCore
import SwiftUI

/// The panel the menu bar icon opens: what fits the lifecycle phase, the
/// banners, one section per project, and the footer. It draws the core's
/// `Shipyard` directly (it's observable) and redraws the ages every 30 s.
struct Panel: View {
    let shipyard: Shipyard
    let actions: AppServices
    /// The tallest the list of sections gets before it scrolls.
    private static let maxSectionsHeight: CGFloat = 560
    /// The sections' own height, measured, which sizes the list around them.
    @State private var sectionsHeight: CGFloat = 0
    /// The footer's "Install agent skill…" shows the install card above it.
    @State private var showsSkillInstall = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                banners(now: context.date)
                content(now: context.date)
                if showsSkillInstall, shipyard.phase != .needsProjects {
                    SkillInstallCard(installation: actions.skillInstallation) { showsSkillInstall = false }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 10)
                }
                Divider()
                footer(now: context.date)
            }
        }
        .frame(width: 380)
        .onAppear { actions.panelOpened() }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(now: Date) -> some View {
        switch shipyard.phase {
        case .connecting:
            // Only the device flow connects this way, and 0.0.x doesn't
            // offer it (#22).
            ProgressView().padding(12)
        case .signedOut:
            ConnectView(shipyard: shipyard)
        case .needsProjects:
            // Onboarding's second step, and its offer to install the skill.
            ProjectPicker(shipyard: shipyard)
            SkillInstallCard(installation: actions.skillInstallation)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        case .ready:
            // As tall as the sections, scrolling once they pass the maximum.
            // The height is fixed from the measured sections: the
            // `MenuBarExtra` window sizes the panel from a zero-height
            // proposal, which a scroll view (or `ViewThatFits`) takes as 0,
            // leaving only the footer (#27).
            ScrollView {
                sections(now: now)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sectionsHeight = $0 }
            }
            .frame(height: min(sectionsHeight, Self.maxSectionsHeight))
        }
    }

    private func sections(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(shipyard.menu.sections) { section in
                ProjectSection(
                    section: section,
                    now: now,
                    open: { shipyard.open($0) },
                    markSeen: { shipyard.markSeen($0) },
                    markAllSeen: { shipyard.markAllSeen(project: section.name) },
                    toggleCollapsed: { shipyard.toggleCollapsed(section.name) }
                )
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Banners

    @ViewBuilder
    private func banners(now: Date) -> some View {
        if let error = shipyard.configError {
            banner(PanelText.configError(error), symbol: "exclamationmark.octagon.fill", color: Palette.red)
        }
        if shipyard.phase == .ready {
            let menu = shipyard.menu
            if let text = PanelText.refreshDelay(
                menu.refreshDelay,
                sharePercent: shipyard.configStore.lastValid.rateLimit.maxSharePercent
            ) {
                if menu.canRefreshNow {
                    banner(text, symbol: "tortoise.fill", color: Palette.amber)
                } else {
                    banner(text, symbol: "pause.circle.fill", color: Palette.red)
                }
            }
            if let error = menu.bannerFetchError {
                // The rows are kept; the footer says how old they are.
                banner(PanelText.fetchError(error), symbol: "wifi.exclamationmark", color: Palette.amber)
            }
            if actions.notificationsAreOff {
                banner(
                    PanelText.notificationsOff,
                    symbol: "bell.slash.fill",
                    color: Palette.gray,
                    action: (PanelText.openNotificationSettings, actions.openNotificationSettings)
                )
            }
        }
    }

    private func banner(_ text: String, symbol: String, color: Color, action: (String, () -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.caption)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    Button(action.0, action: action.1)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
    }

    // MARK: - Footer

    private func footer(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if shipyard.isRefreshing {
                    ProgressView().controlSize(.mini)
                    Text("Refreshing…")
                } else if let updated = PanelText.lastUpdated(shipyard.menu.lastUpdated, now: now) {
                    Text(updated)
                }
                Spacer()
                if shipyard.phase == .ready, shipyard.menu.attention.total > 0 {
                    Button("Mark all seen") { shipyard.markAllSeen() }
                        .buttonStyle(.link)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if shipyard.phase == .ready, let indicator = shipyard.menu.rateIndicator {
                rateIndicator(indicator)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Button("Refresh", action: actions.refresh)
                        .keyboardShortcut("r")
                        // The model's pause, as the banner and the menu bar icon show it.
                        .disabled(!shipyard.menu.canRefreshNow || shipyard.phase != .ready)
                    Button("Open configuration file", action: actions.openConfigurationFile)
                    Button(PanelText.installSkill) { showsSkillInstall = true }
                        // Onboarding shows the card under the picker already.
                        .disabled(shipyard.phase == .needsProjects)
                }
                HStack(spacing: 12) {
                    // Once signed in: while `start()` still asks GitHub, the
                    // token is picked but the panel says it's connecting.
                    if shipyard.phase != .signedOut, shipyard.tokenSource != nil {
                        Button("Sign out") { shipyard.signOut() }
                    }
                    Spacer()
                    Button("Quit", action: actions.quit)
                        .keyboardShortcut("q")
                }
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(10)
    }

    /// Remaining / limit and the reset time per API, amber when low and
    /// red when exhausted (the worst API's level colours the whole indicator).
    private func rateIndicator(_ indicator: RateIndicator) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            VStack(alignment: .leading, spacing: 1) {
                ForEach(indicator.apis, id: \.api) { usage in
                    Text(PanelText.rateUsage(usage))
                }
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(Palette.color(indicator.level))
    }
}
