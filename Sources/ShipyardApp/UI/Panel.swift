import ShipyardConfig
import ShipyardControl
import ShipyardCore
import SwiftUI

struct Panel: View {
    let shipyard: Shipyard
    let actions: AppServices
    var isSnapshot = false

    var body: some View {
        // The theme is set below this view, so its own sizes come from the
        // theme's knobs here; the views it builds read the environment's.
        let scale = PanelScale(shipyard.theme.knobs)
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                header(scale)
                banners
                Hairline()
                content(scale)
                Hairline()
                footer(now: context.date, scale: scale)
            }
            .environment(\.panelNow, context.date)
            .hoverHelpHost()
        }
        .frame(width: Grid.panelWidth)
        .background { PanelBackdrop() }
        .background { if !isSnapshot { PanelWindowAnchor(isOpen: actions.panelState.isOpen) } }
        .theme(shipyard.theme)
        .onAppear { if !isSnapshot { actions.panelOpened() } }
        .onDisappear { if !isSnapshot { actions.panelClosed() } }
        .onChange(of: actions.skillInstallation.state) { actions.skillDetector.check() }
    }

    private func header(_ scale: PanelScale) -> some View {
        let attention = shipyard.phase == .ready ? shipyard.menu.attention.total : 0
        return HStack(spacing: 8) {
            if let viewer = shipyard.viewer {
                AccountButton(viewer: viewer, avatars: actions.avatars, action: actions.openProfile)
            } else {
                Text(PanelText.title(for: nil))
                    .font(scale.type.title)
                    .foregroundStyle(ThemeColor.textPrimary)
            }
            if let summary = PanelText.attentionSummary(attention) {
                Text(summary)
                    .font(scale.type.caption)
                    .foregroundStyle(ThemeColor.textSecondary)
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
            SettingsMenuButton { settingsItems }
                .hoverHelp(PanelText.settings)
            .accessibilityLabel(PanelText.settings)
        }
        .padding(.leading, scale.grid.gutter)
        .padding(.trailing, 8)
        .frame(height: scale.grid.titleBarHeight)
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
                Button(item.title) { actions.panelState.show(part) }
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
            return (PanelText.openBannerView, { panelState.show(part) })
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
    private func content(_ scale: PanelScale) -> some View {
        if let part = actions.panelState.openView {
            StatusView(part: part, actions: actions) { actions.panelState.show(nil) }
        } else {
            phaseContent(scale)
        }
    }

    @ViewBuilder
    private func phaseContent(_ scale: PanelScale) -> some View {
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
                .padding(.horizontal, scale.grid.gutter)
                .padding(.bottom, 8)
            CLILinkCard(link: actions.cliLink)
                .padding(.horizontal, scale.grid.gutter)
                .padding(.bottom, scale.grid.gutter)
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

    private func footer(now: Date, scale: PanelScale) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if shipyard.isRefreshing {
                    ProgressView().controlSize(.mini)
                    Text("Refreshing…")
                        .font(scale.type.caption)
                        .foregroundStyle(ThemeColor.textSecondary)
                } else if let updated = PanelText.lastUpdated(shipyard.menu.lastUpdated, now: now) {
                    Image(systemName: "clock")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(ThemeColor.textTertiary)
                    Text(updated)
                        .font(scale.type.caption)
                        .foregroundStyle(ThemeColor.textSecondary)
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
                        Text("⌘Q").foregroundStyle(ThemeColor.textTertiary)
                    }
                }
                .buttonStyle(TextButtonStyle(tint: ThemeColor.textPrimary, font: \.caption))
                .keyboardShortcut("q")
            }
            if shipyard.phase == .ready, let indicator = shipyard.menu.rateIndicator {
                ForEach(indicator.apis, id: \.api) { usage in
                    RateLine(usage: usage)
                }
            }
        }
        .padding(.leading, scale.grid.gutter)
        .padding(.trailing, scale.grid.gutter - 6)
        .padding(.vertical, 8)
        .background(ThemeColor.chrome)
        .animation(.spring(duration: 0.5), value: shipyard.menu.rateIndicator)
    }
}

/// The header's gear: the settings menu, drawn like the header's icon
/// buttons. The system draws a borderless menu's own icon in the label
/// colour, darker than the icons beside it, whatever style it's given; so
/// the gear is an image already tinted with the theme's colour, secondary at
/// rest and primary under the pointer, on the icon buttons' hover fill.
private struct SettingsMenuButton<Items: View>: View {
    @ViewBuilder let items: Items
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme
    @State private var hover = false

    var body: some View {
        let tint = hover ? ThemeColor.textPrimary : ThemeColor.textSecondary
        Menu {
            items
        } label: {
            Image(nsImage: SymbolImage.tinted("gearshape", NSColor(tint.color(in: theme, ThemeAppearance(scheme)))))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .frame(width: 24, height: 22)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(ThemeColor.rowHover.opacity(hover ? 1 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .animation(Motion.hover, value: hover)
    }
}

/// An SF Symbol drawn in one colour into an image that isn't a template, so
/// AppKit draws it as it is rather than tinting it with the label colour.
enum SymbolImage {
    static func tinted(_ name: String, _ color: NSColor, pointSize: CGFloat = 12, weight: NSFont.Weight = .medium) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        else { return NSImage() }
        // The ink is painted opaque over the glyph, then the glyph is drawn at
        // the colour's alpha. Painting a translucent colour over the black
        // glyph would leave it near black: a `label` at 70% read as `label`.
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let solid = rgb.withAlphaComponent(1)
        let glyph = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            solid.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            glyph.draw(in: rect, from: .zero, operation: .sourceOver, fraction: rgb.alphaComponent)
            return true
        }
        image.isTemplate = false
        return image
    }
}

private struct AccountButton: View {
    let viewer: Viewer
    let avatars: AvatarCache
    let action: () -> Void
    @State private var avatar: NSImage?
    @State private var hover = false
    @Environment(\.panelScale) private var scale

    private static let avatarSize: CGFloat = 20

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                avatarView
                Text(PanelText.title(for: viewer))
                    .font(scale.type.title)
                    .foregroundStyle(ThemeColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 4)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(ThemeColor.rowHover.opacity(hover ? 1 : 0))
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
                    .fill(ThemeColor.field)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(ThemeColor.textTertiary)
                    )
            }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(ThemeColor.border, lineWidth: 0.5))
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

    fileprivate var tint: ThemeColor {
        switch kind {
        // A delay is the rate limit running low, a pause the limit spent.
        case .delay: ThemeColor.rate(.low)
        case .paused: ThemeColor.rate(.exhausted)
        case .configError, .fetch: ThemeColor.failed
        case .lease: ThemeColor.lease
        case .stoppedHolder, .configWarnings, .machine, .notes, .notificationsOff: ThemeColor.quiet
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
    @Environment(\.panelScale) private var scale

    private var fraction: Double {
        Double(max(0, usage.remaining)) / Double(max(1, usage.limit))
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                Capsule().fill(ThemeColor.track)
                Capsule().fill(ThemeColor.rateBar(usage.level)).frame(width: 26 * fraction)
            }
            .frame(width: 26, height: 4)
            .accessibilityHidden(true)
            Text(PanelText.rateUsage(usage))
                .font(scale.type.caption)
                .foregroundStyle(ThemeColor.rateText(usage.level))
        }
    }
}
