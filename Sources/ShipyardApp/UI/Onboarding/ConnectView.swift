import ShipyardCore
import SwiftUI

struct ConnectView: View {
    let shipyard: Shipyard

    @State private var shown: Shipyard.SignedOutReason?
    @State private var isTrying = false
    @State private var isRequestingCode = false
    @State private var stillSignedOut = false
    @State private var showsGh = false
    @State private var showsInstallHint = false
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

    private func line(_ text: String) -> some View {
        markdown(text, size: 12)
            .foregroundStyle(.secondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func ghWay(prominent: Bool, installHint: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                CommandBox(command: PanelText.ghLogin)
                if installHint { installHintButton }
            }
            connectWithGh(prominent: prominent)
        }
    }

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

    private static let actionHeight: CGFloat = 28

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

    private func markdown(_ text: String, size: CGFloat, weight: Font.Weight = .regular) -> Text {
        Text(markdown: text, size: size, weight: weight)
    }

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

    private func beginSignIn() {
        isRequestingCode = true
        stillSignedOut = false
        let flow = shipyard.beginDeviceFlow()
        Task {
            await flow.value
            isRequestingCode = false
        }
    }

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
