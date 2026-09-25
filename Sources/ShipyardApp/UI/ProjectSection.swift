import ShipyardCore
import SwiftUI

/// One project: a header that collapses and expands it, with its attention
/// count and "Mark all seen", then a row per item and an error row per
/// repository that couldn't be fetched.
struct ProjectSection: View {
    let section: MenuSection
    let now: Date
    let open: (MenuRow) -> Void
    let markSeen: (MenuRow) -> Void
    let markAllSeen: () -> Void
    let toggleCollapsed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if !section.isCollapsed {
                ForEach(section.errors) { error in
                    Label(error.message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Palette.amber)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
                if let empty = PanelText.emptySection(section) {
                    Text(empty)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                }
                ForEach(section.rows) { row in
                    ItemRow(
                        row: row,
                        showsRepository: section.showsRepository,
                        now: now,
                        open: { open(row) },
                        markSeen: { markSeen(row) }
                    )
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: toggleCollapsed) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(section.isCollapsed ? 0 : 90))
                        .frame(width: 10)
                    Text(section.name)
                        .font(.subheadline.weight(.semibold))
                    if section.attentionCount > 0 {
                        Text(String(section.attentionCount))
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                            .accessibilityLabel("\(section.attentionCount) need attention")
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(section.isCollapsed ? "Expand \(section.name)" : "Collapse \(section.name)")
            if section.attentionCount > 0 {
                Button("Mark all seen", action: markAllSeen)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}
