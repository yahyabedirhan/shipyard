import ShipyardCore
import SwiftUI

struct CLILinkCard: View {
    let link: CLILink
    @Environment(\.panelScale) private var scale

    var body: some View {
        let text = PanelText.cliLink(link.state, command: link.command)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                ToneIcon(tone: text.tone, neutral: "terminal", neutralTint: ThemeColor.accent)
                Text(text.title).font(scale.type.bodyEmphasis).foregroundStyle(ThemeColor.textPrimary)
                Spacer()
            }
            .frame(minHeight: 22)
            Text(text.message)
                .font(scale.type.body)
                .foregroundStyle(ThemeColor.textSecondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            if let command = text.command {
                CommandBox(command: command, prompt: false)
            }
            if let action = text.action {
                HStack(spacing: 8) {
                    Spacer()
                    switch action {
                    case .link:
                        Button("Link") { link.makeLink() }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    case .tryAgain:
                        Button("Try again") { link.makeLink() }
                            .buttonStyle(PillButtonStyle(prominent: true))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .onAppear { link.check() }
    }
}
