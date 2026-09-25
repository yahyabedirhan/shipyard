import AppKit
import ShipyardCore
import SwiftUI

/// The agent skill install: the offer, the running install with Cancel, and
/// how it ended (installed, the failure's output, or the command to copy when
/// `npx` isn't found), in `PanelText.skillInstall`'s words. Onboarding shows
/// it under the picker; the footer's "Install agent skill…" shows it above
/// the footer, with `close` to hide it again.
struct SkillInstallCard: View {
    let installation: SkillInstallation
    /// Hides the card; `nil` in onboarding, where it stays.
    var close: (() -> Void)?

    @State private var copied = false

    var body: some View {
        let text = PanelText.skillInstall(installation.state)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                icon(text.tone)
                Text(text.title).font(.subheadline.weight(.semibold))
                Spacer()
                if let close {
                    Button(action: close) {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Close")
                }
            }
            Text(text.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let output = text.output {
                Text(output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
            if let command = text.command {
                commandLine(command)
            }
            if let action = text.action {
                HStack(spacing: 8) {
                    switch action {
                    case .install:
                        Button("Install") { installation.start() }
                    case .tryAgain:
                        Button("Try again") { installation.start() }
                    case .cancel:
                        ProgressView().controlSize(.small)
                        Button("Cancel") { installation.cancel() }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .onChange(of: installation.state) { copied = false }
    }

    @ViewBuilder
    private func icon(_ tone: PanelText.SkillInstall.Tone) -> some View {
        switch tone {
        case .success:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.amber)
        case .neutral:
            Image(systemName: "sparkles").foregroundStyle(.secondary)
        }
    }

    private func commandLine(_ command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
    }
}
