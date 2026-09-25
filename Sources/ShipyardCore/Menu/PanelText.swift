import Foundation

/// The words the panel shows for what the menu model and the orchestrator
/// hold: a row's age, when the list was last updated, and why the
/// configuration or a refresh failed. Pure, so tests reach them without SwiftUI.
public enum PanelText {
    /// A row's age: "now" under a minute, then "5m", "3h", "2d".
    public static func age(_ seconds: TimeInterval) -> String {
        guard let (count, unit) = span(seconds) else { return "now" }
        return "\(count)\(unit.prefix(1))"
    }

    /// "Last updated 5 min ago" for rows fetched at `date`; `nil` before
    /// the first refresh succeeded.
    public static func lastUpdated(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        guard let (count, unit) = span(now.timeIntervalSince(date)) else { return "Last updated just now" }
        return "Last updated \(count) \(unit) ago"
    }

    /// `seconds` in whole minutes, hours or days (the largest that fits);
    /// `nil` under a minute, or when it's negative (a clock that went back).
    private static func span(_ seconds: TimeInterval) -> (count: Int, unit: String)? {
        switch seconds {
        case ..<60: nil
        case ..<3600: (Int(seconds / 60), "min")
        case ..<86_400: (Int(seconds / 3600), "h")
        default: (Int(seconds / 86_400), "d")
        }
    }

    /// The banner for a rejected configuration file: each problem with its
    /// line, then that the last valid configuration is still in use.
    public static func configError(_ error: ConfigError) -> String {
        let lines = error.issues.map { issue in
            issue.line.map { "config.toml line \($0): \(issue.message)" } ?? "config.toml: \(issue.message)"
        }
        return (lines + ["Using the last valid configuration."]).joined(separator: "\n")
    }

    /// Why the latest refresh failed, for the banner above the kept rows.
    public static func fetchError(_ error: GitHubError) -> String {
        switch error {
        case .unauthorized: "GitHub rejected the token."
        case .http(let status): "GitHub answered with HTTP \(status)."
        case .network(let message): "Couldn't reach GitHub: \(message)"
        case .malformed: "GitHub's answer couldn't be read."
        case .graphQL(let message): "GitHub: \(message)"
        case .rateLimited(_, let api): "The \(api.name) rate limit ran out."
        case .secondaryLimit: "GitHub asked shipyard to slow down."
        }
    }
}
