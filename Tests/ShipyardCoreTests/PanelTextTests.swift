import Foundation
@testable import ShipyardCore
import Testing

@Suite("Panel text")
struct PanelTextTests {
    private let now = Date(timeIntervalSince1970: 1_790_337_600)

    @Test("a row's age is short: now, minutes, hours, days", arguments: [
        (0.0, "now"),
        (59, "now"),
        (60, "1m"),
        (59 * 60 + 59, "59m"),
        (3600, "1h"),
        (23 * 3600 + 3599, "23h"),
        (86_400, "1d"),
        (40 * 86_400, "40d"),
    ] as [(TimeInterval, String)])
    func age(seconds: TimeInterval, text: String) {
        #expect(PanelText.age(seconds) == text)
    }

    @Test("last updated counts minutes, then hours, then days; nothing before the first refresh")
    func lastUpdated() {
        #expect(PanelText.lastUpdated(nil, now: now) == nil)
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-30), now: now) == "Last updated just now")
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-60), now: now) == "Last updated 1 min ago")
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-5 * 60 - 10), now: now) == "Last updated 5 min ago")
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-2 * 3600), now: now) == "Last updated 2 h ago")
        #expect(PanelText.lastUpdated(now.addingTimeInterval(-3 * 86_400), now: now) == "Last updated 3 d ago")
        // A clock that went back doesn't say "in the future".
        #expect(PanelText.lastUpdated(now.addingTimeInterval(60), now: now) == "Last updated just now")
    }

    @Test("a configuration error names the file and line, and says the last valid one is used")
    func configError() {
        let error = ConfigError([
            ConfigIssue(line: 14, message: "unknown event `pr.openned` (did you mean `pr.opened`?)"),
            ConfigIssue(line: nil, message: "can't read the file"),
        ])

        #expect(PanelText.configError(error) == """
            config.toml line 14: unknown event `pr.openned` (did you mean `pr.opened`?)
            config.toml: can't read the file
            Using the last valid configuration.
            """)
    }

    @Test("with notifications turned off, the banner says so and where to turn them on")
    func notificationsOff() {
        #expect(PanelText.notificationsOff == "Notifications are off for shipyard, so it can't tell you when something happens.")
        #expect(PanelText.openNotificationSettings == "Open notification settings")
    }

    @Test("a failed refresh says why", arguments: [
        (GitHubError.network("The operation couldn’t be completed. (NSURLErrorDomain error -1009.)"),
         "Can't reach GitHub. Check your connection. Shipyard will try again."),
        (.http(502), "GitHub answered with HTTP 502."),
        (.malformed, "GitHub's answer couldn't be read."),
        (.graphQL("Something went wrong"), "GitHub: Something went wrong"),
        (.unauthorized, "GitHub rejected the token."),
        (.rateLimited(resetAt: Date(timeIntervalSince1970: 0), api: .graphql), "The GraphQL rate limit ran out."),
        (.secondaryLimit(retryAfter: 60), "GitHub asked shipyard to slow down."),
    ] as [(GitHubError, String)])
    func fetchError(error: GitHubError, text: String) {
        #expect(PanelText.fetchError(error) == text)
    }

    @Test("a section with nothing to list says why: not loaded yet, or nothing open")
    func emptySection() {
        #expect(PanelText.emptySection(MenuSection(name: "a", rows: [], isLoaded: false)) == "Not loaded yet")
        #expect(PanelText.emptySection(MenuSection(name: "a", rows: [])) == "Nothing open")
        let error = MenuErrorRow(RepositoryError(repository: "o/gone", kind: .notFound, message: ""))
        #expect(PanelText.emptySection(MenuSection(name: "a", rows: [], errors: [error])) == nil)
    }

    // MARK: - Rows

    private func row(repository: String = "yahyabedirhan/shipyard", number: Int = 21, author: String = "yahyabedirhan") -> MenuRow {
        MenuRow(Item(
            kind: .pullRequest,
            repository: repository,
            number: number,
            title: "Attention in the panel",
            url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
            author: author,
            authorKind: .me,
            state: .open,
            createdAt: now.addingTimeInterval(-37 * 60),
            updatedAt: now.addingTimeInterval(-37 * 60)
        ))
    }

    @Test("a row's second line names the repository only in a project with more than one")
    func rowDetail() {
        #expect(PanelText.rowDetail(row(), showingRepository: true, now: now) == "#21 · shipyard · yahyabedirhan · 37m")
        #expect(PanelText.rowDetail(row(), showingRepository: false, now: now) == "#21 · yahyabedirhan · 37m")
    }

    private func issue(state: ItemState) -> MenuRow {
        MenuRow(Item(
            kind: .issue,
            repository: "yahyabedirhan/shipyard",
            number: 17,
            title: "Issues and workflow runs in the panel",
            url: URL(string: "https://github.com/yahyabedirhan/shipyard/issues/17")!,
            author: "octocat",
            authorKind: .other,
            state: state,
            createdAt: now.addingTimeInterval(-3 * 86_400),
            updatedAt: now.addingTimeInterval(-3600),
            closedAt: state == .closed ? now.addingTimeInterval(-2 * 3600) : nil
        ))
    }

    @Test("an issue's second line reads like a pull request's")
    func issueDetail() {
        #expect(PanelText.rowDetail(issue(state: .open), showingRepository: false, now: now) == "#17 · octocat · 3d")
        #expect(PanelText.rowDetail(issue(state: .open), showingRepository: true, now: now) == "#17 · shipyard · octocat · 3d")
        #expect(PanelText.rowDetail(issue(state: .closed), showingRepository: false, now: now) == "#17 · octocat · 2h")
    }

    private func run(state: ItemState, branch: String? = "main") -> MenuRow {
        MenuRow(Item(
            kind: .workflowRun,
            repository: "yahyabedirhan/shipyard",
            number: 41,
            title: "CI",
            url: URL(string: "https://github.com/yahyabedirhan/shipyard/actions/runs/9001")!,
            author: "yahyabedirhan",
            authorKind: .me,
            state: state,
            createdAt: now.addingTimeInterval(-20 * 60),
            updatedAt: now.addingTimeInterval(-12 * 60),
            closedAt: state == .running ? nil : now.addingTimeInterval(-12 * 60),
            branch: branch
        ))
    }

    @Test("a run's second line names its branch and state, and ages from its start or finish", arguments: [
        (ItemState.running, "#41 · main · running · 20m"),
        (.succeeded, "#41 · main · succeeded · 12m"),
        (.failed, "#41 · main · failed · 12m"),
    ])
    func runDetail(state: ItemState, text: String) {
        #expect(PanelText.rowDetail(run(state: state), showingRepository: false, now: now) == text)
    }

    @Test("a run's second line names the repository only in a project with more than one, and leaves out a missing branch")
    func runDetailRepository() {
        #expect(PanelText.rowDetail(run(state: .failed), showingRepository: true, now: now) == "#41 · shipyard · main · failed · 12m")
        #expect(PanelText.rowDetail(run(state: .failed, branch: nil), showingRepository: false, now: now) == "#41 · failed · 12m")
    }

    @Test("the state icon reads as the state and the kind, so VoiceOver tells an issue from a pull request")
    func stateLabel() {
        #expect(PanelText.stateLabel(row()) == "open pull request")
        #expect(PanelText.stateLabel(issue(state: .closed)) == "closed issue")
        #expect(PanelText.stateLabel(run(state: .failed)) == "failed workflow run")
    }

    @Test("each state has a word, for a run's second line and the state icon's label", arguments: [
        (ItemState.open, "open"),
        (.draft, "draft"),
        (.merged, "merged"),
        (.closed, "closed"),
        (.running, "running"),
        (.succeeded, "succeeded"),
        (.failed, "failed"),
    ])
    func stateName(state: ItemState, text: String) {
        #expect(PanelText.state(state) == text)
    }

    // MARK: - The rate limit

    private let london = TimeZone(identifier: "Europe/London")!
    private let british = Locale(identifier: "en_GB")
    /// 12:42 UTC, 13:42 in London (summer time).
    private var reset: Date { now.addingTimeInterval(42 * 60) }

    @Test("the footer's rate-limit line: remaining / limit per API and when it resets")
    func rateUsage() {
        let usage = RateUsage(api: .graphql, remaining: 4850, limit: 5000, resetAt: reset, level: .normal)
        #expect(PanelText.rateUsage(usage, locale: british, timeZone: london) == "GraphQL 4,850 / 5,000 · resets 13:42")
        let rest = RateUsage(api: .rest, remaining: 0, limit: 5000, resetAt: reset, level: .exhausted)
        #expect(PanelText.rateUsage(rest, locale: british, timeZone: london) == "REST 0 / 5,000 · resets 13:42")
    }

    @Test("the banner says why refreshing is slower or stopped; nothing at the configured interval", arguments: [
        (RefreshDelay?.none, nil),
        (.configured(120), nil),
        (.stretched(216, api: .graphql, cost: 3),
         "Refreshing every 4 min to stay within 10% of your GraphQL rate limit (a refresh costs 3 points)."),
        (.stretched(5400, api: .rest, cost: 1),
         "Refreshing every 1 h 30 min to stay within 10% of your REST rate limit (a refresh costs 1 request)."),
        (.stretched(90, api: .rest, cost: 12.4),
         "Refreshing every 2 min to stay within 10% of your REST rate limit (a refresh costs 12 requests)."),
        (.backedOff(600, api: .graphql),
         "Your GraphQL rate limit is low (other tools are using it). Refreshing every 10 min."),
        (.paused(until: Date(timeIntervalSince1970: 1_790_340_120), reason: .exhausted(.graphql)),
         "GraphQL rate limit reached · updates resume at 13:42"),
        (.paused(until: Date(timeIntervalSince1970: 1_790_340_120), reason: .secondaryLimit),
         "GitHub asked shipyard to slow down · updates resume at 13:42"),
    ] as [(RefreshDelay?, String?)])
    func refreshDelay(delay: RefreshDelay?, text: String?) {
        #expect(PanelText.refreshDelay(delay, sharePercent: 10, locale: british, timeZone: london) == text)
    }

    // MARK: - The connect screen

    @Test("with no gh token the connect screen says to install gh and run gh auth login")
    func connectNoToken() {
        let text = PanelText.connect(.noToken)
        #expect(text.title == "Connect to GitHub")
        #expect(text.message.contains("GitHub CLI"))
        #expect(text.command == "gh auth login")
        #expect(text.suggestsInstallingGh)
        #expect(PanelText.installGh.contains("https://cli.github.com"))
        #expect(PanelText.installGh.contains("brew install gh"))
    }

    @Test("while shipyard looks for gh's token the panel says it's connecting")
    func connecting() {
        #expect(PanelText.connecting == "Connecting to GitHub…")
    }

    @Test("a Try again that leaves shipyard signed out says why, so the click doesn't look dead", arguments: [
        (Shipyard.SignedOutReason.noToken, "gh still isn't signed in."),
        (.rejected(.gh), "GitHub still rejects gh's token."),
        (.rejected(.tokenStore), "GitHub still rejects the token."),
        (.signedOut(.signedOut), "Still not connected."),
        (.signedOut(.ghStillSignedIn), "Still not connected."),
    ])
    func stillSignedOut(reason: Shipyard.SignedOutReason, text: String) {
        #expect(PanelText.stillSignedOut(reason) == text)
    }

    @Test("a rejected gh token says it was revoked or expired and to sign gh in again")
    func connectRejectedGh() {
        let text = PanelText.connect(.rejected(.gh))
        #expect(text.title == "GitHub rejected gh's token")
        #expect(text.message.contains("revoked or has expired"))
        #expect(text.command == "gh auth login")
        #expect(!text.suggestsInstallingGh)
    }

    @Test("a rejected stored token also points at gh auth login")
    func connectRejectedStored() {
        let text = PanelText.connect(.rejected(.tokenStore))
        #expect(text.title == "GitHub rejected shipyard's token")
        #expect(text.command == "gh auth login")
    }

    @Test("signing out while gh is still signed in says to run gh auth logout")
    func connectSignedOutGhStillSignedIn() {
        let text = PanelText.connect(.signedOut(.ghStillSignedIn))
        #expect(text.title == "Signed out")
        #expect(text.message.contains("still signed in"))
        #expect(text.command == "gh auth logout")
        #expect(!text.suggestsInstallingGh)
    }

    @Test("signing out with nothing left signed in points back at gh auth login")
    func connectSignedOut() {
        let text = PanelText.connect(.signedOut(.signedOut))
        #expect(text.title == "Signed out")
        #expect(text.command == "gh auth login")
    }

    // MARK: - The agent skill

    private let skillCommand = "npx -y skills add yahyabedirhan/shipyard -g -y"

    @Test("the skill offer says what the skill does and shows the command it runs")
    func skillOffer() {
        let text = PanelText.skillInstall(.idle)
        #expect(text.title == "Install the agent skill")
        #expect(text.tone == .neutral)
        #expect(text.message.contains("configuration file"))
        #expect(text.command == skillCommand)
        #expect(text.output == nil)
        #expect(text.action == .install)
    }

    @Test("a running install can be cancelled and shows no command to copy")
    func skillRunning() {
        let text = PanelText.skillInstall(.running)
        #expect(text.title == "Installing the agent skill…")
        #expect(text.command == nil)
        #expect(text.action == .cancel)
    }

    @Test("a finished install says so, with what the command printed")
    func skillInstalled() {
        let text = PanelText.skillInstall(.finished(.installed(output: "✓ Installed 1 skill: shipyard")))
        #expect(text.title == "Agent skill installed")
        #expect(text.tone == .success)
        #expect(text.output == "✓ Installed 1 skill: shipyard")
        #expect(text.command == nil)
        #expect(text.action == nil)
    }

    @Test("a failed install shows its output, the command to run by hand, and Try again")
    func skillFailed() {
        let text = PanelText.skillInstall(.finished(.failed(output: "npm ERR! network")))
        #expect(text.title == "Couldn't install the agent skill")
        #expect(text.tone == .warning)
        #expect(text.output == "npm ERR! network")
        #expect(text.command == skillCommand)
        #expect(text.action == .tryAgain)
    }

    @Test("without npx the command is there to copy and run in a terminal")
    func skillNpxNotFound() {
        let text = PanelText.skillInstall(.finished(.npxNotFound(command: skillCommand)))
        #expect(text.title == "npx wasn't found")
        #expect(text.message.contains("Node.js"))
        #expect(text.message.contains("terminal"))
        #expect(text.command == skillCommand)
        #expect(text.output == nil)
        #expect(text.action == .tryAgain)
    }

    @Test("an install stopped by the timeout says after how long")
    func skillTimedOut() {
        let text = PanelText.skillInstall(.timedOut(seconds: 180))
        #expect(text.title == "The install took too long")
        #expect(text.message.contains("3 min"))
        #expect(text.command == skillCommand)
        #expect(text.action == .tryAgain)
    }

    // MARK: - The project picker

    @Test("the picker's Add button counts the projects it writes")
    func addProjects() {
        #expect(PanelText.addProjects(0) == "Add projects")
        #expect(PanelText.addProjects(1) == "Add 1 project")
        #expect(PanelText.addProjects(3) == "Add 3 projects")
    }

    @Test("the picker's summary names what Add writes, counting a project's repositories when it groups several")
    func pickedProjects() {
        #expect(PanelText.pickedProjects([]) == nil)
        #expect(PanelText.pickedProjects([
            NewProject(name: "e-commerce", repositories: ["a/frontend", "a/backend"]),
            NewProject(name: "job-search", repositories: ["yahyabedirhan/job-search"]),
        ]) == "Adds e-commerce (2 repositories), job-search")
    }

    @Test("suggestions that couldn't load say why")
    func suggestionsFailed() {
        #expect(PanelText.suggestionsFailed(.unauthorized) == "Couldn't load suggestions: GitHub rejected the token.")
    }
}
