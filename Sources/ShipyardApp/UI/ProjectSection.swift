import ShipyardCore
import SwiftUI

/// One project: its name, then a row per item and an error row per
/// repository that couldn't be fetched.
struct ProjectSection: View {
    let section: MenuSection
    let now: Date
    let open: (MenuRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(section.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 6)
            ForEach(section.errors) { error in
                Label(error.message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Palette.amber)
                    .lineLimit(2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            if section.rows.isEmpty && section.errors.isEmpty {
                Text("Nothing open")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            ForEach(section.rows) { row in
                ItemRow(row: row, now: now) { open(row) }
            }
        }
    }
}
