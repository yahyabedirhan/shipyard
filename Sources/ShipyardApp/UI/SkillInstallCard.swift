import ShipyardCore
import SwiftUI

struct SkillInstallCard: View {
    let installation: SkillInstallation
    @Environment(\.panelScale) private var scale

    var body: some View {
        let text = PanelText.skillInstall(installation.state)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                ToneIcon(tone: text.tone, neutral: "sparkles", neutralTint: ThemeColor.accent)
                Text(text.title).font(scale.type.bodyEmphasis).foregroundStyle(ThemeColor.textPrimary)
                Spacer()
            }
            .frame(minHeight: 22)
            Text(text.message)
                .font(scale.type.body)
                .foregroundStyle(ThemeColor.textSecondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            if let output = text.output {
                OutputBox(output: output)
            }
            if let command = text.command {
                CommandBox(command: command, prompt: false)
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
