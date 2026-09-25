import AppKit
import ShipyardCore
import SwiftUI

/// One item: a dot when it needs attention, its state icon in GitHub's
/// colour, its title (a run: its workflow's name), the second line
/// (number, author and age; a run: number, branch, state and age), and a
/// pull request's check dot. Clicking opens it in the browser and marks
/// it seen; ⌥-click only marks it seen.
struct ItemRow: View {
    let row: MenuRow
    /// Whether the second line names the repository (its project has more than one).
    let showsRepository: Bool
    let now: Date
    let open: () -> Void
    let markSeen: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: click) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(row.needsAttention ? Color.accentColor : .clear)
                    .frame(width: 6, height: 6)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                    .accessibilityHidden(!row.needsAttention)
                    .accessibilityLabel("Needs attention")
                Image(systemName: Palette.symbol(row.state, kind: row.kind))
                    .foregroundStyle(Palette.color(row.state, kind: row.kind))
                    .frame(width: 14)
                    .accessibilityLabel(PanelText.stateLabel(row))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .fontWeight(row.needsAttention ? .semibold : .regular)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        // Whatever runs long (a run's branch, an author)
                        // gives way in the middle, so the age, and a run's
                        // state, stay readable.
                        .truncationMode(.middle)
                }
                Spacer(minLength: 4)
                if let checks = row.checks, let color = Palette.color(checks) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .help(checksHelp(checks))
                }
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        // ⌥-click's equivalent for the keyboard and VoiceOver.
        .accessibilityAction(named: "Mark seen", markSeen)
        .onHover { isHovered = $0 }
        .help(row.needsAttention ? "\(row.url.absoluteString)\n⌥-click to mark seen" : row.url.absoluteString)
    }

    /// ⌥ held: mark seen without opening; otherwise open (which marks seen).
    private func click() {
        let flags = NSApp.currentEvent?.modifierFlags ?? NSEvent.modifierFlags
        if flags.contains(.option) { markSeen() } else { open() }
    }

    /// `PanelText.rowDetail`.
    private var detail: String {
        PanelText.rowDetail(row, showingRepository: showsRepository, now: now)
    }

    private func checksHelp(_ checks: ChecksState) -> String {
        switch checks {
        case .none: ""
        case .pending: "Checks running"
        case .passed: "Checks passed"
        case .failed: "Checks failed"
        }
    }
}
