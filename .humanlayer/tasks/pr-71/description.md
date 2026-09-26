[Spec #54](https://github.com/yahyabedirhan/shipyard/issues/54) | Tickets: #55–#66, #14, #23, #72–#74, #78–#82 | QA: #67–#70, #76 | [Design](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-0.0.2/docs/low-level-design.md) | [Configuration docs](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-0.0.2/docs/configuration.md) | [Decisions](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-0.0.2/.handoff/2026-09-26-shipyard-0.0.2-decisions.md)

## Why the change

Shipyard 0.0.2 makes it a superset of ghbar through configuration, lets people sign in without `gh`, and gives it its own logo, while the maintainer's own file keeps working unchanged.

## Special things to note

- **Merge with a merge commit, not a squash or rebase.** Issues, this description and the README embed screenshots by raw URLs pinned to commits on this branch (such as `23901d4` and `5ca2f60`); a merge commit keeps those commits reachable from `main`.
- **Behaviour changes worth a look:**
  - **The connect screen is redesigned.** It greets the user, and Sign in with GitHub leads, with the `gh` way folded under it. When `gh` is still signed in after Sign out, **Connect with `gh`** leads instead. "Try again" is now "Connect with `gh`", and there's no `gh auth logout` line. Shipyard's OAuth App (`Ov23li68GZnClULrjIFj`) is compiled in. After each `make install`, macOS may ask once whether the new copy may use the Keychain item: choose Always Allow.
  - **`closed-window` and `finished-window` replace `closed-window-days` and `finished-window-hours`.** They take a whole number and one unit, such as `"30m"`, `"12h"` or `"7d"`. The old keys still work, with a warning in the banner and `config-status.json` saying what to write instead. They stay in the schema as deprecated, and setting both forms in one table is an error.
  - **While the rate limit pauses refreshing, the menu is still re-listed** from the last snapshot at every refresh interval, so a 30-minute window ends on time.
  - **The logo and the menu bar item are drawn from our own path** (`Brand/Sailboat.swift`), because SF Symbols can't be used in an app icon. The icon, the menu bar item and the connect screen's badge share that one figure and `Brand/Logo.swift`'s colours, and a test compares the badge with the committed icon.
  - From earlier in this PR: the closed and finished windows are part of a project's listing (ADR 0003), so a window of `0` no longer notifies merged, closed or finished items. A PR the review search finds for the first time raises both `pr.opened` and `pr.review_requested`. With several projects, the All tab sorts rows across projects within each kind. `incoming-contributions` hides bots in its Review requests project too, and a failed review search keeps its last results.
- **QA is done:** #67–#70 and #76 were checked by the maintainer in the real menu, and the hover card, the connect screen, the copy button, the logo and the badge were each tried round by round on their own tickets. The preset screenshot below was retaken from the installed build `2ecf1c4` with a version-only test config, and the maintainer's `config.toml` was restored and checked with `cmp` afterwards. The other three are still from build `05e285e`, because a permission check stopped their retake.

## Change outline

The app on a real Mac. The preset step is build 2ecf1c4; the others are build 05e285e:

| List: `group-by = "repository"`, `subsections = true`, `show-first = 4` | List: `group-by = "date"`, `show-first = 3` |
|---|---|
| ![Repository subsections with Show more](https://raw.githubusercontent.com/yahyabedirhan/shipyard/23901d4e16460ce4f5bdbfd211eea000d84cf2d4/docs/assets/shipyard-0.0.2/repo-subsections-showfirst.png) | ![Date groups with Show more](https://raw.githubusercontent.com/yahyabedirhan/shipyard/23901d4e16460ce4f5bdbfd211eea000d84cf2d4/docs/assets/shipyard-0.0.2/date.png) |
| **Tabs: the All tab keeps its look, by kind** | **Onboarding starts with a preset** |
| ![Tabs layout, All tab](https://raw.githubusercontent.com/yahyabedirhan/shipyard/23901d4e16460ce4f5bdbfd211eea000d84cf2d4/docs/assets/shipyard-0.0.2/tabs.png) | ![Preset step: How will you use Shipyard?, with You and your agents, Incoming contributions and Review queue](https://raw.githubusercontent.com/yahyabedirhan/shipyard/5ca2f6044bca640653567fb267c413c7ecead440/docs/assets/shipyard-0.0.2/presets.png) |

What a user can now write, all optional, with every 0.0.1 file still valid:

```toml
[defaults]
group-by = "repository"      # kind (default) | repository | date | author | none
subsections = true           # unset: dividers in the list, subheaders in a tab
sort-by = "updated"          # updated | created | title; open always first
show-first = 5               # 0 = all; then "Show N more"
archived = false             # for groups and wildcards
forks = true

[defaults.pull-requests]
authors = { hide = ["me", "bots"] }   # me | others | bots | @login; show minus hide
states = ["open"]                     # open | merged | closed
review-requested = true               # only PRs waiting on you, teams included
closed-window = "30m"                 # s | m | h | d; was closed-window-days

[defaults.workflow-runs]
finished-window = "3h"                # was finished-window-hours

[[projects]]
name = "Everything of mine"
repositories = ["owned", "organizations", "my-org/*", "owner/name"]

[[projects]]
name = "Review requests"
repositories = ["anywhere"]           # needs review-requested = true, PRs only
issues = { show = false }
```

One refresh, from the configuration to the menu. `Listing` is the only place that decides what a project has, so counts and notifications follow it:

```diff
 refresh()
+  paused by the rate limit?                      list again from the last snapshot; timer ≤ the refresh interval
+  RepositoryResolver.resolve(selectors)          at launch, on edit, on ⌘R, else hourly
-  GitHubClient.fetch(repositories)               one GraphQL request
+  GitHubClient.fetch(projects, resolved)         batches of 25; first batch carries the review search
+  Listing.items(project, snapshot)               kind, window (in seconds), drafts, states, authors, review-requested
-  MenuModel.build(snapshot, config)             grouped by kind, hide-authors checked here
+  MenuModel.build(listings, …)                   Arrangement.groups: group, sort, fold, cap
-  notify(snapshot)                               hide-authors checked again
+  notify(listings)                               only listed items notify; every item stays known
```

Where the new responsibilities live. Since the last review, the work added hover help, the connect screen, the logo and the windows:

```diff
 Sources/ShipyardCore/
   Config/
+    Selectors.swift            author and repository selectors: parse, match, hints
+    Presets.swift              my-agents ("You and your agents"), incoming-contributions, review-queue
+    PresetSetting.swift        the third writer: a preset only over a version-only file
+    WindowDuration.swift       "30m" to seconds and back; the nearest spelling for a near miss
   GitHub/
+    RepositoryResolver.swift   groups and wildcards to repositories, paged, kept on failure
~    ProjectQuery.swift         + avatars, branches, +/− lines, files, review decision for the row card
   Items/
+    Listing.swift              what a project lists, used by the menu, the counts and notifications
   Menu/
+    Arrangement.swift          groups, sort, folds, show-first
+    HoverHelpPlacement.swift   pure: the card sits under or over the hovered view, inside the panel
+    PanelText+RowCard.swift    a row's card: only what the row doesn't show
~    PanelText+Connect.swift    one welcoming screen per signed-out state, the lead way first
 Sources/ShipyardApp/
+  Keychain.swift               the token store for the device flow
+  Brand/
+    Sailboat.swift             the one figure: app icon, menu bar item, badge (make-icon.swift compiles it)
+    Logo.swift                 olive khaki squircle, sheen and cream figure colour
+    LogoBadge.swift            the logo in the connect screen's heading
+    SailboatImage.swift        the menu bar item, a template image
   UI/
+    HoverHelp.swift            .hoverHelp in place of .help: one card the panel draws
~    Components.swift           CopyButton (Copy → Copied, back after 10 s); CountBadge fades its colour only
~    Onboarding/ConnectView.swift   logo, greeting, stacked full-width ways in, the gh disclosure and install hint
 Packaging/Icon/
~  AppIcon.icns                 the olive khaki sailboat (make icon); alternates/ keeps the others
 skills/shipyard/
~   SKILL.md                    selectors, filters, groups, arrangement, closed-window; valid YAML frontmatter
+   presets.md                  the three presets, tested equal to the app's
 README.md                      the logo, rewritten for newcomers, examples tested by ReadmeDocumentTests
```

Commits, one per ticket: #55 `887d33c`, #57 `fbb70ca`, #56 `aae03e7`, #14 `71431da` and `f2d6408`, #59 `7c1c559`, #62 `dbfc390`, #58 `f87ea62`, #60 `6421bb8`, #63 `f3d1687`, #61 `b52835b`, #65 `f23a938`, #64 `6a7f547`, #66 `8b546fd` (its wording `c1a858c`, `fffcae0`), the first review's tidy-up `05e285e`, #73 `23901d4`, `e164484`, `45b4518`, #74 `12ba5be`, `8d29622`, `0b87422`, #72 hover help (merged from #75 as `fa15396`), #78 the connect screen `fc5718e`, `9c16c5e`, `0511bde`, `72249d5`, #79 the copy button `856da7f`, `77aafcc`, `8ef3542`, #80 the logo `bb91153`, `deee81e`, `ac23c0a`, `0ab120f`, `6d76fd9`, #81 windows `2cc164a`, #82 the badge `2ecf1c4`, the version bump `79856d5`, the CI fix `ed9afc6`, and the wrap-up: the README's logo and new preset shot `5ca2f60`, and the final review's design-doc fix `719948e`. `make test`: 650 tests pass. The release build has no warnings.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_015UKPStz8JFUtJhtiecYPRJ
