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

    var body: some View {
        Group {
            if let reason = shipyard.signedOutReason ?? shown {
                screen(PanelText.connect(reason))
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(PanelText.connecting).font(TypeScale.body).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.accent, Palette.accent.opacity(0.75)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "sailboat.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                    )
                    .accessibilityHidden(true)
                Text(text.title).font(TypeScale.display)
            }
            .padding(.bottom, 12)
            Text(text.message)
                .font(TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 10)
            CommandBox(command: text.command)
                .padding(.bottom, 10)
            if text.suggestsInstallingGh {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Text(LocalizedStringKey(PanelText.installGh))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .tint(Palette.accent)
                }
                .padding(.bottom, 4)
            }
            HStack(spacing: 8) {
                if isTrying {
                    ProgressView().controlSize(.small)
                } else if stillSignedOut, let reason = shipyard.signedOutReason {
                    Text(PanelText.stillSignedOut(reason))
                        .font(TypeScale.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Not the default action: after signing out of gh's token,
                // Return would connect straight back.
                Button("Try again", action: tryAgain)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(isTrying)
            }
            .padding(.top, 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
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
