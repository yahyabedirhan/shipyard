import ShipyardConfig
import ShipyardControl
import ShipyardCore
import SwiftUI

/// The panel the menu bar icon opens: the frame every layout shares (the
/// header, the banners and the footer) around what fits the lifecycle
/// phase; once ready, the layout `[menu] layout` picks. It draws the core's
/// `Shipyard` directly (it's observable) and redraws the ages every 30 s.
struct Panel: View {
    let shipyard: Shipyard
    let actions: AppServices
    /// A panel drawn only for a screenshot's fallback, never on screen: its
    /// appearing and disappearing aren't the panel opening and closing.
    var isSnapshot = false
    /// The header's "Install agent skill…" shows the install card above the footer.
    @State private var showsSkillInstall = false
    /// The header's "Link shipyard CLI…" shows the link card above the footer.
    @State private var showsCLILink = false
    /// The header's "Connect Notion…" shows the Notion card above the footer.
    @State private var showsNotionConnect = false

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
                if showsCLILink, shipyard.phase != .needsProjects {
                    CLILinkCard(link: actions.cliLink) { showsCLILink = false }
                        .padding(Grid.gutter - 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if showsNotionConnect {
                    NotionConnectCard(shipyard: shipyard) { showsNotionConnect = false }
                        .padding(Grid.gutter - 4)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Hairline()
                footer(now: context.date)
            }
            .environment(\.panelNow, context.date)
            .hoverHelpHost()
        }
        .frame(width: Grid.panelWidth)
        .animation(Motion.banner, value: showsSkillInstall)
        .animation(Motion.banner, value: showsCLILink)
        .animation(Motion.banner, value: showsNotionConnect)
        .onAppear { if !isSnapshot { actions.panelOpened() } }
        .onDisappear { if !isSnapshot { actions.panelClosed() } }
    }

    // MARK: - Header

    private var header: some View {
        let attention = shipyard.phase == .ready ? shipyard.menu.attention.total : 0
        return HStack(spacing: 8) {
            // The account once it's known; "Shipyard" until then and after signing out.
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
                // Shows the current layout; a click writes the next one to
                // `[menu] layout`, and the menu follows the reload.
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
                // While a refresh runs, the native mini spinner (the one the
                // footer shows) stands in for the arrow; the hidden arrow
                // keeps the button's size, so the header doesn't shift.
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
            // The model's pause, as the banner and the menu bar icon show it.
            .disabled(!shipyard.menu.canRefreshNow || shipyard.phase != .ready)
            .hoverHelp(PanelText.refreshHelp)
            .accessibilityLabel("Refresh")
            Menu {
                Button("Open configuration file", action: actions.openConfigurationFile)
                Button(PanelText.installSkill) { showsSkillInstall = true }
                    // Onboarding shows the card under the picker already.
                    .disabled(shipyard.phase == .needsProjects)
                Button(PanelText.linkCLI) { showsCLILink = true }
                    // Onboarding shows the card under the picker already.
                    .disabled(shipyard.phase == .needsProjects)
                Divider()
                // The notes' token: entered here once, kept in the Keychain.
                if shipyard.notionConnected {
                    Button(PanelText.disconnectNotion) { shipyard.disconnectNotion() }
                } else {
                    Button(PanelText.connectNotion) { showsNotionConnect = true }
                }
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
            .hoverHelp(PanelText.settings)
            .accessibilityLabel(PanelText.settings)
        }
        .padding(.leading, Grid.gutter)
        .padding(.trailing, 8)
        .frame(height: Grid.titleBarHeight)
        .animation(Motion.count, value: attention)
    }

    // MARK: - Banners

    /// The lease's banner first, in every phase and layout, then a quiet
    /// line for each agent the maintainer stopped, then the core's banners
    /// (`Shipyard.banners(at:)`), each with its ✕ when it can be dismissed. A
    /// stopped agent's line stays under the next holder's banner, so Allow
    /// is there for the whole bar. Redrawn when a snooze ends, so a banner
    /// whose hour is up slides back in without a refresh.
    private var banners: some View {
        TimelineView(.explicit(shipyard.bannerSnoozeEnds)) { context in
            // The snooze's end once it's reached, even when its entry fires
            // a moment early; now for any other draw.
            bannerStack(shipyard.banners(at: max(context.date, Date())))
        }
    }

    private func bannerStack(_ items: [PanelBanner]) -> some View {
        let now = Date()
        let leaseEnds = actions.leaseIndicator.shownEnd(at: now)
        let stopped = actions.leaseIndicator.stopped(at: now)
        return VStack(spacing: 6) {
            if let leaseEnds {
                leaseBanner(ends: leaseEnds)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            ForEach(stopped, id: \.holder.key) { bar in
                Banner(
                    symbol: "hand.raised.fill",
                    text: LeaseBanner.tookBack(from: bar.holder.name),
                    tint: Palette.gray,
                    action: (LeaseBanner.allow, { actions.allowLeaseHolder(bar.holder.key) }),
                    trailing: true
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            ForEach(items) { item in
                Banner(
                    symbol: item.symbol,
                    text: item.text,
                    tint: item.tint,
                    action: action(of: item),
                    dismiss: dismiss(of: item)
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, items.isEmpty && leaseEnds == nil && stopped.isEmpty ? 0 : 8)
        .animation(Motion.banner, value: items.map(\.id))
        .animation(Motion.banner, value: leaseEnds == nil)
        .animation(Motion.banner, value: stopped.map(\.holder.key))
    }

    /// A banner's button: notifications off opens System Settings.
    private func action(of banner: PanelBanner) -> (title: String, run: () -> Void)? {
        guard banner.kind == .notificationsOff else { return nil }
        return (PanelText.openNotificationSettings, actions.openNotificationSettings)
    }

    /// A banner's ✕, which hides it for an hour; none on the configuration error's.
    private func dismiss(of banner: PanelBanner) -> (() -> Void)? {
        guard banner.isDismissable else { return nil }
        let shipyard = shipyard
        return { shipyard.dismissBanner(banner.id) }
    }

    /// While an agent holds the lease: its banner, the countdown ticking
    /// each second, on the second the time left changes. The control
    /// server ends the lease when it runs out, which takes the banner away.
    private func leaseBanner(ends: Date) -> some View {
        // Whole seconds before the end: never later than now, since the cap counts from when it was taken.
        TimelineView(.periodic(from: ends.addingTimeInterval(-ControlLease.cap), by: 1)) { context in
            if let lease = actions.leaseIndicator.shown(at: context.date) {
                LeaseBannerView(lease: lease, stop: actions.stopLease)
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch shipyard.phase {
        case .signedOut, .connecting:
            // Signed out, or the device flow's code waiting for approval.
            ConnectView(shipyard: shipyard)
        case .needsProjects:
            // Onboarding's preset step while the file holds nothing but
            // `version`, else the plain picker; and its offers to install the
            // skill and link the CLI.
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

    /// The configured layout, drawing the menu model. Each layout measures
    /// its own scrolling area.
    @ViewBuilder
    private var layout: some View {
        switch shipyard.menu.layout {
        case .list:
            ListLayout(model: shipyard.menu, actions: actions.layoutActions)
        case .tabs:
            TabsLayout(model: shipyard.menu, panel: actions.panelState, actions: actions.layoutActions)
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

/// The header's account: the round avatar and `@handle`, as one
/// button that opens the profile on GitHub (the caller closes the menu).
/// The avatar comes from the `AvatarCache`, so opening the panel downloads
/// nothing once it's stored; until it's there, or when it can't be had, a
/// plain circle stands in, never a broken image. The full name is in the
/// hover text.
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
        // The hover fill reaches past the text, not the text past the gutter.
        .padding(.leading, -4)
        .onHover { inside in
            guard inside != hover else { return }
            hover = inside
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .onDisappear {
            // Clicking closes the menu under the pointer: give the cursor back.
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
        // Bytes that aren't an image leave the placeholder.
        avatar = await avatars.image(for: url).flatMap(NSImage.init(data:))
    }
}

extension PanelBanner {
    /// The banner's icon: configuration error, warnings, refresh delay,
    /// pause, fetch error (the rows are kept; the footer says how old they
    /// are), a remote machine's quiet line, notifications off.
    fileprivate var symbol: String {
        switch kind {
        case .configError: "exclamationmark.octagon.fill"
        case .configWarnings: "info.circle.fill"
        case .delay: "tortoise.fill"
        case .paused: "pause.circle.fill"
        case .fetch: "wifi.exclamationmark"
        case .machine: "server.rack"
        case .notificationsOff: "bell.slash.fill"
        }
    }

    /// Red for the configuration error and a pause, amber for a slower
    /// refresh and a failed one, gray for the quiet ones.
    fileprivate var tint: Color {
        switch kind {
        case .configError, .paused: Palette.red
        case .delay, .fetch: Palette.amber
        case .configWarnings, .machine, .notificationsOff: Palette.gray
        }
    }
}

extension MenuLayout {
    /// The layout button's icon while this layout is shown.
    fileprivate var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .tabs: "rectangle.split.3x1"
        }
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
