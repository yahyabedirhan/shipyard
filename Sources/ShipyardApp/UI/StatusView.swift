import ShipyardCore
import SwiftUI

struct StatusView: View {
    let part: SetupPart
    let actions: AppServices
    let back: () -> Void

    private static let actionHeight: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: back) {
                Text(PanelText.back)
            }
            .buttonStyle(TextButtonStyle(font: TypeScale.body))
            .accessibilityLabel("Back")
            .padding(.horizontal, Grid.gutter)
            .padding(.top, 10)
            if let text = page {
                page(text)
            } else {
                ConnectView(shipyard: actions.shipyard)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedScreen()
        .onChange(of: part, initial: true) { lookAgain() }
    }

    private var page: PanelText.StatusPage? {
        switch part {
        case .cli:
            PanelText.cliStatus(actions.cliLink.state, command: actions.cliLink.command)
        case .github:
            actions.shipyard.gitHubConnection.map(PanelText.gitHubStatus)
        case .skill:
            PanelText.skillStatus(isInstalled: actions.skillDetector.isInstalled, installation: actions.skillInstallation.state)
        case .notion:
            PanelText.notionStatus(actions.shipyard.notionStatus, connected: actions.shipyard.notionConnected)
        }
    }

    private func lookAgain() {
        switch part {
        case .cli: actions.cliLink.check()
        case .skill: actions.skillDetector.check()
        case .notion: checkNotion()
        case .github: break
        }
    }

    private func run(_ action: PanelText.StatusPage.Action) {
        switch action {
        case .linkCLI: actions.cliLink.makeLink()
        case .installSkill: actions.skillInstallation.start()
        case .cancelSkillInstall: actions.skillInstallation.cancel()
        case .checkNotion: checkNotion()
        case .connectNotion:
            back()
            let shipyard = actions.shipyard
            Task { await shipyard.connectNotion() }
        case .disconnectNotion: actions.shipyard.disconnectNotion()
        case .signOut: actions.shipyard.signOut()
        }
    }

    private func checkNotion() {
        let shipyard = actions.shipyard
        Task { await shipyard.checkNotion() }
    }

    private func page(_ text: PanelText.StatusPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SetupBadge(part: part, side: 32)
                Text(text.title).font(TypeScale.display)
            }
            .padding(.bottom, 12)
            line(text.lead)
                .padding(.bottom, 12)
            if let status = text.status {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ToneIcon(tone: status.tone, neutral: "circle.dashed", neutralTint: ThemeColor.textSecondary)
                    MarkdownText(status.text, size: 12, weight: .medium)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 8)
            }
            if let detail = text.detail {
                line(detail).padding(.bottom, 8)
            }
            if let output = text.output {
                OutputBox(output: output)
                    .padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 8) {
                commands(text.commands)
                if let primary = text.primary {
                    button(primary, prominent: true)
                }
                ForEach(text.alternatives.indices, id: \.self) { index in
                    let alternative = text.alternatives[index]
                    Hairline().padding(.vertical, 4)
                    line(alternative.line)
                    commands(alternative.commands)
                    if let button = alternative.button {
                        self.button(button, prominent: false)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func commands(_ commands: [String]) -> some View {
        ForEach(commands, id: \.self) { command in
            CommandBox(command: command, prompt: false)
        }
    }

    private func button(_ button: PanelText.StatusPage.Button, prominent: Bool) -> some View {
        HStack(spacing: 8) {
            if button.action == .cancelSkillInstall {
                ProgressView().controlSize(.small)
            }
            Button { run(button.action) } label: {
                Text(button.title).frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(prominent: prominent && button.action != .cancelSkillInstall, height: Self.actionHeight))
        }
    }

    private func line(_ text: String) -> some View {
        MarkdownText(text, size: 12)
            .foregroundStyle(ThemeColor.textSecondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}
