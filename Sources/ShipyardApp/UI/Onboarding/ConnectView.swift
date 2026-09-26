import ShipyardCore
import SwiftUI

/// Onboarding's connect step. Signed out, it says what happened in a line
/// and puts the fix right there, in the order `PanelText.Connect.lead`
/// gives: Sign in with GitHub (the device flow) first, with the `gh` way
/// folded in a disclosure under it; or the `gh auth login` box with Connect
/// with gh beside it; or Connect with gh alone beside the message, when `gh`
/// is signed in already. Connect with gh looks for a token once more
/// (`start()`). A build without an OAuth App client ID shows Sign in with
/// GitHub disabled, with why, and `gh` leads. While the device flow waits
/// (`connecting`) it shows the code (a click on it, or on its copy icon,
/// copies it), a button that copies it and opens github.com/login/device,
/// and Cancel. The words come from `PanelText.connect` and `PanelText.deviceCode`.
///
/// `start()` clears the reason while it looks for a token, so the last one
/// stays on screen during Connect with gh; before any is known (at launch)
/// a spinner shows instead.
struct ConnectView: View {
    let shipyard: Shipyard

    @State private var shown: Shipyard.SignedOutReason?
    @State private var isTrying = false
    /// Sign in with GitHub was clicked and GitHub hasn't sent a code yet.
    @State private var isRequestingCode = false
    /// Connect with gh left shipyard signed out: say so, or the click seems to do nothing.
    @State private var stillSignedOut = false
    /// The `gh` disclosure under Sign in with GitHub is open.
    @State private var showsGh = false
    /// The install hint's popover is open.
    @State private var showsInstallHint = false
    /// The code is on the clipboard: the copy icon shows a checkmark.
    @State private var codeCopied = false

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
            switch text.lead {
            case .signIn:
                message(text.message)
                    .padding(.bottom, 12)
                signIn(prominent: true, unavailable: text.signInUnavailable)
                    .padding(.bottom, 12)
                DisclosureGroup(isExpanded: $showsGh) {
                    ghCommand(prominent: false, installHint: true)
                        .padding(.top, 8)
                } label: {
                    markdown(PanelText.useGhInstead)
                        .font(TypeScale.body)
                        .foregroundStyle(.secondary)
                        .hoverHelp(markdown: PanelText.useGhInsteadHelp)
                }
            case .ghCommand:
                message(text.message)
                    .padding(.bottom, 12)
                ghCommand(prominent: true, installHint: text.showsInstallHint)
                    .padding(.bottom, 12)
                signIn(prominent: false, unavailable: text.signInUnavailable)
            case .connectWithGh:
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    message(text.message)
                    Spacer(minLength: 0)
                    connectWithGh(prominent: true)
                }
                stillSignedOutNote
                    .padding(.top, 6)
                signIn(prominent: false, unavailable: text.signInUnavailable)
                    .padding(.top, 12)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func message(_ text: String) -> some View {
        markdown(text)
            .font(TypeScale.body)
            .foregroundStyle(.secondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The `gh auth login` box with Connect with gh beside it, the install
    /// hint after it, and under it why the last Connect with gh found nothing.
    private func ghCommand(prominent: Bool, installHint: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CommandBox(command: PanelText.ghLogin)
                connectWithGh(prominent: prominent)
                if installHint { installHintButton }
            }
            stillSignedOutNote
        }
    }

    /// Looks for a token once more (`start()`). Never the default action:
    /// after signing out of `gh`'s token, Return would connect straight back.
    private func connectWithGh(prominent: Bool) -> some View {
        HStack(spacing: 6) {
            if isTrying { ProgressView().controlSize(.small) }
            Button(action: connectAgain) { markdown(PanelText.connectWithGh) }
                .buttonStyle(PillButtonStyle(prominent: prominent))
                .disabled(isTrying || isRequestingCode)
        }
        .fixedSize()
    }

    @ViewBuilder
    private var stillSignedOutNote: some View {
        if stillSignedOut, !isTrying, let reason = shipyard.signedOutReason {
            markdown(PanelText.stillSignedOut(reason))
                .font(TypeScale.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The ⓘ beside the `gh` way: a popover with where to get `gh`, and
    /// the Homebrew command to copy.
    private var installHintButton: some View {
        Button { showsInstallHint.toggle() } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(IconButtonStyle())
        .hoverHelp(markdown: PanelText.installGhHelp)
        .accessibilityLabel(PanelText.installGhHelp.replacingOccurrences(of: "`", with: ""))
        .popover(isPresented: $showsInstallHint, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                markdown(PanelText.installGh)
                    .font(TypeScale.body)
                    .tint(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                CommandBox(command: PanelText.brewInstallGh)
            }
            .padding(12)
            .frame(width: 260)
        }
    }

    /// Sign in with GitHub, and under it why the last one failed, or why
    /// the build can't offer it.
    private func signIn(prominent: Bool, unavailable: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(PanelText.signInWithGitHub, action: beginSignIn)
                    .buttonStyle(PillButtonStyle(prominent: prominent && unavailable == nil))
                    .disabled(unavailable != nil || isRequestingCode || isTrying)
                if isRequestingCode {
                    ProgressView().controlSize(.small)
                }
            }
            if let note = unavailable ?? shipyard.signInError.map(PanelText.signInFailed) {
                markdown(note)
                    .font(TypeScale.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Text from `PanelText` that may hold Markdown: `gh` in backticks, a link.
    private func markdown(_ text: String) -> Text {
        Text(LocalizedStringKey(text))
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
            code(text)
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

    /// The code, large, in a card with the copy icon at its end. Clicking
    /// the code copies it too; either way the icon turns into a checkmark,
    /// and the code's hover help says Copied.
    private func code(_ text: PanelText.DeviceCodeScreen) -> some View {
        Button(action: { copy(text.code) }) {
            Text(text.code)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .kerning(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHelp(codeCopied ? text.copied : text.copyCode)
        .accessibilityLabel(text.code)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .overlay(alignment: .trailing) {
            CopyButton(text: text.code, label: text.copyCode, copiedLabel: text.copied, copied: $codeCopied)
                .padding(.trailing, 6)
        }
        .card()
        .onChange(of: text.code) { codeCopied = false }
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
        copy(code)
        shipyard.openVerificationPage()
    }

    private func copy(_ code: String) {
        Clipboard.copy(code)
        withAnimation(.spring(duration: 0.3)) { codeCopied = true }
    }

    private func connectAgain() {
        isTrying = true
        stillSignedOut = false
        Task {
            await shipyard.start()
            isTrying = false
            stillSignedOut = shipyard.phase == .signedOut
        }
    }
}
