import Foundation

/// When onboarding may write a preset over `config.toml`: the third writer
/// (ADR 0001, amended) replaces the file as a whole, so it only does so
/// while the file holds nothing of the user's.
extension Configuration {
    /// Whether a preset may replace `text`: it reads, and its only live key
    /// is `version`, as in the commented header the app creates. Comments
    /// and blank lines don't count; any table, even an empty one, does.
    static func acceptsPreset(_ text: String) -> Bool {
        guard (try? decode(text)) != nil else { return false }
        return TOMLSourceMap(text).entries.allSatisfy { !$0.isHeader && $0.path == [.key("version")] }
    }

    /// Why a preset wasn't written over a file that holds other settings.
    static let presetRefused = ConfigError([ConfigIssue(
        line: nil,
        message: "config.toml already has settings, so a preset isn't written over it; add projects instead"
    )])
}
