import ShipyardConfig
import ShipyardCore
import SwiftUI

struct PresetPicker: View {
    let shipyard: Shipyard

    @State private var choice = PresetChoice()
    @State private var isWriting = false
    @State private var writeError: String?
    @Environment(\.panelScale) private var scale

    var body: some View {
        switch choice.step {
        case .preset:
            presets
        case .repositories:
            if let preset = choice.preset {
                ProjectPicker(
                    shipyard: shipyard,
                    preset: preset,
                    add: { try await shipyard.choosePreset(preset, projects: choice.projects(from: $0)) },
                    back: { choice.back() }
                )
            }
        }
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PanelText.presetTitle).font(scale.type.display)
                Text(PanelText.presetIntro)
                    .font(scale.type.body)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker(PanelText.presetTitle, selection: $choice.preset) {
                ForEach(shipyard.presets) { preset in
                    label(preset).tag(Optional(preset))
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if choice.offersOwned {
                repositoriesChoice
                    .padding(.leading, 20)
            }
            footer
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedScreen()
    }

    private func label(_ preset: Preset) -> some View {
        (Text(preset.title).font(scale.type.bodyEmphasis)
            + Text("\n" + preset.summary).font(scale.type.meta).foregroundStyle(ThemeColor.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
    }

    private var repositoriesChoice: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker(PanelText.watchOwned, selection: $choice.watchesOwned) {
                Text(PanelText.watchOwned).tag(true)
                Text(PanelText.pickRepositories).tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if choice.watchesOwned {
                Text(PanelText.watchOwnedDetail)
                    .font(scale.type.meta)
                    .foregroundStyle(ThemeColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Spacer()
                if isWriting {
                    ProgressView().controlSize(.small)
                }
                Button(PanelText.presetContinue(choice), action: proceed)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!choice.canContinue || isWriting)
            }
            if let writeError {
                Text(writeError)
                    .font(scale.type.caption)
                    .foregroundStyle(ThemeColor.failed)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func proceed() {
        guard !isWriting, let preset = choice.preset else { return }
        writeError = nil
        guard choice.proceed() else { return }
        isWriting = true
        Task {
            defer { isWriting = false }
            do {
                try await shipyard.choosePreset(preset, projects: choice.projects(from: []))
            } catch let error as ConfigurationError {
                writeError = error.description
            } catch {
                writeError = PanelText.couldNotWrite(error.localizedDescription)
            }
        }
    }
}
