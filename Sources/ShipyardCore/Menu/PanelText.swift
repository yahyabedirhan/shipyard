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

    /// A row's second line: "#21 · shipyard · yahyabedirhan · 37m", naming
    /// the repository (without its owner) only when `showingRepository`
    /// (its project has more than one): "#21 · yahyabedirhan · 37m".
    public static func rowDetail(_ row: MenuRow, showingRepository: Bool, now: Date) -> String {
        let repository = showingRepository
            ? [row.repository.split(separator: "/").last.map(String.init) ?? row.repository]
            : []
        return (["#\(row.number)"] + repository + [row.author, age(row.age(at: now))]).joined(separator: " · ")
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

    // MARK: - Notifications

    /// The banner while macOS doesn't let shipyard post notifications.
    public static let notificationsOff = "Notifications are off for shipyard, so it can't tell you when something happens."
    /// Its button, to shipyard's page in System Settings.
    public static let openNotificationSettings = "Open notification settings"

    // MARK: - The rate limit

    /// One API's line in the footer: "GraphQL 4,850 / 5,000 · resets 16:42".
    public static func rateUsage(_ usage: RateUsage, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let numbers = NumberFormatter()
        numbers.locale = locale
        numbers.numberStyle = .decimal
        let count = { (value: Int) in numbers.string(from: NSNumber(value: value)) ?? String(value) }
        return "\(usage.api.name) \(count(usage.remaining)) / \(count(usage.limit)) · resets \(clockTime(usage.resetAt, locale: locale, timeZone: timeZone))"
    }

    /// The banner for a refresh delay that isn't the configured interval:
    /// why it's stretched (to stay within `sharePercent`, `[rate-limit]
    /// max-share-percent`), backed off or paused, and until when; `nil` for
    /// the configured interval or before the first refresh.
    public static func refreshDelay(
        _ delay: RefreshDelay?,
        sharePercent: Int,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String? {
        switch delay {
        case nil, .configured:
            return nil
        case .stretched(let seconds, let api, let cost):
            let cost = Int(cost.rounded())
            let unit = switch api {
            case .graphql: cost == 1 ? "point" : "points"
            case .rest: cost == 1 ? "request" : "requests"
            }
            return "Refreshing every \(interval(seconds)) to stay within \(sharePercent)% of your \(api.name) rate limit (a refresh costs \(cost) \(unit))."
        case .backedOff(let seconds, let api):
            return "Your \(api.name) rate limit is low (other tools are using it). Refreshing every \(interval(seconds))."
        case .paused(let until, let reason):
            let why = switch reason {
            case .exhausted(let api): "\(api.name) rate limit reached"
            case .secondaryLimit: "GitHub asked shipyard to slow down"
            }
            return "\(why) · updates resume at \(clockTime(until, locale: locale, timeZone: timeZone))"
        }
    }

    /// An interval in whole minutes, rounded up: "4 min", "1 h", "1 h 30 min".
    private static func interval(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let (hours, rest) = minutes.quotientAndRemainder(dividingBy: 60)
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return "\(hours) h"
        default: return "\(hours) h \(rest) min"
        }
    }

    /// A time of day the way the user's clock shows it, e.g. "16:42".
    private static func clockTime(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // MARK: - The connect screen

    /// What the connect screen says: a title, what happened and what to do,
    /// the `gh` command to copy, and whether to point at installing `gh`.
    public struct Connect: Equatable, Sendable {
        /// The screen's heading, e.g. "Connect to GitHub".
        public var title: String
        /// What happened and what to do, ending where the command follows.
        public var message: String
        /// The `gh` command to run in a terminal, with a Copy button.
        public var command: String
        /// Whether `gh` may not be installed at all, so the screen shows `installGh`.
        public var suggestsInstallingGh: Bool
    }

    private static let ghLoginCommand = "gh auth login"
    private static let ghLogoutCommand = "gh auth logout"

    /// Where to get `gh`, as Markdown (the link is clickable in the panel).
    public static let installGh = "Get gh at [cli.github.com](https://cli.github.com) or with `brew install gh`."

    /// Shown while `start()` looks for a token, before there's a reason to show.
    public static let connecting = "Connecting to GitHub…"

    /// Said under Try again when it left shipyard signed out, for `reason`
    /// as it stands after the try, so the click doesn't look like it did nothing.
    public static func stillSignedOut(_ reason: Shipyard.SignedOutReason) -> String {
        switch reason {
        case .noToken: "gh still isn't signed in."
        case .rejected(.gh): "GitHub still rejects gh's token."
        case .rejected(.tokenStore): "GitHub still rejects the token."
        case .signedOut: "Still not connected."
        }
    }

    /// The connect screen for why shipyard is signed out. 0.0.x connects
    /// through `gh` only, so every way back in is `gh auth login`.
    public static func connect(_ reason: Shipyard.SignedOutReason) -> Connect {
        switch reason {
        case .noToken:
            Connect(
                title: "Connect to GitHub",
                message: "Shipyard connects to GitHub through the GitHub CLI, gh. Install it, then sign in with it in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: true
            )
        case .rejected(let source):
            Connect(
                title: source == .gh ? "GitHub rejected gh's token" : "GitHub rejected shipyard's token",
                message: "It was revoked or has expired. Sign in to gh again in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: false
            )
        case .signedOut(.ghStillSignedIn):
            Connect(
                title: "Signed out",
                message: "gh is still signed in, so Try again, or the next launch, connects again. To disconnect for good, sign gh out in a terminal:",
                command: ghLogoutCommand,
                suggestsInstallingGh: false
            )
        case .signedOut(.signedOut):
            Connect(
                title: "Signed out",
                message: "To connect again, sign in to gh in a terminal:",
                command: ghLoginCommand,
                suggestsInstallingGh: false
            )
        }
    }
}
