import Foundation

/// The words the panel shows for what the menu model and the orchestrator
/// hold: a row's age, when the list was last updated, and why the
/// configuration or a refresh failed. Pure, so tests reach them without SwiftUI.
///
/// This file holds the words of the menu itself (header, rows, tabs,
/// banners, rate limit); each onboarding screen and the skill install card
/// have their own `PanelText+…` file next to it.
public enum PanelText {
    /// The panel's heading until the account is known.
    public static let title = "Shipyard"

    /// The panel's heading: the signed-in account's handle, "@yabepa"
    /// (beside its avatar), or `title` while the account isn't known
    /// (connecting, signed out, GitHub out of reach at sign-in).
    public static func title(for viewer: Viewer?) -> String {
        viewer.map { "@\($0.login)" } ?? title
    }

    /// The account's hover text: its full name when it has one, and what a
    /// click does. "Mona Lisa (@octocat) · Open profile on GitHub".
    public static func profileHelp(_ viewer: Viewer) -> String {
        let handle = "@\(viewer.login)"
        let name = viewer.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let who = name.isEmpty ? handle : "\(name) (\(handle))"
        return "\(who) · Open profile on GitHub"
    }

    /// VoiceOver's label for the account button: "Open @octocat's profile on GitHub".
    public static func profileAccessibilityLabel(_ viewer: Viewer) -> String {
        "Open @\(viewer.login)'s profile on GitHub"
    }

    /// The header's layout button, as its tooltip and VoiceOver label: the
    /// layout shown and the one a click switches to. "Layout: list. Click for tabs."
    public static func layoutButton(_ current: MenuLayout) -> String {
        "Layout: \(current.rawValue). Click for \(current.next.rawValue)."
    }

    /// Next to the heading: "3 need attention"; `nil` when nothing does.
    public static func attentionSummary(_ count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: "1 needs attention"
        default: "\(count) need attention"
        }
    }

    /// A row's age: "now" under a minute, then "5m", "3h", "2d".
    public static func age(_ seconds: TimeInterval) -> String {
        guard let (count, unit) = span(seconds) else { return "now" }
        return "\(count)\(unit.prefix(1))"
    }

    /// A row's second line: "#21 · shipyard · yahyabedirhan · 37m", naming
    /// the repository (without its owner) only when `showingRepository`
    /// (its project has more than one): "#21 · yahyabedirhan · 37m". An
    /// issue reads the same. A workflow run (whose first line is its
    /// workflow's name) names its branch and state instead of its author:
    /// "#41 · shipyard · main · failed · 12m", aged from its start while
    /// running and from its finish after.
    public static func rowDetail(_ row: MenuRow, showingRepository: Bool, now: Date) -> String {
        (detailParts(row, showingRepository: showingRepository) + [age(row.age(at: now))]).joined(separator: " · ")
    }

    /// The same second line without the age, for a layout that shows the
    /// age apart, aligned on the right: "#21 · shipyard · yahyabedirhan".
    public static func rowDetail(_ row: MenuRow, showingRepository: Bool) -> String {
        detailParts(row, showingRepository: showingRepository).joined(separator: " · ")
    }

    private static func detailParts(_ row: MenuRow, showingRepository: Bool) -> [String] {
        let repository = showingRepository ? [repositoryName(row.repository)] : []
        let subject: [String] = switch row.kind {
        case .pullRequest, .issue: [row.author]
        case .workflowRun: (row.branch.map { [$0] } ?? []) + [state(row.state)]
        }
        return ["#\(row.number)"] + repository + subject
    }

    /// A repository without its owner: "shipyard" for "yahyabedirhan/shipyard".
    public static func repositoryName(_ repository: String) -> String {
        repository.split(separator: "/").last.map(String.init) ?? repository
    }

    /// A row's tooltip, in either layout: its state and its full second
    /// line, then, while it needs attention, the ⌥-click hint.
    public static func rowHelp(_ row: MenuRow, showingRepository: Bool, now: Date) -> String {
        let detail = "\(stateLabel(row)) · \(rowDetail(row, showingRepository: showingRepository, now: now))"
        return row.needsAttention ? "\(detail)\n\(optionClickHint)" : detail
    }

    /// The button that marks everything it covers seen: the footer's for
    /// every project, a list section's (on hover) for that project, and the
    /// All tab's.
    public static let markAllSeen = "Mark all seen"
    /// A row's action for ⌥-click's keyboard and VoiceOver equivalent.
    public static let markRowSeen = "Mark seen"
    /// Said in a row's tooltip, under its detail, while it needs attention.
    public static let optionClickHint = "⌥-click to mark seen"
    /// What the attention dot says to VoiceOver.
    public static let needsAttention = "Needs attention"

    /// What a pull request's check dot means, for its tooltip; `nil` with no checks.
    public static func checks(_ checks: ChecksState) -> String? {
        switch checks {
        case .none: nil
        case .pending: "Checks running"
        case .passed: "Checks passed"
        case .failed: "Checks failed"
        }
    }

    /// What the row's state icon says to VoiceOver: its state and kind,
    /// "open pull request", "closed issue", "failed workflow run".
    public static func stateLabel(_ row: MenuRow) -> String {
        let kind = switch row.kind {
        case .pullRequest: "pull request"
        case .issue: "issue"
        case .workflowRun: "workflow run"
        }
        return "\(state(row.state)) \(kind)"
    }

    /// A state in a word: "open", "merged", "running", "failed"…, for a
    /// run's second line and the state icon's label.
    public static func state(_ state: ItemState) -> String {
        switch state {
        case .open: "open"
        case .draft: "draft"
        case .merged: "merged"
        case .closed: "closed"
        case .running: "running"
        case .succeeded: "succeeded"
        case .failed: "failed"
        }
    }

    /// What a section with no rows and no error rows says in their place:
    /// "Not loaded yet" before the first refresh succeeded, else "Nothing
    /// open"; `nil` when it has something to list.
    public static func emptySection(_ section: MenuSection) -> String? {
        if !section.isLoaded { return "Not loaded yet" }
        return section.rows.isEmpty && section.errors.isEmpty ? "Nothing open" : nil
    }

    // MARK: - The tabs layout

    /// A tab's title: "All", or its project's name.
    public static func tabTitle(_ tab: MenuTab) -> String {
        switch tab {
        case .all: "All"
        case .project(let name): name
        }
    }

    /// The line under the tab strip: "5 need attention · 4 projects" on
    /// All, "2 need attention" on a project's tab, and "All caught up" in
    /// place of the count when nothing needs attention.
    public static func tabSummary(attention: Int, projects: Int, tab: MenuTab) -> String {
        let count = switch attention {
        case 0: "All caught up"
        case 1: "1 needs attention"
        default: "\(attention) need attention"
        }
        guard tab == .all else { return count }
        return "\(count) · \(projects) \(projects == 1 ? "project" : "projects")"
    }

    /// The button next to that line: All marks every project seen, a
    /// project's tab only that project.
    public static func markTabSeen(_ tab: MenuTab) -> String {
        tab == .all ? markAllSeen : markRowSeen
    }

    /// What a tab with no rows and no error rows says in their place, as
    /// `emptySection` does for a section; `nil` when it has something to list.
    public static func emptyTab(_ content: MenuTabContent) -> String? {
        guard content.groups.isEmpty, content.errors.isEmpty else { return nil }
        return content.isLoaded ? "Nothing open" : "Not loaded yet"
    }

    /// The small header over a kind's rows in a tab.
    public static func kindGroup(_ kind: ItemKind) -> String {
        switch kind {
        case .pullRequest: "Pull requests"
        case .issue: "Issues"
        case .workflowRun: "Runs"
        }
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
        (error.issues.map(configIssue) + ["Using the last valid configuration."]).joined(separator: "\n")
    }

    /// One problem's line in a configuration banner:
    /// "config.toml line 14: unknown event `pr.openned` …", or without the
    /// line when it can't be placed. `config-status.json` repeats it.
    public static func configIssue(_ issue: ConfigIssue) -> String {
        issue.line.map { "config.toml line \($0): \(issue.message)" } ?? "config.toml: \(issue.message)"
    }

    /// The quiet banner for settings the file has but shipyard ignores, each
    /// with its line; `nil` when there are none.
    public static func configWarnings(_ warnings: [ConfigIssue]) -> String? {
        guard !warnings.isEmpty else { return nil }
        return warnings.map(configIssue).joined(separator: "\n")
    }

    /// Why the latest refresh failed, for the banner above the kept rows.
    public static func fetchError(_ error: GitHubError) -> String {
        switch error {
        case .unauthorized: "GitHub rejected the token."
        case .http(let status): "GitHub answered with HTTP \(status)."
        // The system's own text names an error domain and code; say it plainly.
        case .network: "Can't reach GitHub. Check your connection. Shipyard will try again."
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
    static func interval(_ seconds: TimeInterval) -> String {
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
}
