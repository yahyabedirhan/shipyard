import ShipyardCore
import SwiftUI

/// A part's status view (`SetupPart`), in place of the panel's content
/// while `PanelState.openView` names it: the ‹ Back row, then the page
/// `PanelText` gives for the part, in the signed-out onboarding view's
/// shape (`ConnectView`): the logo badge and the title, the lead line, the
/// status line with its tone's icon, what to do, each command in a box with
/// a copy button, the full-width button, and an alternative under a
/// divider. One view draws every part; each part's page and the actions its
/// buttons run are picked here. The GitHub view, signed out, shows the
/// signed-out onboarding view (`ConnectView`) under ‹ Back instead.
struct StatusView: View {
    let part: SetupPart
    let actions: AppServices
    /// ‹ Back: the projects again.
    let back: () -> Void

    /// The height of the page's full-width buttons, as onboarding's.
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
            if part == .github, actions.shipyard.gitHubConnection == nil {
                // Signed out: the signed-out onboarding view's content, its ways in included.
                ConnectView(shipyard: actions.shipyard)
            } else {
                page(page)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The user may have changed the part by hand since it was last looked at.
        .onChange(of: part, initial: true) { lookAgain() }
    }

    /// The part's words, as its state is now.
    private var page: PanelText.StatusPage {
        switch part {
        case .cli:
            PanelText.cliStatus(actions.cliLink.state, command: actions.cliLink.command)
        case .github:
            actions.shipyard.gitHubConnection.map(PanelText.gitHubStatus) ?? PanelText.placeholderStatus(part)
        case .notion, .skill:
            PanelText.placeholderStatus(part)
        }
    }

    private func lookAgain() {
        switch part {
        case .cli: actions.cliLink.check()
        case .github, .notion, .skill: break
        }
    }

    private func run(_ action: PanelText.StatusPage.Action) {
        switch action {
        case .linkCLI: actions.cliLink.makeLink()
        }
    }

    // MARK: - The page

    private func page(_ text: PanelText.StatusPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LogoBadge(side: 32)
                Text(text.title).font(TypeScale.display)
            }
            .padding(.bottom, 12)
            line(text.lead)
                .padding(.bottom, 12)
            if let status = text.status {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    ToneIcon(tone: status.tone, neutral: "circle.dashed", neutralTint: .secondary)
                    Text(markdown: status.text, size: 12, weight: .medium)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 8)
            }
            if let detail = text.detail {
                line(detail).padding(.bottom, 8)
            }
            VStack(alignment: .leading, spacing: 8) {
                commands(text.commands)
                if let primary = text.primary {
                    button(primary, prominent: true)
                }
                if let alternative = text.alternative {
                    Divider().padding(.vertical, 4)
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
            CommandBox(command: command, prompt: false, font: .system(size: 11, weight: .medium, design: .monospaced))
        }
    }

    private func button(_ button: PanelText.StatusPage.Button, prominent: Bool) -> some View {
        Button { run(button.action) } label: {
            Text(button.title).frame(maxWidth: .infinity)
        }
        .buttonStyle(PillButtonStyle(prominent: prominent, height: Self.actionHeight))
    }

    /// A line of the page's words, which may hold code spans.
    private func line(_ text: String) -> some View {
        Text(markdown: text, size: 12)
            .foregroundStyle(.secondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }
}
