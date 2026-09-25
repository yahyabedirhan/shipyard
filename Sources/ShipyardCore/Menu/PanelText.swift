import Foundation

/// The words the panel shows for what the menu model and the orchestrator
/// hold: a row's age, when the list was last updated, and why the
/// configuration or a refresh failed. Pure, so tests reach them without SwiftUI.
public enum PanelText {
    /// The panel's heading.
    public static let title = "Shipyard"

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
        let repository = showingRepository
            ? [row.repository.split(separator: "/").last.map(String.init) ?? row.repository]
            : []
        let subject: [String] = switch row.kind {
        case .pullRequest, .issue: [row.author]
        case .workflowRun: (row.branch.map { [$0] } ?? []) + [state(row.state)]
        }
        return (["#\(row.number)"] + repository + subject + [age(row.age(at: now))]).joined(separator: " · ")
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

    // MARK: - The project picker

    public static let pickerTitle = "Pick your projects"
    public static let pickerIntro = "Each repository you choose is a project, one section in the list. Give several the same project name to group them into one."
    /// The field for a repository that isn't suggested.
    public static let typeRepository = "owner/name or a github.com link"
    public static let findingSuggestions = "Finding the repositories you worked on recently…"
    public static let noSuggestions = "You haven't pushed to any repository lately. Add one by name above."
    /// Said while a chosen repository's project name is empty; Add waits for it.
    public static let unnamedProject = "Give every project a name."
    /// Said when Add wrote the projects but the file around them doesn't load.
    public static let addedToBrokenFile = "Added to config.toml, but the file has an error (see above). Shipyard picks the projects up once it's fixed."

    /// Why the suggestions didn't load; typing a repository still works.
    public static func suggestionsFailed(_ error: GitHubError) -> String {
        "Couldn't load suggestions: \(fetchError(error))"
    }

    /// Why Add couldn't write the file.
    public static func couldNotWrite(_ reason: String) -> String {
        "Couldn't write config.toml: \(reason)"
    }

    /// The picker's confirm button: "Add 2 projects".
    public static func addProjects(_ count: Int) -> String {
        switch count {
        case 0: "Add projects"
        case 1: "Add 1 project"
        default: "Add \(count) projects"
        }
    }

    /// What Add writes, above its button: "Adds e-commerce (2 repositories),
    /// job-search"; `nil` while nothing is chosen.
    public static func pickedProjects(_ projects: [NewProject]) -> String? {
        guard !projects.isEmpty else { return nil }
        let names = projects.map { project in
            project.repositories.count > 1 ? "\(project.name) (\(project.repositories.count) repositories)" : project.name
        }
        return "Adds " + names.joined(separator: ", ")
    }

    // MARK: - The agent skill

    /// What the skill install card says: a title, what happened or what to
    /// do, the command's output, the command to copy, and its button.
    public struct SkillInstall: Equatable, Sendable {
        /// The card's button: Install, Cancel (while running) or Try again.
        public enum Action: Equatable, Sendable {
            case install, cancel, tryAgain
        }

        /// The card's icon: the offer, a success or a problem.
        public enum Tone: Equatable, Sendable {
            case neutral, success, warning
        }

        /// The card's heading.
        public var title: String
        /// What happened or what to do.
        public var message: String
        /// What the command printed, when it's worth showing.
        public var output: String?
        /// `SkillInstaller.command`, with a Copy button, when running it by hand helps.
        public var command: String?
        /// The card's button, if any.
        public var action: Action?
        public var tone: Tone = .neutral
    }

    /// The footer's button for the skill install card.
    public static let installSkill = "Install agent skill…"

    /// The skill install card for `state`.
    public static func skillInstall(_ state: SkillInstallation.State) -> SkillInstall {
        let command = SkillInstaller.command
        switch state {
        case .idle:
            return SkillInstall(
                title: "Install the agent skill",
                message: "It teaches your agents shipyard's configuration file, so you can ask one to watch a repository for you. Shipyard runs this in your login shell:",
                command: command,
                action: .install
            )
        case .running:
            return SkillInstall(
                title: "Installing the agent skill…",
                message: "Running npx in your login shell. It can take a minute.",
                action: .cancel
            )
        case .finished(.installed(let output)):
            return SkillInstall(
                title: "Agent skill installed",
                message: "Your agents can now edit shipyard's configuration file for you.",
                output: output.isEmpty ? nil : output,
                tone: .success
            )
        case .finished(.failed(let output)):
            return SkillInstall(
                title: "Couldn't install the agent skill",
                message: "The command failed. Try again, or run it in a terminal:",
                output: output,
                command: command,
                action: .tryAgain,
                tone: .warning
            )
        case .finished(.npxNotFound(let command)):
            return SkillInstall(
                title: "npx wasn't found",
                message: "Shipyard couldn't find npx (it comes with Node.js) in your login shell. Run this in a terminal instead:",
                command: command,
                action: .tryAgain,
                tone: .warning
            )
        case .timedOut(let seconds):
            return SkillInstall(
                title: "The install took too long",
                message: "It was stopped after \(interval(seconds)). Try again, or run it in a terminal:",
                command: command,
                action: .tryAgain,
                tone: .warning
            )
        }
    }
}
