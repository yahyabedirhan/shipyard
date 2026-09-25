import ShipyardCore
import SwiftUI

/// One item: its state icon in GitHub's colour, number and title, author
/// and age, and the check dot. Clicking opens it in the browser.
struct ItemRow: View {
    let row: MenuRow
    let now: Date
    let open: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Palette.symbol(row.state, kind: row.kind))
                    .foregroundStyle(Palette.color(row.state, kind: row.kind))
                    .frame(width: 14)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if let checks = row.checks, let color = Palette.color(checks) {
                    Circle()
                        .fill(color)
                        .frame(width: 7, height: 7)
                        .help(checksHelp(checks))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(row.url.absoluteString)
    }

    /// "#12 · owner/repo · yabepa · 3h".
    private var detail: String {
        let repository = row.repository.split(separator: "/").last.map(String.init) ?? row.repository
        return ["#\(row.number)", repository, row.author, PanelText.age(row.age(at: now))].joined(separator: " · ")
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
