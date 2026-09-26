import AppKit
import ShipyardCore
import SwiftUI

/// Onboarding's connect step. Signed out, it says what happened, offers
/// Sign in with GitHub (the device flow), and beside it the `gh` command to
/// run, with a Copy button; Try again looks for a token once more. A build
/// without an OAuth App client ID shows Sign in with GitHub disabled, with
/// why, and `gh` stays the way in. While the device flow waits (`connecting`)
/// it shows the code, a button that copies it and opens github.com/login/device,
/// and Cancel. The words come from `PanelText.connect` and `PanelText.deviceCode`.
///
/// `start()` clears the reason while it looks for a token, so the last one
/// stays on screen during Try again; before any is known (at launch) a
/// spinner shows instead.
struct ConnectView: View {
    let shipyard: Shipyard

    @State private var shown: Shipyard.SignedOutReason?
    @State private var isTrying = false
    /// Sign in with GitHub was clicked and GitHub hasn't sent a code yet.
    @State private var isRequestingCode = false
    /// Try again left shipyard signed out: say so, or the click seems to do nothing.
    @State private var stillSignedOut = false

    var body: some View {
        Group {
            if case .connecting(let code) = shipyard.phase {
                codeScreen(PanelText.deviceCode(code))
            } else if let reason = shipyard.signedOutReason ?? shown {
                screen(PanelText.connect(reason, canSignIn: shipyard.canSignInWithGitHub))
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
        .onChange(of: shipyard.phase) { isRequestingCode = false }
    }

    // MARK: - Signed out

    private func screen(_ text: PanelText.Connect) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(text.title)
            Text(text.message)
                .font(TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            signIn(unavailable: text.signInUnavailable)
                .padding(.bottom, 12)
            Hairline()
                .padding(.bottom, 10)
            Text(text.commandLead)
                .font(TypeScale.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
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
                // Return would connect straight back. Quiet when Sign in
                // with GitHub is the screen's main action.
                Button("Try again", action: tryAgain)
                    .buttonStyle(PillButtonStyle(prominent: text.signInUnavailable != nil))
                    .disabled(isTrying || isRequestingCode)
            }
            .padding(.top, 10)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sign in with GitHub, and under it why the last one failed, or why
    /// the build can't offer it.
    private func signIn(unavailable: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(PanelText.signInWithGitHub, action: beginSignIn)
                    .buttonStyle(PillButtonStyle(prominent: unavailable == nil))
                    .disabled(unavailable != nil || isRequestingCode || isTrying)
                if isRequestingCode {
                    ProgressView().controlSize(.small)
                }
            }
            if let note = unavailable ?? shipyard.signInError.map(PanelText.signInFailed) {
                Text(note)
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The code (connecting)

    private func codeScreen(_ text: PanelText.DeviceCodeScreen) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(text.title)
            Text(text.message)
                .font(TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
            Text(text.code)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .kerning(2)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .card()
                .padding(.bottom, 8)
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(text.waiting)
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Spacer()
                Button(PanelText.cancelSignIn) { shipyard.cancelDeviceFlow() }
                    .buttonStyle(PillButtonStyle())
                Button(text.openButton) { copyAndOpen(text.code) }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func heading(_ title: String) -> some View {
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
            Text(title).font(TypeScale.display)
        }
        .padding(.bottom, 12)
    }

    // MARK: - Actions

    private func beginSignIn() {
        isRequestingCode = true
        stillSignedOut = false
        let flow = shipyard.beginDeviceFlow()
        Task {
            // Ends only when the whole flow does; a code arriving first
            // clears the spinner through the phase change.
            await flow.value
            isRequestingCode = false
        }
    }

    /// The code goes on the clipboard first: opening the browser may close
    /// the menu, and the code is then ready to paste.
    private func copyAndOpen(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        shipyard.openVerificationPage()
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
