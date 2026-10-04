import ShipyardCore
import SwiftUI

/// Takes the Notion token the notes are read with: a secure field and
/// Connect, which checks it with Notion and keeps it in the Keychain
/// (`Shipyard.connectNotion`), then says how that went. The header's
/// "Connect Notion…" shows it above the footer, shaped like `CLILinkCard`;
/// it closes itself once connected. The token never leaves the field but
/// for the Keychain.
struct NotionConnectCard: View {
    let shipyard: Shipyard
    let close: () -> Void

    @State private var token = ""
    @State private var isConnecting = false
    @State private var result: NotionConnection?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "note.text")
                    .foregroundStyle(Palette.accent)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .semibold))
                Text(PanelText.notionCardTitle).font(TypeScale.bodyEmphasis)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle())
                .accessibilityLabel("Close")
            }
            .frame(minHeight: 22)
            Text(PanelText.notionCardMessage)
                .font(TypeScale.body)
                .foregroundStyle(.secondary)
                .lineSpacing(1.5)
                .fixedSize(horizontal: false, vertical: true)
            SecureField(PanelText.notionTokenPlaceholder, text: $token)
                .textFieldStyle(.roundedBorder)
                .onSubmit(connect)
            if let result {
                Text(PanelText.notionConnection(result))
                    .font(TypeScale.caption)
                    .foregroundStyle(result == .connected ? AnyShapeStyle(Palette.green) : AnyShapeStyle(Palette.red))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                if isConnecting { ProgressView().controlSize(.mini) }
                Button(PanelText.notionConnect, action: connect)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(isConnecting)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func connect() {
        guard !isConnecting else { return }
        isConnecting = true
        let pasted = token
        Task {
            let outcome = await shipyard.connectNotion(token: pasted)
            isConnecting = false
            result = outcome
            if outcome == .connected {
                token = ""
                close()
            }
        }
    }
}
