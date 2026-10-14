import ShipyardConfig
import ShipyardControl
import ShipyardCore
import SwiftUI

struct Panel: View {
    let shipyard: Shipyard
    let actions: AppServices
    var isSnapshot = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                header
                banners
                Hairline()
                content
                Hairline()
                footer(now: context.date)
            }
            .environment(\.panelNow, context.date)
            .hoverHelpHost()
        }
        .frame(width: Grid.panelWidth)
        .onAppear { if !isSnapshot { actions.panelOpened() } }
        .onDisappear { if !isSnapshot { actions.panelClosed() } }
        .onChange(of: actions.skillInstallation.state) { actions.skillDetector.check() }
    }

    private var header: some View {
        let attention = shipyard.phase == .ready ? shipyard.menu.attention.total : 0
        return HStack(spacing: 8) {
            if let viewer = shipyard.viewer {
                AccountButton(viewer: viewer, avatars: actions.avatars, action: actions.openProfile)
            } else {
                Text(PanelText.title(for: nil)).font(TypeScale.title)
            }
            if let summary = PanelText.attentionSummary(attention) {
                Text(summary)
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: Double(attention)))
                    .transition(.opacity)
            }
            Spacer()
            if shipyard.phase == .ready {
                let layout = shipyard.menu.layout
                Button(action: actions.switchToNextLayout) {
                    Image(systemName: layout.symbol)
                        .frame(width: 16, height: 16)
                        .contentTransition(.symbolEffect(.replace, options: .speed(1.5)))
                }
                .buttonStyle(IconButtonStyle())
                .hoverHelp(PanelText.layoutButton(layout))
                .accessibilityLabel(PanelText.layoutButton(layout))
            }
            Button(action: actions.refresh) {
                Image(systemName: "arrow.clockwise")
                    .opacity(shipyard.isRefreshing ? 0 : 1)
                    .overlay {
                        if shipyard.isRefreshing {
                            ProgressView().controlSize(.mini)
                        }
                    }
            }
            .buttonStyle(IconButtonStyle())
            .keyboardShortcut("r")
            .disabled(!shipyard.menu.canRefreshNow || shipyard.phase != .ready)
            .hoverHelp(PanelText.refreshHelp)
            .accessibilityLabel("Refresh")
            Menu {
                settingsItems
            } label: {
                Image(systemName: "gearshape")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 24, height: 22)
            .hoverHelp(PanelText.settings)
            .accessibilityLabel(PanelText.settings)
        }
        .padding(.leading, Grid.gutter)
        .padding(.trailing, 8)
        .frame(height: Grid.titleBarHeight)
        .animation(Motion.count, value: attention)
    }

    @ViewBuilder
    private var settingsItems: some View {
        let canSignOut = shipyard.phase != .signedOut && shipyard.tokenSource != nil
        let status = SetupStatus(
            cli: actions.cliLink.state,
            github: shipyard.gitHubConnection != nil,
            notion: shipyard.notionIsSetUp,
            skill: actions.skillDetector.isInstalled
        )
        ForEach(PanelText.settingsMenu(status, canSignOut: canSignOut), id: \.title) { item in
            switch item.action {
            case .openConfiguration:
                Button(item.title, action: actions.openConfigurationFile)
            case .open(let part):
                Button(item.title) { actions.panelState.openView = part }
                    .badge(item.isChecked ? Text(PanelText.setUpMark) : nil)
            case .signOut:
                Divider()
                Button(item.title) { shipyard.signOut() }
            }
        }
    }

    private var banners: some View {
        TimelineView(.explicit(shipyard.bannerSnoozeEnds)) { context in
            bannerStack(shipyard.banners(at: Self.bannerDate(context.date, now: Date())))
        }
    }

    /// The time the banners are drawn for: the entry's date when it fires a
    /// moment early, so its snooze counts as ended; now otherwise. A draw
    /// before any entry is due gets the schedule's first date from SwiftUI,
    /// a snooze that ends in an hour, which would show the banner just
    /// dismissed.
    static func bannerDate(_ entry: Date, now: Date) -> Date {
        entry > now && entry.timeIntervalSince(now) <= 1 ? entry : now
    }

    private func bannerStack(_ banners: [PanelBanner]) -> some View {
        let leaseEnds = actions.leaseIndicator.shownEnd(at: Date())
        let hidden = actions.leaseIndicator.isHiddenForCapture
        let items = banners.filter { banner in
            switch banner.kind {
            case .lease: leaseEnds != nil
            case .stoppedHolder: !hidden
            default: true
            }
        }
        return VStack(spacing: 6) {
            ForEach(items) { item in
                bannerView(item, leaseEnds: leaseEnds)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, items.isEmpty ? 0 : 8)
        .animation(Motion.banner, value: items.map(\.id))
    }

    @ViewBuilder
    private func bannerView(_ item: PanelBanner, leaseEnds: Date?) -> some View {
        let dismiss = dismiss(of: item)
        switch item.kind {
        case .lease:
            if let leaseEnds { leaseBanner(ends: leaseEnds, dismiss: dismiss) }
        case .stoppedHolder(let key):
            Banner(
                symbol: item.symbol,
                text: item.text,
                tint: item.tint,
                action: (LeaseBanner.allow, { actions.allowLeaseHolder(key) }),
                trailing: true,
                dismiss: dismiss
            )
        default:
            Banner(
                symbol: item.symbol,
                text: item.text,
                tint: item.tint,
                action: action(of: item),
                dismiss: dismiss
            )
        }
    }

    private func action(of banner: PanelBanner) -> (title: String, run: () -> Void)? {
        if let part = banner.opens {
            let panelState = actions.panelState
            return (PanelText.openBannerView, { panelState.openView = part })
        }
        guard banner.kind == .notificationsOff else { return nil }
        return (PanelText.openNotificationSettings, actions.openNotificationSettings)
    }

    private func dismiss(of banner: PanelBanner) -> () -> Void {
        let shipyard = shipyard
        return { shipyard.dismissBanner(banner.id) }
    }

    private func leaseBanner(ends: Date, dismiss: @escaping () -> Void) -> some View {
        TimelineView(.periodic(from: ends.addingTimeInterval(-ControlLease.cap), by: 1)) { context in
            if let lease = actions.leaseIndicator.shown(at: context.date) {
                LeaseBannerView(lease: lease, stop: actions.stopLease, dismiss: dismiss)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let part = actions.panelState.openView {
            StatusView(part: part, actions: actions) { actions.panelState.openView = nil }
        } else {
            phaseContent
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch shipyard.phase {
        case .signedOut, .connecting:
            ConnectView(shipyard: shipyard)
        case .needsProjects:
            if shipyard.presets.isEmpty {
                ProjectPicker(shipyard: shipyard)
            } else {
                PresetPicker(shipyard: shipyard)
            }
            SkillInstallCard(installation: actions.skillInstallation)
                .padding(.horizontal, Grid.gutter)
                .padding(.bottom, 8)
            CLILinkCard(link: actions.cliLink)
                .padding(.horizontal, Grid.gutter)
                .padding(.bottom, Grid.gutter)
        case .ready:
            layout
        }
    }

    @ViewBuilder
    private var layout: some View {
        switch shipyard.menu.layout {
        case .list:
            ListLayout(model: shipyard.menu, actions: actions.layoutActions)
        case .tabs:
            TabsLayout(model: shipyard.menu, panel: actions.panelState, actions: actions.layoutActions)
        }
    }

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

private struct AccountButton: View {
    let viewer: Viewer
    let avatars: AvatarCache
    let action: () -> Void
    @State private var avatar: NSImage?
    @State private var hover = false

    private static let avatarSize: CGFloat = 20

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                avatarView
                Text(PanelText.title(for: viewer))
                    .font(TypeScale.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 4)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hover ? Palette.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressButtonStyle())
        .padding(.leading, -4)
        .onHover { inside in
            guard inside != hover else { return }
            hover = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            if hover { NSCursor.pop() }
            hover = false
        }
        .animation(Motion.hover, value: hover)
        .hoverHelp(PanelText.profileHelp(viewer), leadingInset: 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PanelText.profileAccessibilityLabel(viewer))
        .accessibilityAddTraits(.isLink)
        .task(id: viewer.avatarURL) { await loadAvatar() }
    }

    @ViewBuilder
    private var avatarView: some View {
        Group {
            if let avatar {
                Image(nsImage: avatar)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    )
            }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        .accessibilityHidden(true)
    }

    private func loadAvatar() async {
        guard let url = viewer.avatarURL else {
            avatar = nil
            return
        }
        avatar = await avatars.image(for: url).flatMap(NSImage.init(data:))
    }
}

extension PanelBanner {
    fileprivate var symbol: String {
        switch kind {
        case .lease: "terminal.fill"
        case .stoppedHolder: "hand.raised.fill"
        case .configError: "exclamationmark.octagon.fill"
        case .configWarnings: "info.circle.fill"
        case .delay: "tortoise.fill"
        case .paused: "pause.circle.fill"
        case .fetch: "wifi.exclamationmark"
        case .machine: "server.rack"
        case .notes: "note.text"
        case .notificationsOff: "bell.slash.fill"
        }
    }

    fileprivate var tint: Color {
        switch kind {
        case .configError, .paused: Palette.red
        case .delay, .fetch: Palette.amber
        case .lease: Palette.lease
        case .stoppedHolder, .configWarnings, .machine, .notes, .notificationsOff: Palette.gray
        }
    }
}

extension MenuLayout {
    fileprivate var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .tabs: "rectangle.split.3x1"
        }
    }
}

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
