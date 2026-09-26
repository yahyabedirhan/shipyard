[Spec #54](https://github.com/yahyabedirhan/shipyard/issues/54) | Tickets: #55–#66, #14 | QA: #67–#70 | [Design](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-0.0.2/docs/low-level-design.md) | [Configuration docs](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-0.0.2/docs/configuration.md) | [Decisions](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-0.0.2/.handoff/2026-09-26-shipyard-0.0.2-decisions.md)

## Why the change

Shipyard 0.0.2 makes it a superset of ghbar through configuration, while the maintainer's own file keeps working unchanged. Projects filter whose items they show, which states and whether a PR waits on your review; they watch repository groups instead of hand-listed repositories, and they arrange their rows. New users start from a preset, and the skill installs again.

## Special things to note

- **Sign-in without `gh` is built but switched off:** it waits on #23. `OAuthApp.clientID` (`DeviceFlow.swift`) is still the placeholder, so the connect screen shows Sign in with GitHub as unavailable with its reason, and `gh` stays the way in. Setting the ID is a one-line change. This PR is only **part of #14**, which stays open, and the README already describes the sign-in.
- **Behaviour changes worth a look:**
  - The closed and finished windows are part of a project's listing (ADR 0003), so `closed-window-days = 0` no longer notifies `pr.merged`/`pr.closed`, and `finished-window-hours = 0` no longer notifies finished runs.
  - The first time the review search finds a PR, it raises both `pr.opened` and `pr.review_requested`, so a project with both rules gets two notifications.
  - With several projects, the All tab sorts rows across projects within each kind.
  - `incoming-contributions` hides bots in its Review requests project too.
  - A failed review search keeps the last results.
- **QA is non-blocking:** #67 (group and sort), #68 (fold), #69 (Show more) and #70 (preset onboarding) carry the real-menu checks and don't hold this PR. Agents took the screenshots below in the real app with a test config that watches public repositories only. Clicking inside the panel wasn't possible, so folding and the keys weren't shot.
  - Your `config.toml` and `state.json` were restored from backups afterwards.
  - `.scratch/shipyard-0-0-2/mac.lock` is kept with the backups; remove it when you're happy.
  - `/Applications/Shipyard.app` is this branch's build (05e285e).

## Change outline

The app on a real Mac, build 05e285e:

| List: `group-by = "repository"`, `subsections = true`, `show-first = 4` | List: `group-by = "date"`, `show-first = 3` |
|---|---|
| ![Repository subsections with Show more](https://raw.githubusercontent.com/yahyabedirhan/shipyard/9a5ca8283245a9cdbaafe6a09b8eb90bbeaf9771/0.0.2-repo-subsections-showfirst.png) | ![Date groups with Show more](https://raw.githubusercontent.com/yahyabedirhan/shipyard/9a5ca8283245a9cdbaafe6a09b8eb90bbeaf9771/0.0.2-date.png) |
| **Tabs: the All tab keeps its look, by kind** | **Onboarding starts with a preset** |
| ![Tabs layout, All tab](https://raw.githubusercontent.com/yahyabedirhan/shipyard/9a5ca8283245a9cdbaafe6a09b8eb90bbeaf9771/0.0.2-tabs.png) | ![Preset step](https://raw.githubusercontent.com/yahyabedirhan/shipyard/9a5ca8283245a9cdbaafe6a09b8eb90bbeaf9771/0.0.2-presets.png) |

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

[[projects]]
name = "Everything of mine"
repositories = ["owned", "organizations", "my-org/*", "owner/name"]

[[projects]]
name = "Review requests"
repositories = ["anywhere"]           # needs review-requested = true, PRs only
issues = { show = false }
```

One refresh, from the configuration to the menu. `Listing` is now the only place that decides what a project has, so counts and notifications follow it:

```diff
 refresh()
+  RepositoryResolver.resolve(selectors)          at launch, on edit, on ⌘R, else hourly
-  GitHubClient.fetch(repositories)               one GraphQL request
+  GitHubClient.fetch(projects, resolved)         batches of 25; first batch carries the review search
+  Listing.items(project, snapshot)               kind, window, drafts, states, authors, review-requested
-  MenuModel.build(snapshot, config)             grouped by kind, hide-authors checked here
+  MenuModel.build(listings, …)                   Arrangement.groups: group, sort, fold, cap
-  notify(snapshot)                               hide-authors checked again
+  notify(listings)                               only listed items notify; every item stays known
```

Where the new responsibilities live:

```diff
 Sources/ShipyardCore/
   Config/
+    Selectors.swift          author and repository selectors: parse, match, hints
+    Presets.swift            my-agents, incoming-contributions, review-queue as commented files
+    PresetSetting.swift      the third writer: a preset only over a version-only file
   GitHub/
+    RepositoryResolver.swift groups and wildcards to repositories, paged, kept on failure
   Items/
+    Listing.swift            what a project lists, used by the menu, the counts and notifications
   Menu/
+    Arrangement.swift        groups, sort, folds, show-first
   Onboarding/
+    PresetChoice.swift       the preset step's state
 Sources/ShipyardApp/
+  Keychain.swift             the token store for the device flow
   UI/
+    Components+Groups.swift  subheaders (fold), dividers, Show more
     Onboarding/
+      PresetPicker.swift     native radio groups
 skills/shipyard/
~   SKILL.md                  selectors, filters, groups, arrangement; valid YAML frontmatter
+   presets.md                the three presets, tested equal to the app's
```

Commits, one per ticket: #55 `887d33c`, #57 `fbb70ca`, #56 `aae03e7`, #14 `71431da` (part), #59 `7c1c559`, #62 `dbfc390`, #58 `f87ea62`, #60 `6421bb8`, #63 `f3d1687`, #61 `b52835b`, #65 `f23a938`, #64 `6a7f547`, #66 `8b546fd`, and the final review's tidy-up in `05e285e`. `make test`: 608 tests pass. The release build has no warnings.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
