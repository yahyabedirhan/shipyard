import Foundation

/// A row's hover card: only what the row doesn't already show. Its title
/// and second line are on the row, so the card has the author's avatar, the
/// rest of the item (branches, size, review, comments, when it last moved,
/// what started a run and how long it took), and whether it waits on the
/// viewer's review or failed its checks.
public struct RowCard: Hashable, Sendable {
    /// The author's avatar (a run: whoever triggered it).
    public var avatarURL: URL?
    /// The item's full title, which the row may cut off; a run's title
    /// (its commit's message or pull request's title), where the row shows
    /// the workflow's name.
    public var headline: String
    /// The facts, a line of them at a time.
    public var facts: [[Fact]]
    /// What kind of item it is, for the words of `reasons`.
    public var kind: ItemKind
    /// The reasons the row needs attention that the card shows, as tags:
    /// a review request and failed checks. New and changed aren't worth a
    /// tag; the row's attention dot says as much.
    public var reasons: [Attention.Reason]
    /// The same in words: "Your review is requested · Checks failed";
    /// `nil` when there are none.
    public var attention: String?

    /// Each line of facts in words: "+120 −43 · 6 files".
    public var lines: [String] {
        facts.map { $0.map(PanelText.fact).joined(separator: " · ") }
    }

    /// What VoiceOver reads as the row's hint: the lines and the
    /// attention (the row's label already has its title).
    public var spoken: String {
        (lines + [attention].compactMap { $0 }).joined(separator: ". ")
    }

    /// One thing the card says, which the app draws with its icon and
    /// colour and VoiceOver reads in words (`PanelText.fact`).
    public enum Fact: Hashable, Sendable {
        /// A pull request's head branch and the branch it merges into.
        case branches(head: String, base: String)
        /// A pull request's lines added and removed.
        case size(additions: Int, deletions: Int)
        case files(Int)
        case review(ReviewDecision)
        case checks(ChecksState)
        /// Comments; zero says "No comments".
        case comments(Int)
        case reviews(Int)
        /// When it last changed, as an age: "5m", "now".
        case updated(String)
        /// What started a run (GitHub's event name) and who.
        case trigger(event: String?, by: String)
        /// A run's attempt, past the first.
        case attempt(Int)
        /// How long a run ran, or has been running: "3m 12s".
        case duration(String, running: Bool)
        /// A ping's body, whole.
        case body(String)
        /// What clicking a ping does.
        case action(PingAction)
        /// Why a ping's action failed at its last click.
        case failure(String)
    }
}

extension PanelText {
    /// A row's hover card, in either layout.
    ///
    /// A pull request: "feat/hover-help → main", "+120 −43 · 6 files",
    /// "Approved · Checks passed", "3 comments · 1 review · updated 5m ago".
    /// An issue: its comments and when it was updated. A run: "Push by
    /// yahyabedirhan · attempt 2", "Took 3m 12s" (or "Running for 2m"). A
    /// ping: its body, "Opens https://…" (or the app), and why that failed.
    public static func rowCard(_ row: MenuRow, now: Date) -> RowCard {
        let details = row.item.details
        var facts: [[RowCard.Fact]] = []
        switch row.kind {
        case .pullRequest:
            if let head = details.headBranch, let base = details.baseBranch {
                facts.append([.branches(head: head, base: base)])
            }
            if let additions = details.additions, let deletions = details.deletions {
                facts.append([.size(additions: additions, deletions: deletions)] + (details.changedFiles.map { [.files($0)] } ?? []))
            }
            let review: [RowCard.Fact] = (details.review.map { [.review($0)] } ?? [])
                + (row.checks.flatMap { $0 == .none ? nil : [.checks($0)] } ?? [])
            if !review.isEmpty { facts.append(review) }
            facts.append(activity(row, now: now))
        case .issue:
            // An issue's card is its title and its tags; a
            // lone "No comments" under them would be noise.
            let activity = activity(row, now: now).filter { $0 != .comments(0) }
            if !activity.isEmpty { facts.append(activity) }
        case .workflowRun:
            let attempt: [RowCard.Fact] = details.runAttempt.flatMap { $0 > 1 ? [.attempt($0)] : nil } ?? []
            facts.append([.trigger(event: details.runEvent, by: row.author)] + attempt)
            facts.append([runTime(row, now: now)])
        case .ping:
            // Its whole body (the row may cut it off), where clicking it
            // takes you, and why that last failed.
            let ping = row.item.ping
            if let body = ping?.body { facts.append([.body(body)]) }
            if let action = ping?.action { facts.append([.action(action)]) }
            if let failure = ping?.failure { facts.append([.failure(failure)]) }
        }
        let headline = row.kind == .workflowRun ? (details.runTitle ?? row.title) : row.title
        let tagged = row.attentionReasons.filter { $0 == .reviewRequested || $0 == .checksFailed }
        let reasons = tagged.map { attentionWord($0, kind: row.kind) }
        return RowCard(
            avatarURL: row.item.avatarURL,
            headline: headline,
            facts: facts,
            kind: row.kind,
            reasons: tagged,
            attention: reasons.isEmpty ? nil : reasons.joined(separator: " · ")
        )
    }

    /// A fact in words, for VoiceOver and tests: "fix-totals → main",
    /// "+120 −43", "6 files", "Approved", "Checks passed", "3 comments",
    /// "1 review", "updated 5m ago", "Push by yahyabedirhan", "attempt 2",
    /// "Took 3m 12s", "Running for 2m".
    public static func fact(_ fact: RowCard.Fact) -> String {
        switch fact {
        case .branches(let head, let base): "\(head) → \(base)"
        case .size(let additions, let deletions): "+\(additions) −\(deletions)"
        case .files(let count): count == 1 ? "1 file" : "\(count) files"
        case .review(let review): reviewWord(review)
        case .checks(let state): checks(state) ?? ""
        case .comments(let count): count == 0 ? "No comments" : count == 1 ? "1 comment" : "\(count) comments"
        case .reviews(let count): count == 1 ? "1 review" : "\(count) reviews"
        case .updated(let age): age == "now" ? "updated now" : "updated \(age) ago"
        case .trigger(let event, let by): "\(event.map(eventWord) ?? "Run") by \(by)"
        case .attempt(let attempt): "attempt \(attempt)"
        case .duration(let time, let running): running ? "Running for \(time)" : "Took \(time)"
        case .body(let text): text
        case .action(.url(let url)): "Opens \(url.absoluteString)"
        case .action(.app(let app)): "Opens \(app)"
        case .action(.herdr(let id)): "Focuses \(id) in Herdr"
        case .failure(let reason): reason
        }
    }

    static func reviewWord(_ review: ReviewDecision) -> String {
        switch review {
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .reviewRequired: "Review required"
        }
    }

    /// "3 comments · 1 review · updated 5m ago": the counts that aren't
    /// zero ("No comments" when none are), and when it last changed, if
    /// that's later than the age the row shows.
    static func activity(_ row: MenuRow, now: Date) -> [RowCard.Fact] {
        let details = row.item.details
        var facts: [RowCard.Fact] = []
        if details.comments > 0 || details.reviews == 0 { facts.append(.comments(details.comments)) }
        if details.reviews > 0 { facts.append(.reviews(details.reviews)) }
        if row.item.updatedAt.timeIntervalSince(row.since) >= 60 {
            facts.append(.updated(age(max(0, now.timeIntervalSince(row.item.updatedAt)))))
        }
        return facts
    }

    /// What started a run, as GitHub's web names its events.
    static func eventWord(_ event: String) -> String {
        switch event {
        case "push": "Push"
        case "pull_request", "pull_request_target": "Pull request"
        case "schedule": "Schedule"
        case "workflow_dispatch": "Manual run"
        case "release": "Release"
        case "merge_group": "Merge queue"
        default: event.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// How long a run has been running, or ran once it finished.
    static func runTime(_ row: MenuRow, now: Date) -> RowCard.Fact {
        let start = row.item.createdAt
        guard let end = row.item.closedAt else { return .duration(duration(now.timeIntervalSince(start)), running: true) }
        return .duration(duration(end.timeIntervalSince(start)), running: false)
    }

    /// "42s", "3m 12s", "1h 5m".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        switch total {
        case ..<60: return "\(total)s"
        case ..<3600: return total % 60 == 0 ? "\(total / 60)m" : "\(total / 60)m \(total % 60)s"
        default: return total % 3600 < 60 ? "\(total / 3600)h" : "\(total / 3600)h \(total % 3600 / 60)m"
        }
    }

    /// A reason a row needs attention in words: "New", "Changed since you
    /// saw it", "Your review is requested", "Checks failed" ("Run failed").
    public static func attentionWord(_ reason: Attention.Reason, kind: ItemKind) -> String {
        switch reason {
        case .unseen: "New"
        case .changed: "Changed since you saw it"
        case .reviewRequested: "Your review is requested"
        case .checksFailed: kind == .workflowRun ? "Run failed" : "Checks failed"
        }
    }
}
