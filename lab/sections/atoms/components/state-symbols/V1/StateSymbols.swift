import LabHost
import SwiftUI

/// What leads every row: the attention dot, the state symbol in its tinted
/// square, the pull request's check dot on it, and a ping's agent mark.
public let variant = LabVariant { StateSymbolSheet() }

struct StateSymbolSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(Gallery.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 0) {
                    AttentionDot(isOn: row.needsAttention)
                        .frame(width: Grid.dotColumn, alignment: .leading)
                    StateSymbol(row: row)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: Grid.smallRadius + 1, style: .continuous)
                                .fill(Palette.color(row.state, kind: row.kind).opacity(0.14))
                        )
                        .overlay(alignment: .bottomTrailing) { CheckDot(checks: row.checks).offset(x: 2, y: 2) }
                        .padding(.trailing, 10)
                    Text("\(row.kind.commandName) · \(row.state.rawValue)\(row.checks.map { " · checks \($0.rawValue)" } ?? "")")
                        .font(TypeScale.meta)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 12)
                    if let agent = row.agent {
                        AgentMarkView(agent: agent, size: Grid.agentMark)
                    }
                }
            }
            Specimen(title: "every known agent's mark") {
                HStack(spacing: 10) {
                    ForEach(KnownAgent.allCases, id: \.self) { AgentMarkView(agent: $0, size: 20) }
                }
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(width: 360)
        .background(Palette.panel)
        .environment(\.panelNow, Gallery.now)
    }
}
