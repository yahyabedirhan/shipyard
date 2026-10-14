import ShipyardCore
import SwiftUI

struct SkillInstallCard: View {
    let installation: SkillInstallation

    var body: some View {
        let text = PanelText.skillInstall(installation.state)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                ToneIcon(tone: text.tone, neutral: "sparkles", neutralTint: Palette.accent)
                Text(text.title).font(TypeScale.bodyEmphasis)
                Spacer()
            }
            .frame(minHeight: 22)
            Text(text.message)
                .font(TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            if let output = text.output {
                Text(output)
                    .font(.system(size: 10.5, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).fill(Palette.fill))
            }
            if let command = text.command {
                CommandBox(command: command, prompt: false, font: .system(size: 11, weight: .medium, design: .monospaced))
            }
            if let action = text.action {
                HStack(spacing: 8) {
                    Spacer()
                    switch action {
                    case .install:
                        Button("Install") { installation.start() }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    case .tryAgain:
                        Button("Try again") { installation.start() }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    case .cancel:
                        ProgressView().controlSize(.small)
                        Button("Cancel") { installation.cancel() }
                            .buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
