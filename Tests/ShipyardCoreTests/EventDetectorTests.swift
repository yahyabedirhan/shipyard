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

private func settings(
    _ name: String = "shop",
    repositories: [String] = ["o/r"],
    pullRequests: Bool = true,
    rules: [NotificationRule] = [NotificationRule(event: .prOpened)]
) -> ProjectSettings {
    ProjectSettings(
        name: name,
        repositories: repositories,
        pullRequests: PullRequestSettings(show: pullRequests),
        issues: IssueSettings(),
        workflowRuns: WorkflowRunSettings(),
        notifications: rules
    )
}

private func snapshot(_ items: [String: [Item]], errors: [String: RepositoryError] = [:]) -> Snapshot {
    Snapshot(fetchedAt: now, items: items, errors: errors)
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
        let failed = first.updated(with: snapshot(["shop": [pr(1)]], errors: ["o/gone": error]), projects: project)
        #expect(failed.items.count == 2)
        #expect(failed.knows(ItemSource(repository: "o/gone", kind: .pullRequest), in: "shop"))

        let back = snapshot(["shop": [pr(1), pr(2, repository: "o/gone"), pr(3, repository: "o/gone")]])
        #expect(EventDetector.events(known: failed, snapshot: back, projects: project).map(\.item.number) == [3])

        // A repository that failed on its first refresh isn't known yet.
        let never = KnownItems().updated(with: snapshot(["shop": [pr(1)]], errors: ["o/gone": error]), projects: project)
        #expect(!never.knows(ItemSource(repository: "o/gone", kind: .pullRequest), in: "shop"))
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

    struct AuthorCase: Sendable, CustomTestStringConvertible {
        var author: String
        var kind: AuthorKind
        var matches: [AuthorFilter]
        var testDescription: String { author }
    }

    @Test("the author filter matches me, bots and others", arguments: [
        AuthorCase(author: "yabepa", kind: .me, matches: [.any, .me]),
        AuthorCase(author: "octocat", kind: .other, matches: [.any, .others]),
        AuthorCase(author: "dependabot[bot]", kind: .bot, matches: [.any, .bots]),
        // A `[bot]` login counts as a bot even where the account type didn't say.
        AuthorCase(author: "renovate[bot]", kind: .other, matches: [.any, .bots]),
    ])
    func authorFilter(_ author: AuthorCase) {
        let item = pr(author: author.author, authorKind: author.kind)
        #expect(AuthorFilter.allCases.filter { $0.matches(item) } == author.matches)
    }

    @Test("a rule has to name the event and match the author")
    func rules() {
        let defaults = settings()
        #expect(NotificationRules.shouldNotify(event(), settings: defaults))
        #expect(!NotificationRules.shouldNotify(event(.prMerged), settings: defaults))

        let own = settings(rules: [NotificationRule(event: .prMerged, authors: .me), NotificationRule(event: .prOpened, authors: .bots)])
        #expect(!NotificationRules.shouldNotify(event(), settings: own))
        #expect(NotificationRules.shouldNotify(event(author: "dependabot[bot]", authorKind: .bot), settings: own))
        #expect(NotificationRules.shouldNotify(event(.prMerged, author: "yabepa", authorKind: .me), settings: own))
        #expect(!NotificationRules.shouldNotify(event(.prMerged), settings: own))

        #expect(!NotificationRules.shouldNotify(event(), settings: settings(rules: [])))
    }

    @Test("hidden authors are never notified")
    func hiddenAuthors() {
        #expect(!NotificationRules.shouldNotify(event(author: "Dependabot[bot]", authorKind: .bot), settings: settings(), hiddenAuthors: ["dependabot[bot]"]))
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
