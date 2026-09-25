import AppKit
import ShipyardCore
import SwiftUI

/// Onboarding's connect step. 0.0.x connects through the GitHub CLI only
/// (sign-in without `gh` is #22), so it says what happened and which `gh`
/// command to run, with a Copy button, and Try again looks for `gh`'s token
/// once more. The words come from `PanelText.connect`.
///
/// Shown while `phase` is `signedOut`. `start()` clears the reason while it
/// looks for a token, so the last one stays on screen during Try again; before
/// any is known (at launch) a spinner shows instead.
struct ConnectView: View {
    let shipyard: Shipyard

    @State private var shown: Shipyard.SignedOutReason?
    @State private var isTrying = false
    /// Try again left shipyard signed out: say so, or the click seems to do nothing.
    @State private var stillSignedOut = false
    @State private var copied = false

    var body: some View {
        Group {
            if let reason = shipyard.signedOutReason ?? shown {
                screen(PanelText.connect(reason))
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(PanelText.connecting).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onChange(of: shipyard.signedOutReason, initial: true) { _, reason in
            if let reason { shown = reason }
        }
    }

    private func screen(_ text: PanelText.Connect) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(text.title).font(.headline)
            Text(text.message)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if text.suggestsInstallingGh {
                Text(LocalizedStringKey(PanelText.installGh))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            command(text.command)
            HStack(spacing: 8) {
                // Not the default action: after signing out of gh's token,
                // Return would connect straight back.
                Button("Try again", action: tryAgain)
                    .disabled(isTrying)
                if isTrying {
                    ProgressView().controlSize(.small)
                } else if stillSignedOut, let reason = shipyard.signedOutReason {
                    Text(PanelText.stillSignedOut(reason))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: text.command) { copied = false }
    }

    private func command(_ command: String) -> some View {
        HStack(spacing: 8) {
            Text(command)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
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

    private func tryAgain() {
        isTrying = true
        stillSignedOut = false
        Task {
            await shipyard.start()
            isTrying = false
            stillSignedOut = shipyard.phase == .signedOut
        }
    }
}
