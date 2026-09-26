[#72 Replace native tooltips with a nicer hover help](https://github.com/yahyabedirhan/shipyard/issues/72) | [stacked on #71](https://github.com/yahyabedirhan/shipyard/pull/71) | [research](docs/references/macos-hover-help.md)

## Why the change

macOS's native tooltips came late, looked dated, got cut off at the panel's edge and only repeated the row. This PR replaces them with a card the panel draws itself: header buttons get short help, and each row gets a card with the avatar, full title and facts the row doesn't show.

## Special things to note

- The row card reads some extra plain GraphQL fields (`avatarUrl`, `baseRefName`, `additions`, `deletions`, `changedFiles`, `reviewDecision`), which add no cost. Labels were tried and dropped: a dry run put 5 repositories at 11 points instead of 4 (recorded in `docs/references/github-rate-limits.md`).
- The maintainer tried every round in the real menu. The placement, the words and the attention reasons are tested in the core, but the drawing and the timing aren't. How each decision was reached, and what was tried and dropped, is in the decision log on #72 and on this PR.
- The popover runner-up stays one line away (`HoverHelp.style = .popover`). It isn't the default because a popover is a window and may take the arrow keys.

## Change outline

`.help` becomes `.hoverHelp`, and the panel draws one card for every view:

```text
Panel  .hoverHelpHost()                 # one overlay on the panel's frame, so the scroll view's clip can't cut it
├── Layout / Refresh / Settings / account / cut-off tab   .hoverHelp("Refresh (⌘R)")        context: toolbar
└── item row                                             .hoverHelp(PanelText.rowCard(row))  context: row
```

Each context has its own timing, in `HoverHelp.timing(_:)`:

```text
toolbar  delay 500 ms · warm 600 ms · grace 90 ms   → glides from button to button
row      delay 1000 ms · no warmth · no grace       → closes as the pointer leaves; every row waits again
```

What it looks like in the real panel (dark mode, the public shipyard project):

| Pull request | Checks running |
|---|---|
| ![A pull request's card: avatar and two-line title, branches, +9,372 −815 in 133 files, checks passed, comments and last update](https://raw.githubusercontent.com/yahyabedirhan/shipyard/86f625d44bcfc7f97b6f64a7b0ae910c120d48c5/docs/assets/hover-help/pull-request-card.png) | ![A pull request's card with checks running in amber](https://raw.githubusercontent.com/yahyabedirhan/shipyard/86f625d44bcfc7f97b6f64a7b0ae910c120d48c5/docs/assets/hover-help/pull-request-checks-running.png) |

| Issue, one-line title | Issue, two-line title | Header button |
|---|---|---|
| ![An issue's card: the avatar centred beside a one-line title](https://raw.githubusercontent.com/yahyabedirhan/shipyard/86f625d44bcfc7f97b6f64a7b0ae910c120d48c5/docs/assets/hover-help/issue-one-line-title.png) | ![An issue's card: the avatar centred beside a two-line title](https://raw.githubusercontent.com/yahyabedirhan/shipyard/86f625d44bcfc7f97b6f64a7b0ae910c120d48c5/docs/assets/hover-help/issue-two-line-title.png) | ![Refresh (⌘R) under the refresh button](https://raw.githubusercontent.com/yahyabedirhan/shipyard/86f625d44bcfc7f97b6f64a7b0ae910c120d48c5/docs/assets/hover-help/toolbar-refresh.png) |

The row card is built in the core, so tests reach it without SwiftUI:

```swift
struct RowCard {
    avatarURL: URL?          // author, or a run's actor
    headline: String         // full title; a run's commit or PR title
    reasons: [Attention.Reason]  // tags: review requested (amber), checks failed (red)
    facts: [[Fact]]          // one line each, drawn as SF Symbol + short value
}
enum Fact { branches, size, files, review, checks, comments, reviews, updated, trigger, attempt, duration }
```

```text
(👤) Fix checkout totals              ← avatar centred on the title, one line or three
     ( 👁 Your review is requested )
     ⎇ fix-totals → main
     ± +120 −43   ⧉ 6 files
     ✓ Approved   ✓ Checks passed
     💬 2  👤✓ 1  ↻ 3h ago
```

Where the data comes from:

```diff
 Item
+  avatarURL: URL?
+  details: ItemDetails     # head/base branch, size, reviewDecision, comments, reviews; a run's title, event, attempt
                            # not in the fingerprint, so it never makes a seen item "changed"
 Attention
+  reasons(item, toggles) -> [Reason]    # unseen | changed | reviewRequested | checksFailed
   needsAttention(item, toggles) = !reasons.isEmpty
```

Files:

```diff
 Sources/ShipyardApp/UI/
+├── HoverHelp.swift                 # hoverHelp, hoverHelpHost, timing, card and row card views
 Sources/ShipyardCore/
+├── Menu/HoverHelpPlacement.swift   # pure: under or over the view, inside the panel
+├── Menu/PanelText+RowCard.swift    # pure: RowCard, its facts and their words
 ├── Items/Item.swift                # + avatarURL, ItemDetails, ReviewDecision
 ├── Items/Attention.swift           # + reasons
 ├── GitHub/ProjectQuery.swift       # + plain fields for the card
 └── GitHub/WorkflowRuns.swift       # + event, run_attempt, actor avatar
```

Where hover help wasn't worth it, it's gone: the chevrons, Copy, the skill card's ✕ and the picker's lock each keep a VoiceOver label. Note and error rows now wrap instead of ending in "…".

🤖 Generated with [Claude Code](https://claude.com/claude-code)
