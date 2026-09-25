import ShipyardCore
import SwiftUI

/// The panel the menu bar icon opens: what fits the lifecycle phase, the
/// banners, one section per project, and the footer. It draws the core's
/// `Shipyard` directly (it's observable) and redraws the ages every 30 s.
struct Panel: View {
    let shipyard: Shipyard
    let actions: AppServices

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 0) {
                banners(now: context.date)
                content(now: context.date)
                Divider()
                footer(now: context.date)
            }
        }
        .frame(width: 380)
        // Opening the panel refreshes (the rate budget may hold it back).
        .onAppear { actions.refresh() }
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
            message(
                "No projects yet",
                detail: "Add a [[projects]] block to config.toml; shipyard picks it up as soon as you save.",
                action: ("Open configuration file", actions.openConfigurationFile)
            )
        case .ready:
            // As tall as the sections, scrolling once they pass 560 pt.
            ViewThatFits(in: .vertical) {
                sections(now: now)
                ScrollView { sections(now: now) }
            }
            .frame(maxHeight: 560)
        }
    }

    private func sections(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(shipyard.menu.sections) { section in
                ProjectSection(section: section, now: now) { shipyard.open($0) }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ title: String, detail: LocalizedStringKey, action: (String, () -> Void)) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Button(action.0, action: action.1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Banners

    @ViewBuilder
    private func banners(now: Date) -> some View {
        if let error = shipyard.configError {
            banner(PanelText.configError(error), symbol: "exclamationmark.octagon.fill", color: Palette.red)
        }
        if shipyard.phase == .ready, let error = shipyard.menu.fetchError {
            // The rows are kept; the footer says how old they are.
            banner(PanelText.fetchError(error), symbol: "wifi.exclamationmark", color: Palette.amber)
        }
    }

    private func banner(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(color)
            Text(text)
                .font(.caption)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
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
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("Refresh", action: actions.refresh)
                    .keyboardShortcut("r")
                    .disabled(!shipyard.canRefreshNow || shipyard.phase != .ready)
                Button("Open configuration file", action: actions.openConfigurationFile)
                // Once signed in: while `start()` still asks GitHub, the
                // token is picked but the panel says it's connecting.
                if shipyard.phase != .signedOut, shipyard.tokenSource != nil {
                    Button("Sign out") { shipyard.signOut() }
                }
                Spacer()
                Button("Quit", action: actions.quit)
                    .keyboardShortcut("q")
            }
            .buttonStyle(.link)
            .font(.callout)
        }
        .padding(10)
    }
}
