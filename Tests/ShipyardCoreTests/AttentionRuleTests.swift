import Foundation
@testable import ShipyardCore
import Testing

private let now = Date(timeIntervalSince1970: 1_790_337_600)

private func item(
    _ number: Int = 1,
    kind: ItemKind = .pullRequest,
    state: ItemState = .open,
    checks: ChecksState = .pending,
    reviewRequested: Bool = false,
    updatedAt: Date = now
) -> Item {
    Item(
        kind: kind,
        repository: "o/r",
        number: number,
        title: "t",
        url: URL(string: "https://github.com/o/r/\(kind.rawValue)/\(number)")!,
        author: "a",
        authorKind: .other,
        state: state,
        checks: checks,
        reviewRequestedFromViewer: reviewRequested,
        createdAt: now,
        updatedAt: updatedAt,
        closedAt: state.isOpen ? nil : now
    )
}

typealias Toggles = Configuration.AttentionToggles

@Suite("Needs-attention rule")
struct AttentionRuleTests {
    /// One case of the rule: whether the item was seen before its latest
    /// change, its standing reasons, the toggles, and the answer.
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var changedSinceSeen = false
        var reviewRequested = false
        var checksFailed = false
        var toggles = Toggles()
        var expected: Bool
        var testDescription: String { name }
    }

    @Test("an open item needs attention for the reasons its toggles allow", arguments: [
        Case(name: "unseen counts", expected: true),
        Case(name: "unseen off", toggles: Toggles(unseen: false), expected: false),
        Case(name: "unseen off, review requested", reviewRequested: true, toggles: Toggles(unseen: false), expected: true),
        Case(name: "unseen off, checks failed", checksFailed: true, toggles: Toggles(unseen: false), expected: true),
        Case(name: "unseen off, review toggle off", reviewRequested: true, toggles: Toggles(unseen: false, reviewRequested: false), expected: false),
        Case(name: "unseen off, checks toggle off", checksFailed: true, toggles: Toggles(unseen: false, checksFailed: false), expected: false),
        Case(name: "changed counts", changedSinceSeen: true, expected: true),
        Case(name: "changed off", changedSinceSeen: true, toggles: Toggles(changed: false), expected: false),
        Case(name: "changed off, review requested", changedSinceSeen: true, reviewRequested: true, toggles: Toggles(changed: false), expected: true),
        Case(name: "changed off, checks failed", changedSinceSeen: true, checksFailed: true, toggles: Toggles(changed: false), expected: true),
    ])
    func rule(_ rule: Case) {
        var attention = Attention()
        let current = item(checks: rule.checksFailed ? .failed : .pending, reviewRequested: rule.reviewRequested)
        if rule.changedSinceSeen {
            attention.markSeen(item(updatedAt: now.addingTimeInterval(-60)), at: now)
        }
        #expect(attention.needsAttention(current, toggles: rule.toggles) == rule.expected)
    }

    @Test("seeing an item clears every reason until its fingerprint changes")
    func seenClearsEverything() {
        var attention = Attention()
        let current = item(checks: .failed, reviewRequested: true)
        attention.markSeen(current, at: now)

        #expect(!attention.needsAttention(current, toggles: Toggles()))
        #expect(attention.needsAttention(item(checks: .failed, reviewRequested: true, updatedAt: now + 1), toggles: Toggles()))
    }

    @Test("closed and merged items never need attention", arguments: [ItemState.closed, .merged])
    func closedNever(state: ItemState) {
        let attention = Attention()
        #expect(!attention.needsAttention(item(state: state, checks: .failed, reviewRequested: true), toggles: Toggles()))
    }

    @Test("a failed run needs attention until seen, by `unseen` or `checks-failed`; running and succeeded runs never do")
    func runs() {
        var attention = Attention()
        let failed = item(kind: .workflowRun, state: .failed, checks: .failed)
        #expect(attention.needsAttention(failed, toggles: Toggles()))
        #expect(attention.needsAttention(failed, toggles: Toggles(unseen: false)))
        #expect(!attention.needsAttention(failed, toggles: Toggles(unseen: false, checksFailed: false)))
        #expect(!attention.needsAttention(item(kind: .workflowRun, state: .running), toggles: Toggles()))
        #expect(!attention.needsAttention(item(kind: .workflowRun, state: .succeeded, checks: .passed), toggles: Toggles()))
        attention.markSeen(failed, at: now)
        #expect(!attention.needsAttention(failed, toggles: Toggles()))
    }

    @Test("drafts are open and can need attention")
    func drafts() {
        #expect(Attention().needsAttention(item(state: .draft), toggles: Toggles()))
    }

    @Test("counts split by kind, and an item listed twice counts once")
    func counts() {
        let pr = item(1)
        let counts = Attention().counts(
            [pr, pr, item(2, kind: .issue), item(3, kind: .workflowRun, state: .failed, checks: .failed), item(4, state: .merged)],
            toggles: Toggles()
        )
        #expect(counts == AttentionCounts(pullRequests: 1, issues: 1, workflowRuns: 1))
        #expect(counts.total == 3)
        #expect(counts[.issue] == 1)
    }

    @Test("prune drops records of items gone for 30 days and keeps present ones fresh")
    func prune() {
        var attention = Attention()
        let kept = item(1)
        let gone = item(2)
        attention.markSeen(kept, at: now)
        attention.markSeen(gone, at: now)

        // Within a day nothing is rewritten.
        let rewrote = attention.prune(present: [kept], at: now + 3_600)
        #expect(!rewrote)

        // Every day the present one is bumped; the gone one ages out after 30 days.
        var day = now
        for _ in 1...30 {
            day += 86_400
            attention.prune(present: [kept], at: day)
        }
        #expect(attention.seen[kept.id] != nil)
        #expect(attention.seen[kept.id]?.present == day)
        #expect(attention.seen[gone.id] != nil)

        let dropped = attention.prune(present: [kept], at: day + 1)
        #expect(dropped)
        #expect(attention.seen[gone.id] == nil)
        #expect(attention.seen[kept.id] != nil)
    }

    @Test("menu bar label text per style")
    func labelText() {
        let counts = AttentionCounts(pullRequests: 2, issues: 1, workflowRuns: 0)
        #expect(MenuBarLabel(counts, style: .total).text == "3")
        #expect(MenuBarLabel(counts, style: .perKind).text == "2 PRs · 1 issue")
        #expect(MenuBarLabel(AttentionCounts(pullRequests: 1, workflowRuns: 3), style: .perKind).text == "1 PR · 3 runs")
        #expect(MenuBarLabel(AttentionCounts(), style: .perKind).text == nil)
        #expect(MenuBarLabel(counts, style: .none) == .hidden)
    }
}
