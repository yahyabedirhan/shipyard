import ShipyardCore
import SwiftUI

/// The offer to link the bundled `shipyard` CLI into `~/.local/bin`, and how
/// it went (linked, or the command to copy when something is in the way or
/// the link can't be made), in `PanelText.cliLink`'s words. It looks again
/// each time it appears, since the user may have linked it by hand. Shaped
/// like `SkillInstallCard`: onboarding shows it under the skill card; the
/// header's "Link shipyard CLI…" shows it above the footer, with `close`.
struct CLILinkCard: View {
    let link: CLILink
    /// Hides the card; `nil` in onboarding, where it stays.
    var close: (() -> Void)?

    var body: some View {
        let text = PanelText.cliLink(link.state, command: link.command)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                icon(text.tone)
                Text(text.title).font(TypeScale.bodyEmphasis)
                Spacer()
                if let close {
                    Button(action: close) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(IconButtonStyle())
                    // No hover help: an ✕ in a card's corner says what it does.
                    .accessibilityLabel("Close")
                }
            }
            .frame(minHeight: 22)
            Text(text.message)
                .font(TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            if let command = text.command {
                CommandBox(command: command, prompt: false, font: .system(size: 11, weight: .medium, design: .monospaced))
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

    private func icon(_ tone: PanelText.SkillInstall.Tone) -> some View {
        Group {
            switch tone {
            case .success:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.amber)
            case .neutral:
                Image(systemName: "terminal").foregroundStyle(Palette.accent)
            }
        }
        .symbolRenderingMode(.hierarchical)
        .font(.system(size: 12, weight: .semibold))
    }
}
