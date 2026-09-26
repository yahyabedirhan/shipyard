import ShipyardCore
import SwiftUI

/// Onboarding's first step, shown while `phase` is `needsProjects` and the
/// file holds nothing but `version` (`shipyard.presets` isn't empty): choose
/// a preset. `my-agents` goes on to the `ProjectPicker`;
/// `incoming-contributions` watches all the account's repositories (`owned`)
/// by default, or goes on to the picker; `review-queue` needs nothing. The
/// preset is written by `choosePreset(_:projects:)`, and the menu follows
/// the reload without a restart. The rules live in `PresetChoice`.
struct PresetPicker: View {
    let shipyard: Shipyard

    @State private var choice = PresetChoice()
    @State private var isWriting = false
    @State private var writeError: String?

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

    // MARK: - Choosing

    private var presets: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(PanelText.presetTitle).font(TypeScale.display)
                Text(PanelText.presetIntro)
                    .font(TypeScale.body)
                    .foregroundStyle(.secondary)
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
    }

    /// A preset's title, and under it what it lists.
    private func label(_ preset: Preset) -> some View {
        (Text(preset.title).font(TypeScale.bodyEmphasis)
            + Text("\n" + preset.summary).font(TypeScale.meta).foregroundColor(.secondary))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 2)
    }

    /// `incoming-contributions`: every repository the account owns, or picked ones.
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
                    .font(TypeScale.meta)
                    .foregroundStyle(.secondary)
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
                    .font(TypeScale.caption)
                    .foregroundStyle(Palette.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// On to the picker, or writes the preset now when it needs no repositories.
    private func proceed() {
        guard !isWriting, let preset = choice.preset else { return }
        writeError = nil
        guard choice.proceed() else { return }
        isWriting = true
        Task {
            defer { isWriting = false }
            do {
                // The phase moves to `ready` and the panel swaps this view
                // for the list; a refusal empties `presets`, and the panel
                // shows the plain picker.
                try await shipyard.choosePreset(preset, projects: choice.projects(from: []))
            } catch let error as ConfigError {
                writeError = error.description
            } catch {
                writeError = PanelText.couldNotWrite(error.localizedDescription)
            }
        }
    }
}
