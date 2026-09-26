import Foundation

// Onboarding's preset step's words (`PresetPicker`).
extension PanelText {
    public static let presetTitle = "How will you use Shipyard?"
    public static let presetIntro = "Pick a starting point. It becomes your config.toml, which you and your agents can change at any time."
    /// `incoming-contributions`' two ways to choose its repositories.
    public static let watchOwned = "All my repositories (owned)"
    public static let pickRepositories = "Pick repositories"
    /// Under "All my repositories": what `owned` means.
    public static let watchOwnedDetail = "Every repository your account owns, including ones you create later."
    /// The picker's way back to the presets, after one that needs repositories.
    public static let backToPresets = "Presets"

    /// The preset step's button: on to the picker when the choice still
    /// needs repositories, otherwise "Start with Review queue", which writes it.
    public static func presetContinue(_ choice: PresetChoice) -> String {
        guard let preset = choice.preset else { return "Continue" }
        return choice.needsRepositories ? "Choose repositories" : "Start with \(preset.title)"
    }
}
