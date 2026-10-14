import Foundation
import ShipyardConfig

extension Configuration {
    static let presetRefused = ConfigurationError([ConfigurationIssue(
        line: nil,
        message: "config.toml already has settings, so a preset isn't written over it; add projects instead"
    )])
}
