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

    @Test("the header names the app and how many items need attention, saying nothing at 0")
    func header() {
        #expect(PanelText.title == "Shipyard")
        #expect(PanelText.attentionSummary(0) == nil)
        #expect(PanelText.attentionSummary(1) == "1 needs attention")
        #expect(PanelText.attentionSummary(10) == "10 need attention")
    }

    @Test("the layout button's hover help and VoiceOver label name the current layout and the next one")
    func layoutButton() {
        #expect(PanelText.layoutButton(.list) == "Layout: list. Click for tabs.")
        #expect(PanelText.layoutButton(.tabs) == "Layout: tabs. Click for list.")
    }

    @Test("signed in, the header names the account by its handle; until it's known, the app")
    func headerAccount() {
        let viewer = Viewer(login: "yabepa", id: 42, name: "Yahya Bedirhan Pak")
        #expect(PanelText.title(for: viewer) == "@yabepa")
        #expect(PanelText.title(for: nil) == "Shipyard")
    }

    @Test("the account's hover text gives the full name when there is one, and says a click opens the profile")
    func headerAccountHelp() {
        let named = Viewer(login: "yabepa", id: 42, name: "Yahya Bedirhan Pak")
        #expect(PanelText.profileHelp(named) == "Yahya Bedirhan Pak (@yabepa) · Open profile on GitHub")
        #expect(PanelText.profileHelp(Viewer(login: "yabepa", id: 42)) == "@yabepa · Open profile on GitHub")
        #expect(PanelText.profileHelp(Viewer(login: "yabepa", id: 42, name: "  ")) == "@yabepa · Open profile on GitHub")
    }

    @Test("VoiceOver names the account button's action")
    func headerAccountAccessibility() {
        #expect(PanelText.profileAccessibilityLabel(Viewer(login: "yabepa", id: 42)) == "Open @yabepa's profile on GitHub")
    }

    @Test("the footer's and a section's button to mark everything seen says so")
    func markAllSeen() {
        #expect(PanelText.markAllSeen == "Mark all seen")
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

    @Test("configuration warnings name the file and line; none means no banner")
    func configWarnings() {
        #expect(PanelText.configWarnings([]) == nil)
        #expect(PanelText.configWarnings([
            ConfigIssue(line: 1, message: "unknown setting `future-key` (ignored)"),
            ConfigIssue(line: nil, message: "unknown setting `theme` (ignored; did you mean `them`?)"),
        ]) == """
            config.toml line 1: unknown setting `future-key` (ignored)
            config.toml: unknown setting `theme` (ignored; did you mean `them`?)
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

    private func row(
        repository: String = "yahyabedirhan/shipyard",
        number: Int = 21,
        author: String = "yahyabedirhan",
        checks: ChecksState = .none
    ) -> MenuRow {
        MenuRow(Item(
            kind: .pullRequest,
            repository: repository,
            number: number,
            title: "Attention in the panel",
            url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
            author: author,
            authorKind: .me,
            state: .open,
            checks: checks,
            createdAt: now.addingTimeInterval(-37 * 60),
            updatedAt: now.addingTimeInterval(-37 * 60)
        ))
    }

    @Test("a row's second line names the repository only in a project with more than one")
    func rowDetail() {
        #expect(PanelText.rowDetail(row(), showingRepository: true, now: now) == "#21 · shipyard · yahyabedirhan · 37m")
        #expect(PanelText.rowDetail(row(), showingRepository: false, now: now) == "#21 · yahyabedirhan · 37m")
    }

    @Test("a repository is named without its owner")
    func repositoryName() {
        #expect(PanelText.repositoryName("yahyabedirhan/shipyard") == "shipyard")
        #expect(PanelText.repositoryName("shipyard") == "shipyard")
    }

    @Test("a pull request's card holds only what its row doesn't: branches, size, review, comments and when it last moved")
    func pullRequestCard() {
        var pullRequest = row(checks: .passed)
        pullRequest.item.avatarURL = URL(string: "https://avatars.githubusercontent.com/u/42?v=4")
        pullRequest.item.updatedAt = now.addingTimeInterval(-5 * 60)
        pullRequest.item.details = ItemDetails(
            headBranch: "attention-dot",
            baseBranch: "main",
            additions: 120,
            deletions: 43,
            changedFiles: 6,
            review: .approved,
            comments: 3,
            reviews: 1
        )
        let card = PanelText.rowCard(pullRequest, now: now)
        #expect(card.avatarURL == URL(string: "https://avatars.githubusercontent.com/u/42?v=4"))
        #expect(card.headline == "Attention in the panel")
        #expect(card.lines == [
            "attention-dot → main",
            "+120 −43 · 6 files",
            "Approved · Checks passed",
            "3 comments · 1 review · updated 5m ago",
        ])
        // The app draws each fact with its icon, a line of them at a time.
        #expect(card.facts == [
            [.branches(head: "attention-dot", base: "main")],
            [.size(additions: 120, deletions: 43), .files(6)],
            [.review(.approved), .checks(.passed)],
            [.comments(3), .reviews(1), .updated("5m")],
        ])
        #expect(card.reasons == [])
        #expect(card.attention == nil)
    }

    @Test("a card leaves out what GitHub didn't give, and the update time when it's the row's age")
    func sparseCard() {
        let card = PanelText.rowCard(row(), now: now)
        #expect(card.lines == ["No comments"])
    }

    @Test("an issue's card leaves out no comments, so a quiet issue is its title and why it needs attention")
    func issueCard() {
        var issue = row()
        issue.kind = .issue
        issue.item.kind = .issue
        #expect(PanelText.rowCard(issue, now: now).facts == [])

        issue.item.details.comments = 1
        #expect(PanelText.rowCard(issue, now: now).lines == ["1 comment"])

        issue.item.details.comments = 0
        issue.item.updatedAt = now.addingTimeInterval(-2 * 3600)
        issue.item.createdAt = now.addingTimeInterval(-3 * 86_400)
        issue = MenuRow(issue.item)
        #expect(PanelText.rowCard(issue, now: now).facts == [[.updated("2h")]])
        #expect(PanelText.rowCard(issue, now: now).lines == ["updated 2h ago"])
    }

    @Test("a card tags a review request and failed checks, in words too, but not new or changed")
    func attentionCard() {
        var unseen = row(checks: .failed)
        unseen.needsAttention = true
        unseen.attentionReasons = [.unseen, .reviewRequested, .checksFailed]
        let card = PanelText.rowCard(unseen, now: now)
        #expect(card.reasons == [.reviewRequested, .checksFailed])
        #expect(card.kind == .pullRequest)
        #expect(card.attention == "Your review is requested · Checks failed")
        #expect(card.spoken == "Checks failed. No comments. Your review is requested · Checks failed")

        var changed = unseen
        changed.attentionReasons = [.changed]
        #expect(PanelText.rowCard(changed, now: now).reasons == [])
        #expect(PanelText.rowCard(changed, now: now).attention == nil)
    }

    @Test("a run's card has its title, what started it and who, and how long it ran")
    func runCard() {
        let started = now.addingTimeInterval(-10 * 60)
        var item = Item(
            kind: .workflowRun,
            repository: "yahyabedirhan/shipyard",
            number: 41,
            title: "CI",
            url: URL(string: "https://github.com/yahyabedirhan/shipyard/actions/runs/41")!,
            author: "yahyabedirhan",
            authorKind: .me,
            state: .failed,
            checks: .failed,
            createdAt: started,
            updatedAt: started.addingTimeInterval(192),
            closedAt: started.addingTimeInterval(192),
            branch: "main",
            details: ItemDetails(runTitle: "Add the hover card", runEvent: "push", runAttempt: 2)
        )
        var failed = MenuRow(item, needsAttention: true)
        failed.attentionReasons = [.checksFailed]
        let card = PanelText.rowCard(failed, now: now)
        #expect(card.headline == "Add the hover card")
        #expect(card.lines == ["Push by yahyabedirhan · attempt 2", "Took 3m 12s"])
        #expect(card.attention == "Run failed")
        #expect(card.facts == [
            [.trigger(event: "push", by: "yahyabedirhan"), .attempt(2)],
            [.duration("3m 12s", running: false)],
        ])

        item.state = .running
        item.closedAt = nil
        item.details = ItemDetails(runEvent: "workflow_dispatch", runAttempt: 1)
        let running = PanelText.rowCard(MenuRow(item), now: now)
        #expect(running.headline == "CI")
        #expect(running.lines == ["Manual run by yahyabedirhan", "Running for 10m"])
    }

    @Test("a duration reads in seconds, minutes and seconds, or hours and minutes")
    func duration() {
        #expect(PanelText.duration(42) == "42s")
        #expect(PanelText.duration(180) == "3m")
        #expect(PanelText.duration(192) == "3m 12s")
        #expect(PanelText.duration(3600) == "1h")
        #expect(PanelText.duration(3900) == "1h 5m")
    }

    @Test("the header's refresh and settings buttons have hover help, refresh naming its shortcut")
    func headerButtonHelp() {
        #expect(PanelText.refreshHelp == "Refresh (⌘R)")
        #expect(PanelText.settings == "Settings")
    }

    @Test("a list section's header tells VoiceOver what a click does to it")
    func sectionFoldHelp() {
        #expect(PanelText.sectionFoldHelp("shipyard", isCollapsed: false) == "Collapse shipyard")
        #expect(PanelText.sectionFoldHelp("shipyard", isCollapsed: true) == "Expand shipyard")
    }

    @Test("a row's action, attention dot and check dot have words for VoiceOver and the hover help")
    func rowWords() {
        #expect(PanelText.markRowSeen == "Mark seen")
        #expect(PanelText.needsAttention == "Needs attention")
        #expect(PanelText.checks(.none) == nil)
        #expect(PanelText.checks(.pending) == "Checks running")
        #expect(PanelText.checks(.passed) == "Checks passed")
        #expect(PanelText.checks(.failed) == "Checks failed")
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

    @Test("on first launch, or signed out with nothing signed in, a welcome, Sign in with GitHub leads and gh folds away", arguments: [
        Shipyard.SignedOutReason.noToken, .userSignedOut(.signedOut),
    ])
    func connectFirstLaunch(reason: Shipyard.SignedOutReason) {
        let text = PanelText.connect(reason, canSignIn: true)
        #expect(text.title == "Welcome to Shipyard")
        #expect(text.message == "Connect your GitHub account to see the pull requests your agents open.")
        #expect(text.lead == .signIn)
        #expect(text.signInUnavailable == nil)
        #expect(text.showsInstallHint)
    }

    @Test("signed out while gh is still signed in, a welcome back says gh is one click away, and there's no gh auth logout")
    func connectSignedOutGhStillSignedIn() {
        let text = PanelText.connect(.userSignedOut(.ghStillSignedIn), canSignIn: true)
        #expect(text.title == "Welcome back")
        #expect(text.message == "The GitHub CLI `gh` is already signed in on this computer, so connecting takes one click:")
        #expect(text.alternative == "Alternatively, sign in with GitHub, if you'd rather:")
        #expect(!text.message.contains("logout"))
        #expect(text.lead == .connectWithGh)
        #expect(!text.showsInstallHint)
    }

    @Test("without a client ID, signed out while gh is still signed in has no second block")
    func connectSignedOutGhStillSignedInWithoutClientID() {
        let text = PanelText.connect(.userSignedOut(.ghStillSignedIn), canSignIn: false)
        #expect(text.message == "The GitHub CLI `gh` is already signed in on this computer, so connecting takes one click:")
        #expect(text.alternative == nil)
    }

    @Test("only signed out while gh is still signed in splits into two blocks", arguments: [
        Shipyard.SignedOutReason.noToken, .rejected(.gh), .rejected(.tokenStore), .userSignedOut(.signedOut),
    ])
    func connectOneBlock(reason: Shipyard.SignedOutReason) {
        #expect(PanelText.connect(reason, canSignIn: true).alternative == nil)
    }

    @Test("a rejected Keychain token says so in a line, then Sign in with GitHub leads")
    func connectRejectedStored() {
        let text = PanelText.connect(.rejected(.tokenStore), canSignIn: true)
        #expect(text.title == "Welcome back")
        #expect(text.message == "Your GitHub sign-in expired or was revoked. Sign in again to pick up where you left off.")
        #expect(text.lead == .signIn)
        #expect(text.showsInstallHint)
    }

    @Test("a rejected gh token leads with gh auth login and Connect with gh, then Sign in with GitHub")
    func connectRejectedGh() {
        let text = PanelText.connect(.rejected(.gh), canSignIn: true)
        #expect(text.title == "Welcome back")
        #expect(text.message == "GitHub rejected the `gh` command's sign-in. Sign `gh` in again in a terminal, then connect.")
        #expect(text.lead == .ghCommand)
        #expect(!text.showsInstallHint)
    }

    @Test("the gh way's words: gh in code font, as a command", arguments: [
        (PanelText.connectWithGh, "Connect with `gh`"),
        (PanelText.useGhInstead, "Use the GitHub CLI `gh` instead"),
        (PanelText.useGhInsteadHelp, "Shipyard reuses the `gh` command's sign-in if you already use it."),
        (PanelText.installGhHelp, "How to install `gh`"),
        (PanelText.installGh, "Download it from [cli.github.com](https://cli.github.com), or run:"),
        (PanelText.ghLogin, "gh auth login"),
        (PanelText.brewInstallGh, "brew install gh"),
        (PanelText.signInWithGitHub, "Sign in with GitHub"),
    ])
    func connectGhWords(text: String, expected: String) {
        #expect(text == expected)
    }

    @Test("without a client ID Sign in with GitHub says why it's unavailable, and gh leads", arguments: [
        (Shipyard.SignedOutReason.noToken, PanelText.Connect.Lead.ghCommand),
        (.userSignedOut(.signedOut), .ghCommand),
        (.rejected(.tokenStore), .ghCommand),
        (.rejected(.gh), .ghCommand),
        (.userSignedOut(.ghStillSignedIn), .connectWithGh),
    ])
    func connectWithoutClientID(reason: Shipyard.SignedOutReason, lead: PanelText.Connect.Lead) {
        let text = PanelText.connect(reason, canSignIn: false)
        #expect(text.signInUnavailable == PanelText.signInUnavailable)
        #expect(text.lead == lead)
        #expect(!text.message.lowercased().contains("sign in with github"))
    }

    @Test("with no token and no client ID the screen says to connect through gh, with the install hint")
    func connectNoTokenWithoutClientID() {
        let text = PanelText.connect(.noToken, canSignIn: false)
        #expect(text.title == "Welcome to Shipyard")
        #expect(text.message == "Connect your GitHub account through the GitHub CLI `gh`.")
        #expect(text.showsInstallHint)
    }

    @Test("gh is always in backticks, so it reads in code font, in every state's words")
    func connectGhInCodeFont() throws {
        let reasons: [Shipyard.SignedOutReason] = [
            .noToken, .rejected(.gh), .rejected(.tokenStore), .userSignedOut(.signedOut), .userSignedOut(.ghStillSignedIn),
        ]
        var words = reasons.flatMap { reason in
            [true, false].flatMap { canSignIn in
                let text = PanelText.connect(reason, canSignIn: canSignIn)
                return [text.title, text.message, text.alternative ?? ""]
            } + [PanelText.stillSignedOut(reason)]
        }
        words += [PanelText.connectWithGh, PanelText.useGhInstead, PanelText.useGhInsteadHelp, PanelText.installGhHelp]
        words += [DeviceFlowError.unauthorized, .rejected("x")].map(PanelText.signInFailed)
        let code = try Regex("`[^`]*`")
        let gh = try Regex("\\bgh\\b")
        for text in words {
            // Outside the code spans, no gh is left.
            #expect(text.replacing(code, with: "").firstMatch(of: gh) == nil, "bare gh in: \(text)")
        }
    }

    @Test("the unavailable reason is short and names the missing client ID")
    func signInUnavailableReason() {
        #expect(PanelText.signInUnavailable == "Not available in this build: it has no OAuth App client ID.")
    }

    @Test("while shipyard looks for a token the panel says it's connecting")
    func connecting() {
        #expect(PanelText.connecting == "Connecting to GitHub…")
    }

    @Test("a Connect with gh that leaves shipyard signed out says why, so the click doesn't look dead", arguments: [
        (Shipyard.SignedOutReason.noToken, "The `gh` command still isn't signed in."),
        (.rejected(.gh), "GitHub still rejects the `gh` command's sign-in."),
        (.rejected(.tokenStore), "GitHub still rejects the sign-in."),
        (.userSignedOut(.signedOut), "Still not connected."),
        (.userSignedOut(.ghStillSignedIn), "Still not connected."),
    ])
    func stillSignedOut(reason: Shipyard.SignedOutReason, text: String) {
        #expect(PanelText.stillSignedOut(reason) == text)
    }

    // MARK: - Sign in with GitHub

    @Test("the code screen shows the code, says where it goes, how to copy it, and how to open GitHub")
    func deviceCodeScreen() {
        let code = DeviceCode(
            userCode: "WDJB-MJHT",
            verificationURL: URL(string: "https://github.com/login/device")!,
            expiresAt: Date(timeIntervalSince1970: 1_790_338_500)
        )
        let text = PanelText.deviceCode(code, locale: british, timeZone: london)
        #expect(text.title == "Enter this code on GitHub")
        #expect(text.code == "WDJB-MJHT")
        #expect(text.message == "Copy the code, open github.com/login/device and paste it there. Shipyard connects once you approve.")
        #expect(text.copyCode == "Copy code")
        #expect(text.copyTitle == "Copy")
        #expect(text.copied == "Copied")
        #expect(text.openButton == "Copy code and open GitHub")
        #expect(text.waiting == "Waiting for approval · the code expires at 13:15")
        #expect(PanelText.cancelSignIn == "Cancel")
    }

    @Test("a sign-in that ended without a token says why", arguments: [
        (DeviceFlowError.expired, "The code expired before it was approved. Sign in again for a new one."),
        (.denied, "The sign-in was declined on GitHub."),
        (.clientIDMissing, "Not available in this build: it has no OAuth App client ID."),
        (.unauthorized, "GitHub refused the sign-in. Try again, or use `gh`."),
        (.rejected("device_flow_disabled"), "GitHub refused the sign-in (device_flow_disabled). Try again, or use `gh`."),
        (.http(503), "GitHub answered with an error (HTTP 503). Try again."),
        (.network("offline"), "GitHub couldn't be reached. Check the connection and try again."),
        (.malformed, "GitHub's answer couldn't be read. Try again."),
    ])
    func signInFailed(error: DeviceFlowError, text: String) {
        #expect(PanelText.signInFailed(error) == text)
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

    // MARK: - The CLI link

    private let linkCommand = "mkdir -p ~/.local/bin && ln -sf /Applications/Shipyard.app/Contents/Helpers/shipyard ~/.local/bin/shipyard"

    @Test("the CLI link offer says what the CLI is for and shows the command it stands for")
    func cliLinkOffer() {
        let text = PanelText.cliLink(.unlinked, command: linkCommand)
        #expect(text.title == "Link the shipyard CLI")
        #expect(text.tone == .neutral)
        #expect(text.message.contains("pings"))
        #expect(text.message.contains("~/.local/bin"))
        #expect(text.command == linkCommand)
        #expect(text.action == .link)
    }

    @Test("a linked CLI says so, mentions the PATH, and offers nothing to copy")
    func cliLinked() {
        let text = PanelText.cliLink(.linked, command: linkCommand)
        #expect(text.title == "shipyard CLI linked")
        #expect(text.tone == .success)
        #expect(text.message.contains("PATH"))
        #expect(text.command == nil)
        #expect(text.action == nil)
    }

    @Test("something in the way is named and left alone, with the command to replace it and Try again")
    func cliLinkOccupied() {
        let other = PanelText.cliLink(.occupied(destination: "/Users/me/Downloads/Shipyard.app/Contents/Helpers/shipyard"), command: linkCommand)
        #expect(other.title == "Couldn't link the shipyard CLI")
        #expect(other.tone == .warning)
        #expect(other.message.contains("already links to /Users/me/Downloads/Shipyard.app/Contents/Helpers/shipyard."))
        #expect(other.message.contains("leaves it alone"))
        #expect(other.command == linkCommand)
        #expect(other.action == .tryAgain)

        let file = PanelText.cliLink(.occupied(destination: nil), command: linkCommand)
        #expect(file.message.hasPrefix("Something else is already at ~/.local/bin/shipyard."))
        #expect(file.command == linkCommand)
    }

    @Test("a link that couldn't be made gives the reason and the command to run in a terminal")
    func cliLinkFailed() {
        let text = PanelText.cliLink(.failed("You don't have permission to save the file “shipyard” in the folder “bin”"), command: linkCommand)
        #expect(text.title == "Couldn't link the shipyard CLI")
        #expect(text.message == "You don't have permission to save the file “shipyard” in the folder “bin”. Run this in a terminal instead:")
        #expect(text.command == linkCommand)
        #expect(text.action == .tryAgain)
    }

    @Test("without a CLI in the app the card says to open the installed app and offers no command")
    func cliLinkMissing() {
        let text = PanelText.cliLink(.missingCLI, command: linkCommand)
        #expect(text.message.contains("Shipyard.app"))
        #expect(text.command == nil)
        #expect(text.action == nil)
    }

    @Test("a translocated copy says to move Shipyard to Applications first, with no command or button")
    func cliLinkTranslocated() {
        let text = PanelText.cliLink(.translocated, command: linkCommand)
        #expect(text.title == "Move Shipyard to Applications")
        #expect(text.message.hasSuffix("Move Shipyard to Applications first, then link the CLI."))
        #expect(text.command == nil)
        #expect(text.action == nil)
        #expect(text.tone == .warning)
    }

    // MARK: - The project picker

    @Test("the preset step speaks to the user and names neither the app nor the configuration file in its description")
    func presetWords() {
        #expect(PanelText.presetIntro == "Pick a starting point for your configuration. You can change it at any time.")
        #expect(!PanelText.presetIntro.contains("config.toml"))
        #expect(!PanelText.presetIntro.contains("Shipyard"))
        #expect(Preset.myAgents.title == "You and your agents")
        #expect(Preset.myAgents.summary == "The pull requests and issues you and your agents open, in the repositories you pick.")
    }

    @Test("the preset step's button goes on to the picker when repositories are still needed, otherwise starts with the preset")
    func presetContinue() {
        #expect(PanelText.presetContinue(PresetChoice()) == "Continue")
        #expect(PanelText.presetContinue(PresetChoice(preset: .myAgents)) == "Choose repositories")
        #expect(PanelText.presetContinue(PresetChoice(preset: .reviewQueue)) == "Start with Review queue")
        var incoming = PresetChoice(preset: .incomingContributions)
        #expect(PanelText.presetContinue(incoming) == "Start with Incoming contributions")
        incoming.watchesOwned = false
        #expect(PanelText.presetContinue(incoming) == "Choose repositories")
    }

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
