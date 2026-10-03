import ShipyardCore
import SwiftUI

/// Onboarding's connect step. Signed out, it greets the user, says what
/// happened in a line or two, and stacks the ways in as full-width buttons
/// in the order `PanelText.Connect.lead` gives, the main one prominent:
/// Sign in with GitHub (the device flow) with the `gh` way folded in a
/// disclosure under it; or the `gh auth login` box over Connect with gh,
/// then Sign in with GitHub; or Connect with gh, when `gh` is signed in
/// already, then a divider and Sign in with GitHub under a line of its
/// own. Connect with gh looks for a token once more (`start()`). A build
/// without an OAuth App client ID shows Sign in with GitHub disabled, with
/// why (or not at all when `gh` is signed in), and `gh` leads. While the
/// device flow waits (`connecting`) it shows the code (a click on it, or on
/// its copy icon, copies it), a button that copies it and opens
/// github.com/login/device, and Cancel. The words come from
/// `PanelText.connect` and `PanelText.deviceCode`; `gh` in them is set in
/// code font on a chip (`CodeText`).
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
    @State private var codeCopiedAt: Date?

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

    /// Every state has one shape: the greeting, a line or two on what
    /// happened, then the ways in as full-width buttons stacked in the
    /// order `lead` gives, the main one prominent. When Sign in with GitHub
    /// leads, the `gh` way folds into a disclosure under it.
    private func screen(_ text: PanelText.Connect) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            heading(text.title)
            line(text.message)
                .padding(.bottom, 16)
            VStack(alignment: .leading, spacing: 8) {
                switch text.lead {
                case .signIn:
                    signIn(prominent: true, unavailable: text.signInUnavailable)
                    DisclosureGroup(isExpanded: $showsGh) {
                        ghWay(prominent: false, installHint: true)
                            .padding(.top, 8)
                    } label: {
                        markdown(PanelText.useGhInstead, size: 12)
                            .foregroundStyle(.secondary)
                            .hoverHelp(markdown: PanelText.useGhInsteadHelp)
                    }
                    .padding(.top, 4)
                case .ghCommand:
                    ghWay(prominent: true, installHint: text.showsInstallHint)
                    signIn(prominent: false, unavailable: text.signInUnavailable)
                case .connectWithGh:
                    connectWithGh(prominent: true)
                    if let alternative = text.alternative {
                        Divider()
                            .padding(.vertical, 8)
                        line(alternative)
                            .padding(.bottom, 8)
                        signIn(prominent: false, unavailable: text.signInUnavailable)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// A line of the screen's words, over the buttons it leads to.
    private func line(_ text: String) -> some View {
        markdown(text, size: 12)
            .foregroundStyle(.secondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The `gh auth login` box, with the install hint beside it, over
    /// Connect with gh.
    private func ghWay(prominent: Bool, installHint: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                CommandBox(command: PanelText.ghLogin)
                if installHint { installHintButton }
            }
            connectWithGh(prominent: prominent)
        }
    }

    /// Looks for a token once more (`start()`), full width, and under it
    /// why the last try found nothing. Never the default action: after
    /// signing out of `gh`'s token, Return would connect straight back.
    private func connectWithGh(prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: connectAgain) {
                HStack(spacing: 6) {
                    if isTrying { ProgressView().controlSize(.mini) }
                    markdown(PanelText.connectWithGh, size: 12, weight: .medium)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(prominent: prominent, height: Self.actionHeight))
            .disabled(isTrying || isRequestingCode)
            if stillSignedOut, !isTrying, let reason = shipyard.signedOutReason {
                note(PanelText.stillSignedOut(reason))
            }
        }
    }

    /// The ⓘ beside the `gh` command: a popover with where to get `gh`,
    /// and the Homebrew command to copy.
    private var installHintButton: some View {
        Button { showsInstallHint.toggle() } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(IconButtonStyle())
        .hoverHelp(markdown: PanelText.installGhHelp)
        .accessibilityLabel(PanelText.installGhHelp.replacingOccurrences(of: "`", with: ""))
        .popover(isPresented: $showsInstallHint, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                markdown(PanelText.installGh, size: 12)
                    .tint(Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                CommandBox(command: PanelText.brewInstallGh)
            }
            .padding(12)
            .frame(width: 260)
        }
    }

    /// The height of the screen's stacked, full-width buttons.
    private static let actionHeight: CGFloat = 28

    /// Sign in with GitHub, full width, and under it why the last one
    /// failed, or why the build can't offer it.
    private func signIn(prominent: Bool, unavailable: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: beginSignIn) {
                HStack(spacing: 6) {
                    if isRequestingCode { ProgressView().controlSize(.mini) }
                    Text(PanelText.signInWithGitHub)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PillButtonStyle(prominent: prominent && unavailable == nil, height: Self.actionHeight))
            .disabled(unavailable != nil || isRequestingCode || isTrying)
            if let reason = unavailable ?? shipyard.signInError.map(PanelText.signInFailed) {
                note(reason)
            }
        }
    }

    private func note(_ text: String) -> some View {
        markdown(text, size: 10.5)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Text from `PanelText` that may hold Markdown (`gh` in backticks, a
    /// link), `size` points, with its code spans as code (`CodeText`).
    private func markdown(_ text: String, size: CGFloat, weight: Font.Weight = .regular) -> Text {
        Text(markdown: text, size: size, weight: weight)
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

    /// The code, large, in a card with the copy icon and its word ("Copy")
    /// at its end. Clicking the code copies it too; either way the icon
    /// turns into a checkmark and the word rolls to "Copied", the only
    /// feedback: the code has no hover help.
    private func code(_ text: PanelText.DeviceCodeScreen) -> some View {
        Button(action: { copy(text.code) }) {
            Text(text.code)
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .kerning(2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text.code)
        .accessibilityHint(codeCopiedAt != nil ? text.copied : text.copyCode)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .overlay(alignment: .trailing) {
            CopyButton(
                text: text.code,
                label: text.copyCode,
                copiedLabel: text.copied,
                title: text.copyTitle,
                copiedTitle: text.copied,
                copiedAt: $codeCopiedAt
            )
            .padding(.trailing, 6)
        }
        .card()
        .onChange(of: text.code) { codeCopiedAt = nil }
    }

    private func heading(_ title: String) -> some View {
        HStack(spacing: 10) {
            LogoBadge(side: 32)
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
        CopyButton.copied($codeCopiedAt)
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
