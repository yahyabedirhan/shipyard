import Foundation
@testable import ShipyardCore
import Testing

private let now = Date(timeIntervalSince1970: 1_790_337_600)

private func pr(
    _ number: Int = 1,
    repository: String = "o/r",
    state: ItemState = .open,
    checks: ChecksState = .pending,
    reviewRequested: Bool = false,
    activity: Int = 0,
    author: String = "octocat",
    authorKind: AuthorKind = .other,
    updatedAt: Date = now
) -> Item {
    Item(
        kind: .pullRequest,
        repository: repository,
        number: number,
        title: "Change \(number)",
        url: URL(string: "https://github.com/\(repository)/pull/\(number)")!,
        author: author,
        authorKind: authorKind,
        state: state,
        checks: checks,
        reviewRequestedFromViewer: reviewRequested,
        createdAt: now,
        updatedAt: updatedAt,
        closedAt: state.isOpen ? nil : now,
        activity: activity
    )
}

private func issue(_ number: Int = 1, state: ItemState = .open, activity: Int = 0, updatedAt: Date = now) -> Item {
    Item(
        kind: .issue,
        repository: "o/r",
        number: number,
        title: "Problem \(number)",
        url: URL(string: "https://github.com/o/r/issues/\(number)")!,
        author: "octocat",
        authorKind: .other,
        state: state,
        createdAt: now,
        updatedAt: updatedAt,
        closedAt: state.isOpen ? nil : now,
        activity: activity
    )
}

private func settings(
    _ name: String = "shop",
    repositories: [RepositorySelector] = ["o/r"],
    pullRequests: Bool = true,
    issues: Bool = false,
    rules: [NotificationRule] = [NotificationRule(event: .prOpened)]
) -> ProjectSettings {
    ProjectSettings(
        name: name,
        repositories: repositories,
        pullRequests: PullRequestSettings(show: pullRequests),
        issues: IssueSettings(show: issues),
        workflowRuns: WorkflowRunSettings(),
        notifications: rules
    )
}

private func snapshot(_ items: [String: [Item]], errors: [ItemSource: RepositoryError] = [:], at fetchedAt: Date = now) -> Snapshot {
    Snapshot(fetchedAt: fetchedAt, items: items, errors: errors)
}

/// What's known after one refresh listing `items` in "shop".
private func known(_ items: Item..., projects: [ProjectSettings] = [settings()]) -> KnownItems {
    KnownItems().updated(with: snapshot(["shop": items]), projects: projects)
}

private func events(_ before: KnownItems, _ items: Item..., projects: [ProjectSettings] = [settings()]) -> [EventKind] {
    EventDetector.events(known: before, snapshot: snapshot(["shop": items]), projects: projects).map(\.kind)
}

@Suite("Event detector")
struct EventDetectorTests {
    struct Transition: Sendable, CustomTestStringConvertible {
        var name: String
        var before: Item
        var after: Item
        var expected: [EventKind]
        var testDescription: String { name }
    }

    @Test("a change between refreshes makes its event", arguments: [
        Transition(name: "merged", before: pr(), after: pr(state: .merged), expected: [.prMerged]),
        Transition(name: "a draft merged", before: pr(state: .draft), after: pr(state: .merged), expected: [.prMerged]),
        Transition(name: "closed", before: pr(), after: pr(state: .closed), expected: [.prClosed]),
        Transition(name: "reopened", before: pr(state: .closed), after: pr(), expected: [.prReopened]),
        Transition(name: "review requested", before: pr(), after: pr(reviewRequested: true), expected: [.prReviewRequested]),
        Transition(name: "checks failed", before: pr(checks: .passed), after: pr(checks: .failed), expected: [.prChecksFailed]),
        Transition(name: "commented or reviewed", before: pr(activity: 1), after: pr(activity: 3), expected: [.prCommented]),
        Transition(
            name: "several at once",
            before: pr(),
            after: pr(checks: .failed, reviewRequested: true, activity: 1),
            expected: [.prReviewRequested, .prChecksFailed, .prCommented]
        ),
        Transition(name: "commented as it closed", before: pr(), after: pr(state: .closed, activity: 1), expected: [.prClosed, .prCommented]),
        Transition(name: "nothing changed", before: pr(), after: pr(), expected: []),
        Transition(name: "ready for review", before: pr(state: .draft), after: pr(), expected: []),
        Transition(name: "still failing", before: pr(checks: .failed), after: pr(checks: .failed, updatedAt: now + 60), expected: []),
        Transition(name: "still requested", before: pr(reviewRequested: true), after: pr(reviewRequested: true), expected: []),
        Transition(name: "review request withdrawn", before: pr(reviewRequested: true), after: pr(), expected: []),
        Transition(name: "failed after closing", before: pr(state: .closed), after: pr(state: .closed, checks: .failed), expected: []),
    ])
    func transitions(_ transition: Transition) {
        #expect(events(known(transition.before), transition.after) == transition.expected)
    }

    @Test("issues are opened, closed and commented; a reopen is no event; only while the project shows issues")
    func issues() {
        let withIssues = [settings(issues: true)]
        func issueEvents(_ before: [Item], _ after: [Item], projects: [ProjectSettings] = withIssues) -> [EventKind] {
            let known = KnownItems().updated(with: snapshot(["shop": before]), projects: projects)
            return EventDetector.events(known: known, snapshot: snapshot(["shop": after]), projects: projects).map(\.kind)
        }
        #expect(issueEvents([issue(1)], [issue(1), issue(2)]) == [.issueOpened])
        #expect(issueEvents([issue(1)], [issue(1, state: .closed)]) == [.issueClosed])
        #expect(issueEvents([issue(1)], [issue(1, activity: 2)]) == [.issueCommented])
        #expect(issueEvents([issue(1)], [issue(1, state: .closed, activity: 1)]) == [.issueClosed, .issueCommented])
        #expect(issueEvents([issue(1, state: .closed)], [issue(1)]) == [])
        #expect(issueEvents([issue(1)], [issue(1), issue(2, state: .closed)]) == [])

        // Issues and pull requests are separate sources: issues just shown are
        // a first sight, even in a project whose pull requests are known.
        let before = KnownItems().updated(with: snapshot(["shop": [pr(1)]]), projects: [settings()])
        #expect(!before.knows(ItemSource(repository: "o/r", kind: .issue), in: "shop"))
        #expect(EventDetector.events(known: before, snapshot: snapshot(["shop": [pr(1), issue(1)]]), projects: withIssues).isEmpty)
        let shown = before.updated(with: snapshot(["shop": [pr(1), issue(1)]]), projects: withIssues)
        #expect(shown.knows(ItemSource(repository: "o/r", kind: .issue), in: "shop"))

        // Hiding them forgets the source again.
        let hidden = shown.updated(with: snapshot(["shop": [pr(1)]]), projects: [settings()])
        #expect(!hidden.knows(ItemSource(repository: "o/r", kind: .issue), in: "shop"))

        let closed = EventDetector.events(
            known: KnownItems().updated(with: snapshot(["shop": [issue(1)]]), projects: withIssues),
            snapshot: snapshot(["shop": [issue(1, state: .closed)]]),
            projects: withIssues
        )
        #expect(closed.first?.headline == "Closed issue #1")
        #expect(closed.first?.id.hasPrefix("issue.closed https://github.com/o/r/issues/1 ") == true)
    }

    @Test("a pull request not known before is opened, drafts too; one first found closed makes nothing")
    func newItems() {
        let before = known(pr(1))
        #expect(events(before, pr(1), pr(2)) == [.prOpened])
        #expect(events(before, pr(1), pr(2, state: .draft)) == [.prOpened])
        #expect(events(before, pr(1), pr(2, state: .merged), pr(3, state: .closed)) == [])
    }

    @Test("nothing is an event the first time a project's source is fetched")
    func firstSightIsSilent() {
        // The first refresh ever.
        #expect(events(KnownItems(), pr(1)) == [])

        // A project just added: the other project's items are known, not its own.
        let two = [settings(), settings("blog", repositories: ["o/blog"])]
        let before = known(pr(1), projects: [settings()])
        let next = snapshot(["shop": [pr(1), pr(2)], "blog": [pr(7, repository: "o/blog")]])
        #expect(EventDetector.events(known: before, snapshot: next, projects: two).map(\.item.number) == [2])

        // A repository just added to a project.
        let wider = [settings(repositories: ["o/r", "o/new"])]
        let added = snapshot(["shop": [pr(1), pr(5, repository: "o/new")]])
        #expect(EventDetector.events(known: before, snapshot: added, projects: wider).isEmpty)
        let afterAdding = before.updated(with: added, projects: wider)
        #expect(afterAdding.knows(ItemSource(repository: "o/new", kind: .pullRequest), in: "shop"))
        let later = snapshot(["shop": [pr(1), pr(5, repository: "o/new"), pr(6, repository: "o/new")]])
        #expect(EventDetector.events(known: afterAdding, snapshot: later, projects: wider).map(\.item.number) == [6])
    }

    @Test("a project, repository or kind no longer fetched is forgotten, so adding it back is silent")
    func forgetting() {
        let before = known(pr(1))
        let removed = before.updated(with: snapshot([:]), projects: [])
        #expect(removed.sources.isEmpty)
        #expect(removed.items.isEmpty)

        let hidden = before.updated(with: snapshot(["shop": []]), projects: [settings(pullRequests: false)])
        #expect(!hidden.knows(ItemSource(repository: "o/r", kind: .pullRequest), in: "shop"))
        #expect(events(hidden, pr(1), pr(2)) == [])
    }

    @Test("a repository that failed keeps its items and sources, so its return isn't a burst")
    func failedRepository() {
        let project = [settings(repositories: ["o/r", "o/gone"])]
        let first = KnownItems().updated(
            with: snapshot(["shop": [pr(1), pr(2, repository: "o/gone")]]),
            projects: project
        )
        let error = RepositoryError(repository: "o/gone", kind: .notFound, message: "gone")
        let gone = [ItemSource(repository: "o/gone", kind: .pullRequest): error]
        let failed = first.updated(with: snapshot(["shop": [pr(1)]], errors: gone), projects: project)
        #expect(failed.items.count == 2)
        #expect(failed.knows(ItemSource(repository: "o/gone", kind: .pullRequest), in: "shop"))

        let back = snapshot(["shop": [pr(1), pr(2, repository: "o/gone"), pr(3, repository: "o/gone")]])
        #expect(EventDetector.events(known: failed, snapshot: back, projects: project).map(\.item.number) == [3])

        // A repository that failed on its first refresh isn't known yet.
        let never = KnownItems().updated(with: snapshot(["shop": [pr(1)]], errors: gone), projects: project)
        #expect(!never.knows(ItemSource(repository: "o/gone", kind: .pullRequest), in: "shop"))
    }

    @Test("an item that leaves the list and comes back isn't new: it's compared with its last version")
    func leavesAndReturns() {
        let before = known(pr(1), pr(2))
        // #2 drops out of the most recent 50 for a while.
        let gone = before.updated(with: snapshot(["shop": [pr(1)]], at: now + 600), projects: [settings()])
        #expect(gone.items[pr(2).id]?.state == .open)
        let later = snapshot(["shop": [pr(1), pr(2), pr(3)]], at: now + 1_200)
        #expect(EventDetector.events(known: gone, snapshot: later, projects: [settings()]).map(\.item.number) == [3])

        // Merged while it was out of the list: it's merged when it's back.
        let merged = snapshot(["shop": [pr(1), pr(2, state: .merged)]], at: now + 1_200)
        #expect(EventDetector.events(known: gone, snapshot: merged, projects: [settings()]).map(\.kind) == [.prMerged])
    }

    @Test("an item missing from the list is kept for 30 days, then forgotten")
    func missingItemsRetention() {
        let before = known(pr(1), pr(2))
        let day = 86_400.0
        let month = before.updated(with: snapshot(["shop": [pr(1)]], at: now + 29 * day), projects: [settings()])
        #expect(month.items[pr(2).id] != nil)
        let past = month.updated(with: snapshot(["shop": [pr(1)]], at: now + 31 * day), projects: [settings()])
        #expect(past.items[pr(2).id] == nil)
        // #1 was listed all along, so it stays.
        #expect(past.items[pr(1).id] != nil)
    }

    @Test("a listed item's presence is bumped at most once a day, so an unchanged refresh changes nothing")
    func presenceResolution() {
        let before = known(pr(1))
        let soon = before.updated(with: snapshot(["shop": [pr(1)]], at: now + 3_600), projects: [settings()])
        #expect(soon == before)
        let nextDay = before.updated(with: snapshot(["shop": [pr(1)]], at: now + 86_400), projects: [settings()])
        #expect(nextDay.items[pr(1).id]?.present == now + 86_400)
    }

    @Test("a source that failed holds back only itself: runs that can't be read don't hold back pull requests")
    func failedSourceOnly() {
        let withRuns = ProjectSettings(
            name: "blog",
            repositories: ["o/r"],
            pullRequests: PullRequestSettings(),
            issues: IssueSettings(),
            workflowRuns: WorkflowRunSettings(show: true),
            notifications: [NotificationRule(event: .prOpened)]
        )
        let runs = ItemSource(repository: "o/r", kind: .workflowRun)
        let forbidden = [runs: RepositoryError(repository: "o/r", kind: .forbidden, message: "workflow runs: HTTP 403")]
        // A project just added, whose runs are forbidden on its first refresh.
        let first = KnownItems().updated(with: snapshot(["blog": [pr(1)]], errors: forbidden), projects: [withRuns])
        #expect(first.knows(ItemSource(repository: "o/r", kind: .pullRequest), in: "blog"))
        #expect(!first.knows(runs, in: "blog"))

        let next = snapshot(["blog": [pr(1), pr(2)]], errors: forbidden)
        #expect(EventDetector.events(known: first, snapshot: next, projects: [withRuns]).map(\.kind) == [.prOpened])
    }

    @Test("an event's id is the same in every project, and tells recurring occurrences apart")
    func ids() {
        let two = [settings(), settings("mirror")]
        let before = KnownItems().updated(with: snapshot(["shop": [], "mirror": []]), projects: two)
        let found = EventDetector.events(known: before, snapshot: snapshot(["shop": [pr(1)], "mirror": [pr(1)]]), projects: two)
        #expect(found.map(\.project) == ["shop", "mirror"])
        #expect(found[0].id == found[1].id)
        #expect(found[0].id == "pr.opened https://github.com/o/r/pull/1")
        #expect(found[0].headline == "New PR #1")

        let first = EventDetector.events(known: known(pr(checks: .passed)), snapshot: snapshot(["shop": [pr(checks: .failed)]]), projects: [settings()])
        let again = EventDetector.events(
            known: known(pr(checks: .passed, updatedAt: now + 60)),
            snapshot: snapshot(["shop": [pr(checks: .failed, updatedAt: now + 60)]]),
            projects: [settings()]
        )
        #expect(first.map(\.kind) == [.prChecksFailed])
        #expect(first[0].id != again[0].id)
    }

    @Test("every event has a title text")
    func headlines() {
        #expect(EventKind.prOpened.headline(number: 57) == "New PR #57")
        #expect(EventKind.prMerged.headline(number: 57) == "Merged PR #57")
        #expect(EventKind.prChecksFailed.headline(number: 57) == "Checks failed on PR #57")
        #expect(EventKind.allCases.allSatisfy { $0.headline(number: 1).contains("#1") })
    }
}

@Suite("Notification rules")
struct NotificationRulesTests {
    private func event(_ kind: EventKind = .prOpened, author: String = "octocat", authorKind: AuthorKind = .other) -> Event {
        Event(kind: kind, project: "shop", item: pr(author: author, authorKind: authorKind))
    }

    @Test("a rule has to name the event and cover the author")
    func rules() {
        let defaults = settings()
        #expect(NotificationRules.shouldNotify(event(), settings: defaults))
        #expect(!NotificationRules.shouldNotify(event(.prMerged), settings: defaults))

        let own = settings(rules: [NotificationRule(event: .prMerged, authors: [.me]), NotificationRule(event: .prOpened, authors: [.bots])])
        #expect(!NotificationRules.shouldNotify(event(), settings: own))
        #expect(NotificationRules.shouldNotify(event(author: "dependabot[bot]", authorKind: .bot), settings: own))
        #expect(NotificationRules.shouldNotify(event(.prMerged, author: "yabepa", authorKind: .me), settings: own))
        #expect(!NotificationRules.shouldNotify(event(.prMerged), settings: own))

        #expect(!NotificationRules.shouldNotify(event(), settings: settings(rules: [])))
    }

    @Test("a rule's authors cover an author when any selector matches, and everyone when empty")
    func ruleAuthors() {
        let rule = NotificationRule(event: .prOpened, authors: [.login("octocat"), .bots])
        #expect(rule.covers(pr(author: "OctoCat"), viewer: "yabepa"))
        #expect(rule.covers(pr(author: "renovate[bot]"), viewer: "yabepa"))
        #expect(!rule.covers(pr(author: "someone"), viewer: "yabepa"))
        #expect(NotificationRule(event: .prOpened).covers(pr(author: "someone"), viewer: nil))
        // `me` is the viewer, even where the item didn't say so.
        let mine = settings(rules: [NotificationRule(event: .prOpened, authors: [.me])])
        #expect(NotificationRules.shouldNotify(event(author: "yabepa"), settings: mine, viewer: "yabepa"))
    }

    @Test("a notification carries the project, title text, the item's title and its URL")
    func notification() {
        let posted = NotificationRules.notification(for: event())
        #expect(posted.project == "shop")
        #expect(posted.headline == "New PR #1")
        #expect(posted.itemTitle == "Change 1")
        #expect(posted.itemURL == URL(string: "https://github.com/o/r/pull/1")!)
        #expect(posted.title == "shop · New PR #1")
        #expect(posted.id == event().id)
    }

    @Test("notified events are kept while their item is listed, and for 30 days after")
    func notifiedPruning() {
        var notified = NotifiedEvents()
        let opened = event()
        notified.insert(opened, at: now)
        #expect(notified.contains(opened))
        #expect(!notified.contains(event(.prMerged)))

        let changed = notified.prune(present: [opened.item.id], at: now + 3_600)
        #expect(!changed)
        notified.prune(present: [opened.item.id], at: now + 40 * 86_400)
        #expect(notified.contains(opened))

        notified.prune(present: [], at: now + 69 * 86_400)
        #expect(notified.contains(opened))
        notified.prune(present: [], at: now + 71 * 86_400)
        #expect(!notified.contains(opened))
    }
}
