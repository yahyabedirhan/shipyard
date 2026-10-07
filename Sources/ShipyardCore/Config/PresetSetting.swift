import Foundation
import ShipyardConfig

/// When onboarding may write a preset over `config.toml`: the third writer
/// (ADR 0001, amended) replaces the file as a whole, so it only does so
/// while the file holds nothing of the user's (`Configuration.acceptsPreset`,
/// which `ConfigurationStore` records on every reload).
extension Configuration {
    /// Why a preset wasn't written over a file that holds other settings.
    static let presetRefused = ConfigurationError([ConfigurationIssue(
        line: nil,
        message: "config.toml already has settings, so a preset isn't written over it; add projects instead"
    )])
}
