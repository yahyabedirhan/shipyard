import SwiftUI

/// What the brand, building-block and component variants draw on: a row
/// of every kind in every state, a layout's actions that only record the
/// click, and a frame that names each specimen.
@MainActor
enum Gallery {
    static let now = Fixtures.now

    /// One row per kind and state the panel draws, with a title that says which.
    static let rows: [MenuRow] = [
        row(.pullRequest, .open, "Add a tab strip that scrolls", checks: .passed, attention: [.reviewRequested]),
        row(.pullRequest, .open, "Cache the All tab's rows", checks: .pending),
        row(.pullRequest, .open, "Fix the row heights in dark mode", checks: .failed, attention: [.checksFailed]),
        row(.pullRequest, .draft, "Sketch a denser row", checks: .none),
        row(.pullRequest, .merged, "Count attention once per item"),
        row(.pullRequest, .closed, "Try a sidebar layout"),
        row(.issue, .open, "Slow scroll in the All tab", attention: [.unseen]),
        row(.issue, .closed, "Hover cards cut off at the bottom"),
        row(.workflowRun, .running, "CI", branch: "feat/tabs-strip"),
        row(.workflowRun, .succeeded, "linux cli", branch: "main"),
        row(.workflowRun, .failed, "release", branch: "main", attention: [.checksFailed]),
        ping("PR ready for review", sender: "claude", attention: true),
        ping("Need your input on the schema", sender: "codex", attention: false),
        ping("Deploy finished", sender: "deploy-bot", attention: false),
        note("Tab order should follow recency"),
    ]

    static func rows(_ kind: ItemKind) -> [MenuRow] { rows.filter { $0.kind == kind } }

    static func row(_ kind: ItemKind, _ state: ItemState, _ title: String, checks: ChecksState = .none, branch: String? = nil, attention: [Attention.Reason] = []) -> MenuRow {
        let number = 100 + abs(title.hashValue % 300)
        let repository = "shipyard-lab/harbor"
        let path = kind == .issue ? "issues" : kind == .workflowRun ? "actions/runs" : "pull"
        let item = Item(
            kind: kind,
            repository: repository,
            number: number,
            title: title,
            url: URL(string: "https://github.com/\(repository)/\(path)/\(number)-\(title.count)")!,
            author: kind == .workflowRun ? "yahyabedirhan" : "octocat",
            authorKind: .other,
            state: state,
            checks: kind == .workflowRun ? (state == .running ? .pending : state == .failed ? .failed : .passed) : checks,
            createdAt: now.addingTimeInterval(-3 * 3600),
            updatedAt: now.addingTimeInterval(-40 * 60),
            closedAt: state.isActive ? nil : now.addingTimeInterval(-20 * 60),
            activity: 4,
            branch: branch,
            details: ItemDetails(
                headBranch: kind == .pullRequest ? "feat/tabs-strip" : nil,
                baseBranch: kind == .pullRequest ? "main" : nil,
                additions: kind == .pullRequest ? 214 : nil,
                deletions: kind == .pullRequest ? 37 : nil,
                changedFiles: kind == .pullRequest ? 6 : nil,
                review: kind == .pullRequest ? .reviewRequired : nil,
                comments: 3,
                reviews: kind == .pullRequest ? 1 : 0,
                runTitle: kind == .workflowRun ? "feat: add a tab strip that scrolls" : nil,
                runEvent: kind == .workflowRun ? "push" : nil,
                runAttempt: kind == .workflowRun ? 1 : nil
            )
        )
        var row = MenuRow(item, needsAttention: !attention.isEmpty)
        row.attentionReasons = attention
        return row
    }

    static func ping(_ title: String, sender: String, attention: Bool) -> MenuRow {
        var item = Ping(
            id: title,
            title: title,
            projects: ["harbor"],
            sent: now.addingTimeInterval(-12 * 60),
            seen: attention ? nil : now,
            repository: "shipyard-lab/harbor",
            body: "Pick A or B in the pane.",
            sender: sender,
            action: .herdr("w1:t2")
        ).item
        item.number = 7
        var row = MenuRow(item, needsAttention: attention)
        row.attentionReasons = attention ? [.unseen] : []
        return row
    }

    static func note(_ title: String) -> MenuRow {
        MenuRow(Note(
            id: title,
            url: URL(string: "https://www.notion.so/note")!,
            number: 12,
            prefix: "HAR",
            title: title,
            labels: ["idea"],
            status: Note.open,
            created: now.addingTimeInterval(-2 * 86_400),
            edited: now
        ).item)
    }

    /// A layout's actions that do nothing: the gallery shows the views,
    /// not what they change.
    static let actions = LayoutActions(
        open: { _ in }, markSeen: { _ in }, dismiss: { _ in }, markAllSeen: { _ in },
        toggleCollapsed: { _ in }, toggleGroup: { _ in }, toggleShowMore: { _ in },
        openRepository: { _ in }, openPage: { _ in }, startNote: { _ in }
    )

    /// A group of `rows`, with a subheader, as a tab draws its kinds.
    static func group(_ title: String, rows: [MenuRow], folded: Bool = false, hidden: Int = 0) -> RowGroup {
        var group = RowGroup(
            id: GroupID(project: "harbor", key: .kind(rows.first?.kind ?? .pullRequest)),
            title: title,
            rows: rows,
            attentionCount: rows.filter(\.needsAttention).count,
            showsHeader: true,
            isFolded: folded
        )
        if hidden > 0 {
            group.hiddenRows = Array(repeating: rows[0], count: hidden)
        }
        return group
    }
}

/// A named specimen: a small caption over the view, on the panel's surface.
struct Specimen<Content: View>: View {
    let title: String
    var width: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            content
                .frame(width: width, alignment: .leading)
        }
    }
}

/// The panel's surface, the size of the panel, under a gallery's views.
struct PanelSurface<Content: View>: View {
    var width: CGFloat = Grid.panelWidth
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: width, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
            .environment(\.panelNow, Gallery.now)
    }
}
