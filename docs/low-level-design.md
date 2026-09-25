# Shipyard: low-level design

Agreed 2026-09-25. Terms are the ones in `CONTEXT.md`; the configuration decision is `docs/adr/0001-configuration-is-a-toml-file-agents-edit.md`; facts about GitHub's API are in `docs/references/`. When the code and this document disagree, fix one of them in the same change.

**For a newcomer, in one screen.** Shipyard is one Swift executable. `Shipyard` (the orchestrator) owns the app's lifecycle and runs a **refresh**. A refresh reads the **configuration**, fetches every project's items from GitHub, compares the result with what it saw last time to find **events**, sends the notifications the **rules** allow, and publishes a **menu model** the SwiftUI panel draws. Everything the app remembers about the user (seen items, collapsed sections, the last items it knew) is **app state**, kept apart from the configuration.

```text
config.toml ──▶ ConfigStore ─┐
                             ▼
GitHub ◀── GitHubClient ◀── Shipyard (refresh) ──▶ Notifier ──▶ macOS notifications
                             │   ▲
                             ▼   │ click / collapse
                        MenuModel ──▶ Panel (SwiftUI)
                             ▲
                       AppStateStore (seen, known, collapsed)
```

---

## 1. Requirements

### Capabilities

| # | Requirement |
|---|---|
| R1 | Live in the macOS menu bar as an icon plus one **attention count**; clicking it opens a panel. |
| R2 | Show one collapsible section per **project**, in configuration order. A project is one or more GitHub repositories. |
| R3 | In each project, list pull requests from anyone: open ones, then ones closed within the **closed window** (default 7 days), newest first. |
| R4 | Colour pull requests by GitHub's convention: open green, draft gray, merged purple, closed red. Open PRs show a check-status dot. |
| R5 | List issues the same way when the configuration turns them on (off by default). |
| R6 | List **workflow runs** when turned on (off by default): running now, plus finished within the last N hours (default 3), on the default branch and open PR branches. |
| R7 | Clicking an item opens it on GitHub and marks it **seen**. ⌥-click marks it seen without opening. "Mark all seen" exists per project and globally. Opening the panel marks nothing. |
| R8 | An open item **needs attention** when it is unseen, changed since seen (commits, comments, reviews, checks, review request), requests the user's review, or has failed checks. Closed items never do. |
| R9 | Send macOS notifications for **events** matched by **notification rules** (event + scope + author filter). Default: `pr.opened`, any author, all projects. |
| R10 | Refresh on an interval (default 120 s), when the panel opens, when the Mac wakes, when the configuration changes, and on ⌘R. |
| R11 | Read everything the user controls from `~/.config/shipyard/config.toml` (honouring `$XDG_CONFIG_HOME`), apply edits live, and publish a JSON Schema for it (referenced by `#:schema`, checked with `taplo check`). |
| R12 | Keep app state (seen, known items, collapsed sections, notified) in `~/Library/Application Support/Shipyard/state.json`, never in the configuration. |
| R13 | Onboarding: connect GitHub (reuse `gh`'s token silently, else device flow with the token in Keychain); then, whenever there are no projects, show the project picker, which writes projects to the configuration. |
| R14 | Offer to install the shipyard skill during onboarding and from the panel's menu, by running `npx -y skills add yahyabedirhan/shipyard -g -y` for the user. |
| R15 | Launch at login (on by default, configurable). |
| R10a | Spend at most `max-share-percent` (default 10%) of each GitHub hourly limit (GraphQL points, REST requests). If a refresh at the configured interval would spend more, stretch the interval and say so in the panel. |
| R10b | The limit is shared with everything else using your token (your agents' `gh` calls included). Below 20% remaining, refresh every 10 min; at 0, pause until the reset time. ⌘R still works while any limit remains. |
| R16 | Show the rate limit in the panel footer: remaining / limit per API and when it resets (ghbar's indicator). Configurable: `always` (default), `when-low`, `never`. When paused, the menu bar icon changes and a banner says why. |

### Rules and completion

- The configuration is **only** written by the project picker (R13); every other change comes from the user or their agents editing the file.
- The first time shipyard sees a project, it records its items as known **without** notifying (no flood on first launch or on adding a project). This is ghbar's "bootstrap" lesson.
- An item is notified at most once per event (ghbar's other lesson: "seen" and "notified" are separate sets).

### Error handling

| Situation | Behaviour |
|---|---|
| Configuration file is invalid TOML or fails validation | Keep the last valid configuration, show the error (file, line, message) at the top of the panel. Never blank the list. |
| No configuration file | Treat as defaults with no projects → project picker. |
| Token missing or rejected (401) | Go to the signed-out state → onboarding's connect step. |
| One repository not found or not accessible | That project shows an error row for it; other repositories and projects still show. |
| Network down / GitHub 5xx | Keep the last items, show "Last updated 4 min ago · can't reach GitHub" in the panel. Retry on the next trigger. |
| Rate limit exhausted: GraphQL answers **200** with a rate-limit error and `x-ratelimit-remaining: 0`; REST answers 403/429 | Keep the last items; banner "Rate limit reached · updates resume at 16:42"; the reset time comes from the response (`resetAt` / `x-ratelimit-reset`), not ghbar's one-hour guess. |
| Secondary rate limit (403/429 with `retry-after`) | Wait `retry-after` seconds, then resume; banner says so. |
| `npx` not found | Show the command with a Copy button instead of running it. |

### Out of scope

| Excluded | Why |
|---|---|
| Reviewing inside the app (diff, comments), merge/close actions | Agreed: click-through to GitHub for now. |
| A CLI or a settings window | ADR 0001: the file is the interface. The panel's menu only has "Open configuration file". |
| GitLab, GitHub Enterprise, several accounts | Nobody asked; the GraphQL host is one constant if GHE comes up. |
| Telling agent PRs from hand-written ones | Agreed: not reliable today (see Extensibility). |
| Mac App Store build | The sandbox forbids running `gh`/`npx` and reading `~/.config`. |
| Developer ID signing, notarization | Agreed: ad-hoc signed zips and the `xattr` line until 0.1.0 at the earliest. |
| Push updates (webhooks) | Needs a server; polling is enough at this scale. |

---

## 2. Entities and relationships

Nouns from the requirements, sorted:

| Noun | Entity or field? |
|---|---|
| Shipyard (the app) | **Entity**, orchestrator: lifecycle state, refresh. |
| Configuration | **Entity** (value) with rules: defaults, per-project overrides, validation. |
| Project | Field group inside Configuration (name, repositories, overrides). |
| Item (PR, issue, run) | **Entity** (value): kind, state, author, fingerprint. |
| Snapshot | **Entity** (value): all items of all projects from one refresh, plus per-repository errors and the rate limits seen. |
| Rate budget | **Entity**: owns the quota rule (share, back-off, pause). |
| Attention (seen records) | **Entity**: owns the "needs attention" rule and seen records. |
| Event | **Entity** (value), produced by diffing known → snapshot. |
| Notification rule | Field group inside Configuration; evaluated by `NotificationRules`. |
| App state | **Entity** (store): seen, known, notified, collapsed. |
| Account / token | **Entity**: `Auth` owns where the token comes from. |
| Menu model | **Entity** (value): what the panel draws. |
| Attention count, closed window, colour | Fields/derived values, not entities. |

Relationships:

```text
Shipyard -> ConfigStore            reads current Configuration, is told when it changes
Shipyard -> Auth                   asks for a token; drives device flow
Shipyard -> GitHubClient           fetch(projects) -> Snapshot (with rate limits)
Shipyard -> RateBudget             record(limits, cost); nextDelay(configured) -> Delay | pausedUntil
Shipyard -> AppStateStore          owns Attention + known items + notified + collapsed
Shipyard -> EventDetector          diff(known, snapshot) -> [Event]
Shipyard -> NotificationRules      should(event, project config) -> Bool
Shipyard -> Notifier               post(event)
Shipyard -> MenuModel              build(snapshot, config, appState) -> what Panel draws
Panel    -> Shipyard               click(item), collapse(project), markAllSeen(), refresh()
Onboarding -> ConfigStore          writes projects (the one writer)
Snapshot  has  [Project -> [Item]]
Configuration has [Project], Defaults, [NotificationRule]
```

Where each rule lives:

| Rule | Owner |
|---|---|
| Which state the app is in; whether a refresh may start now | `Shipyard` |
| How often refreshing is affordable; back-off; pause until reset | `RateBudget` |
| Effective settings of a project (defaults + overrides) | `Configuration` |
| Last-valid-config fallback | `ConfigStore` |
| Needs attention | `Attention` |
| First sight of a project is silent; one notification per event | `EventDetector` + `AppState.notified` |
| Which events notify | `NotificationRules` |
| What's in the closed window, what order, what colour | `MenuModel` |

---

## 3. Class design

### Shipyard (orchestrator) — `ShipyardCore/Shipyard.swift`

An `@MainActor @Observable` class; the panel observes it.

State:

```text
phase: signedOut | connecting(DeviceCode) | needsProjects | ready
config: Configuration              (from ConfigStore)
configError: ConfigError?
snapshot: Snapshot?                (last good)
fetchError: FetchError?            (last refresh's failure, if any)
gate: RefreshGate                  (one refresh at a time, queues one more)
```

The phase is a small state machine, declared in `Lifecycle.swift` as `Phase.after(LifecycleEvent)` so its transitions are tested on their own:

```text
          token found / device flow done
signedOut ─────────────────────────────▶ needsProjects ──(config has projects)──▶ ready
    ▲                                        ▲                                    │
    │ 401                                    └────────(projects emptied)──────────┤
    └─────────────────────────────────────────────────────────────────────────────┘
```

Operations:

| Operation | Does | Rejects / edge |
|---|---|---|
| `start()` | resolve token → phase; start scheduler; load config | — |
| `refresh()` | the refresh pipeline (§4) | no-op outside `ready`; queued if one is running |
| `open(item)` / `markSeen(item)` | opens URL (or not), `attention.markSeen` | — |
| `markAllSeen(project?)` | marks every open item seen | — |
| `toggleCollapsed(project)` | flips app state | — |
| `beginDeviceFlow()` / `cancelDeviceFlow()` | drives `Auth` | only in `signedOut` |
| `signOut()` | clears Keychain token → `signedOut` | if the token came from `gh`, says to run `gh auth logout` |

### Configuration — `ShipyardCore/Config/Configuration.swift`

A `Codable` value decoded with TOMLDecoder. Every key is optional; missing keys take defaults, so an empty file is valid. Defaults shown, as the file a user would write:

```toml
#:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json
version = 1

refresh-interval-seconds = 120   # min 30; a floor, stretched by the rate budget if needed
launch-at-login = true
hide-authors = []                # logins, e.g. "dependabot[bot]"

[menu-bar]
count = "total"                  # "total" | "per-kind" | "none"

[rate-limit]
show = "always"                  # "always" | "when-low" | "never"
max-share-percent = 10           # 1–50

[attention]
unseen = true
changed = true
review-requested = true
checks-failed = true

# What every project shows, unless the project overrides it.
[defaults.pull-requests]
show = true
closed-window-days = 7
drafts = true

[defaults.issues]
show = false
closed-window-days = 7

[defaults.workflow-runs]
show = false
finished-window-hours = 3
branches = "default-and-pull-requests"   # | "all"

[[defaults.notifications]]
event = "pr.opened"
authors = "any"

# One [[projects]] block per project, shown in this order.
[[projects]]
name = "e-commerce"
repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]
issues = { show = true }          # overrides merge key by key onto defaults
notifications = [                 # replaces the default list for this project
  { event = "pr.opened", authors = "others" },
  { event = "run.failed" },
]

[[projects]]
name = "job-search"
repositories = ["yahyabedirhan/job-search"]
```

Keys are kebab-case (TOML's usual style, as in Cargo and Starship). Per-project overrides are written as inline tables so each `[[projects]]` block stays self-contained and can be appended on its own.

Events: `pr.opened pr.merged pr.closed pr.reopened pr.review_requested pr.checks_failed pr.commented issue.opened issue.closed issue.commented run.failed run.succeeded`. Authors: `any | me | others | bots`.

Operations:

| Operation | Returns / rejects |
|---|---|
| `static decode(Data) throws -> Configuration` | rejects: invalid TOML (with line), unknown key type, unknown event, bad repo slug (`owner/name`), duplicate project names, negative windows, interval < 30 |
| `settings(for: Project) -> ProjectSettings` | defaults merged with the project's overrides (objects merge by field; `notifications` replaces) |
| `appendText(projects:) -> String` | the `[[projects]]` blocks the picker appends; the app never rewrites the file |

Unknown keys are ignored with a warning, so a newer file doesn't break an older app.

### ConfigStore — `ShipyardCore/Config/ConfigStore.swift`

State: `url`, `lastValid: Configuration`, `error: ConfigError?`, a file watcher.
Operations: `load()`, `onChange(handler)`, `append(projects:)` (appends `[[projects]]` blocks to the end, creating the file with a commented header when missing; never rewrites, so comments survive). The core has no file watcher; the app's `ConfigWatcher` calls `reload()`.
The app's `ConfigWatcher` watches the **directory**, not the file, and calls `reload()`: editors and agents write by replacing the file (rename), which kills a watch on the old file descriptor. Changes are debounced 200 ms.

### Auth — `ShipyardCore/GitHub/Auth/` (+ `Shipyard/Keychain.swift`)

Kept from ghbar almost as is, because it worked well:
- `TokenProvider.current()`: Keychain first (the user signed in explicitly), then `gh auth token` found at known paths (`/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, then `PATH`), since an `.app` starts with an almost empty `PATH`.
- `DeviceFlow`: request code → show code and open github.com/login/device → poll → store in Keychain. Needs a GitHub OAuth App client ID (scopes `repo`, `read:org`).
- `Keychain` (app target): the `TokenStore` port, get/set/delete one token. Tests use an in-memory store.

### GitHubClient — `ShipyardCore/GitHub/GitHubClient.swift`

State: token, `URLSession`. Operations:

| Operation | Returns / rejects |
|---|---|
| `viewer() -> Viewer` (login, id) | 401 → `.unauthorized` |
| `fetch(projects, settings) -> Snapshot` | one GraphQL call for PRs and issues (all repositories as aliases), plus one REST call per repository for runs when runs are on; partial errors land per repository in the snapshot. The GraphQL query also asks for `rateLimit { limit remaining resetAt cost }`; REST reads the `x-ratelimit-*` headers and sends `If-None-Match` so unchanged runs come back as 304, which GitHub doesn't count against the limit |
| rate-limit errors | `.rateLimited(api, resetAt)` from `x-ratelimit-reset`; `.secondaryLimit(retryAfter)` from `retry-after`, else wait 60 s. GraphQL's exhausted case is a 200 with an error, so the check reads headers, not only the status code. REST calls for runs go one after another, never in parallel (GitHub's guidance against secondary limits) |
| `recentRepositories() -> [RepoSummary]` | for the picker: the viewer's repositories by `pushedAt` plus those they contributed to recently |

The query text lives next to its parser in `GitHub/ProjectQuery.swift` (build + parse, one owner). Per repository alias it asks for: open PRs (first 50), PRs closed or merged ordered by `UPDATED_AT` (first 20, filtered by `closedAt` locally), the same for issues when shown, and per PR `isDraft`, `author { login, __typename }`, `updatedAt`, `closedAt`, `mergedAt`, comment + review counts, `reviewRequests` (to find the viewer), and the head commit's `statusCheckRollup.state`.
Runs come from REST (`GET /repos/{o}/{r}/actions/runs?created=>…`, plus `status=in_progress`), because GraphQL doesn't list workflow runs.

### Item and Snapshot — `ShipyardCore/Items/`

```text
Item
  id: String                  (URL; unique across PRs, issues, runs)
  kind: pullRequest | issue | workflowRun
  repository: String          ("owner/name")
  number/title/url/author/authorKind(me|other|bot)
  state: open | draft | merged | closed | running | succeeded | failed   (runs: queued counts as running)
  checks: none | pending | passed | failed      (PRs)
  reviewRequestedFromViewer: Bool
  updatedAt, closedAt?
  activity: Int               (comments + reviews)
  fingerprint: String          (state|updatedAt|checks|reviewRequested|activity) — any change = "changed"

Snapshot
  fetchedAt
  projects: [ProjectName: [Item]]
  errors: [Repository: FetchError]
  rateLimits: { graphql: RateLimit, rest: RateLimit? }   (limit, remaining, resetAt, cost of this refresh)
```

### Attention — `ShipyardCore/Items/Attention.swift`

Owns the rule, so the rule sits with the data it reads (seen records).
State: `seen: [ItemID: Fingerprint]`.

| Operation | Returns |
|---|---|
| `needsAttention(item, toggles) -> Bool` | false if closed; true if unseen, or `seen[id] != fingerprint`, or review requested, or checks failed, each gated by its toggle, and **all cleared by a click until the fingerprint changes** |
| `markSeen(item)` | stores the current fingerprint |
| `count(snapshot, toggles) -> Int` / `countByKind` | for the menu bar |
| `prune(snapshot)` | drops records for items gone for 30 days |

### EventDetector — `ShipyardCore/Items/EventDetector.swift`

Pure: `events(known: [ItemID: KnownItem], snapshot, newProjects: Set<ProjectName>) -> [Event]`.
`KnownItem` = the last seen state, checks and activity of each item. Items in a project seen for the first time produce no events. Transitions map to events: absent → open = `pr.opened`; open → merged = `pr.merged`; checks → failed = `pr.checks_failed`; activity went up = `pr.commented`; review requested newly true = `pr.review_requested`; run → failed/succeeded = `run.*`.

### NotificationRules — `ShipyardCore/Items/NotificationRules.swift`

Pure: `shouldNotify(event, settings: ProjectSettings) -> Bool` — the project's rule list contains the event, and the author filter matches (`me` = viewer, `bots` = `Bot` type or `[bot]` login, `others` = neither).

### AppStateStore — `ShipyardCore/State/AppStateStore.swift`

One JSON file (app-owned, never hand-edited, so Foundation's JSON is enough), versioned: `seen`, `known`, `knownProjects`, `notified: Set<EventID>`, `collapsed: Set<ProjectName>`. Loads at start, saves after a refresh and after clicks (debounced). A corrupt file is renamed aside and starts empty, with no notifications on the first refresh (bootstrap).

### Notifier — `Shipyard/Notifier.swift` (the `Notifying` port; tests use a recording one)

Wraps `UNUserNotificationCenter`: asks permission on the first notification (not at launch), posts "e-commerce · New PR #107 · Fix checkout totals". Clicking the notification opens the item and marks it seen.

### MenuModel — `ShipyardCore/Menu/MenuModel.swift`

Pure: `build(snapshot, config, appState, viewer) -> MenuModel`: sections per project in configuration order, items filtered (kind shown, closed window, `hide-authors`, drafts), sorted (open by `updatedAt` desc, then closed by `closedAt` desc), each row with colour, check dot, attention flag; plus the menu bar label (`total`, `per-kind`, `none`). All of R3–R6's display rules live here, where tests can reach them without SwiftUI.

### UI — `Shipyard/UI/`

SwiftUI `MenuBarExtra` in `.window` style (a panel, not an `NSMenu`):

```tsx
<ShipyardApp> (Shipyard/ShipyardApp.swift)
  <MenuBarExtra label={<MenuBarLabel count>}>
    <Panel>                                   switch shipyard.phase
      signedOut / connecting → <ConnectView>  (Onboarding/)
      needsProjects          → <ProjectPicker>(Onboarding/)
      ready →
        <StatusBanner>        config error · fetch error · rate limit paused/backed off · last updated
        <ProjectSection> ×N   collapsible header with attention count, "Mark all seen"
          <ItemRow> ×N        colour dot, #number, title, author, age, check dot
        <PanelFooter>         rate limit indicator · Refresh · Open configuration file · Install agent skill… · Quit
```

### RateBudget — `ShipyardCore/GitHub/RateBudget.swift`

Pure value, so the arithmetic is tested without a network. It's the answer to "can we afford the configured interval?".

State: last `RateLimit` per API, a moving average of what one refresh costs per API, `pausedUntil`.

| Operation | Returns |
|---|---|
| `record(snapshot.rateLimits)` / `record(error)` | updates quotas, cost average; a rate-limit error sets `pausedUntil` = reset time (or now + `retry-after`) |
| `nextDelay(configured, share) -> Delay` | `paused(until)` if paused or any API is at 0; `backedOff(600 s)` if any API is below 20%; else `max(configured, 3600 × cost ÷ (limit × share))` per API, reported as `stretched` when it beat `configured` |
| `canRefreshNow() -> Bool` | false only while paused (⌘R uses this) |
| `indicator(show) -> Indicator?` | what the footer draws: `GraphQL 4,850 / 5,000 · REST 4,960 / 5,000 · resets 16:42`, amber below 25% (ghbar's threshold), red at 0; `nil` for `never`, or for `when-low` above 25% |

`RefreshScheduler` asks `nextDelay` after every refresh and arms its timer with the answer, so a busy hour slows shipyard down on its own instead of running the limit dry.

### SkillInstaller — `ShipyardCore/Skill/SkillInstaller.swift`

Runs the user's login shell (`$SHELL -l -i -c 'npx -y skills add yahyabedirhan/shipyard -g -y'`) so nvm/asdf/Homebrew `PATH` setups are loaded; reports success, failure output, or "npx not found → copy this command".

### Folder tree

```text
shipyard/
├── Package.swift                     # SwiftPM: ShipyardCore (library) + Shipyard (macOS app, declared only on macOS) + tests; one dependency: TOMLDecoder
├── .github/workflows/ci.yml          # core build + tests on Ubuntu (Swift 6) for pushes and pull requests
├── Makefile                          # build, test, bundle .app, ad-hoc sign, zip, install
├── Packaging/Info.plist              # LSUIElement (no Dock icon), bundle id, version
├── schema/config.schema.json         # public contract for config.toml (ADR 0001); JSON Schema describes TOML too
├── skills/shipyard/SKILL.md          # teaches agents the config file; installed by `npx skills add`
├── Sources/ShipyardCore/             # Foundation only, so agents can build and test it on a Linux VPS
│   ├── Shipyard.swift                # orchestrator: phase, refresh pipeline, user actions (@Observable)
│   ├── Lifecycle.swift               # Phase (signedOut, connecting, needsProjects, ready) and its transitions
│   ├── Version.swift                 # ShipyardVersion.current: the one place the version is recorded
│   ├── RefreshScheduler.swift        # timer (armed from RateBudget.nextDelay), triggers + RefreshGate
│   ├── Ports.swift                   # what the app plugs in: Notifying, TokenStore, WallClock, URLOpening
│   ├── Config/
│   │   ├── Configuration.swift       # file model, defaults, validation, per-project merge
│   │   └── ConfigStore.swift         # path, load/reload, last-valid fallback, append projects
│   ├── GitHub/
│   │   ├── GitHubClient.swift        # transport (GraphQL + REST), errors, viewer, rate-limit headers, ETags
│   │   ├── RateBudget.swift          # quota per API, refresh cost, next allowed delay, indicator
│   │   ├── ProjectQuery.swift        # builds the GraphQL query and parses it into Items
│   │   ├── WorkflowRuns.swift        # REST runs request + parse + branch filter
│   │   └── Auth/
│   │       ├── TokenProvider.swift   # TokenStore → gh → none
│   │       └── DeviceFlow.swift      # OAuth device flow
│   ├── Items/
│   │   ├── Item.swift                # Item, Snapshot, fingerprint
│   │   ├── Attention.swift           # needs-attention rule, seen records, counts
│   │   ├── EventDetector.swift       # known + snapshot → events
│   │   └── NotificationRules.swift   # event + project settings → notify?
│   ├── State/
│   │   └── AppStateStore.swift       # state.json: seen, known, notified, collapsed
│   ├── Menu/
│   │   └── MenuModel.swift           # pure: sections, rows, semantic state colours, label
│   └── Skill/
│       └── SkillInstaller.swift      # runs npx skills add in the login shell
├── Sources/Shipyard/                 # macOS app: thin Apple-framework layer over ShipyardCore
│   ├── ShipyardApp.swift             # @main, MenuBarExtra wiring, builds the core with the adapters below
│   ├── ConfigWatcher.swift           # watches the config directory, calls ConfigStore.reload()
│   ├── Wake.swift                    # NSWorkspace wake → refresh trigger
│   ├── Keychain.swift                # TokenStore on the login keychain
│   ├── Notifier.swift                # Notifying on UNUserNotificationCenter
│   ├── LaunchAtLogin.swift           # SMAppService wrapper
│   └── UI/
│       ├── Panel.swift               # phase switch, banner, footer
│       ├── ProjectSection.swift
│       ├── ItemRow.swift
│       ├── Palette.swift             # semantic state colours → GitHub colours, light/dark
│       └── Onboarding/
│           ├── ConnectView.swift
│           └── ProjectPicker.swift
└── Tests/ShipyardCoreTests/          # end-to-end through Shipyard + focused tests per pure module; fixtures of GitHub responses
    └── Doubles/                      # in-memory ports: token store, recording notifier, manual clock, recording URL opener
```

Shipyard is a macOS app and only ships for macOS. The package has two targets so that the implementation agents, which run on a Linux VPS, can build and test everything holding a rule without a Mac; Linux is a development environment, not a platform shipyard supports. `ShipyardCore` imports only Foundation (plus FoundationNetworking on Linux) and TOMLDecoder; the rules live there: configuration, the GitHub client, attention, events, notification rules, the rate budget, the menu model, and the orchestrator itself. It reaches Apple-only services through a few small protocols in `Ports.swift`, and the `Shipyard` app target supplies them: the Keychain, notifications, file watching (`DispatchSource` file-system sources are Darwin-only), wake, login item, and the SwiftUI views. Tests target `ShipyardCore`, so they run on the VPS; the app target is built and checked on macOS.

---

## 4. Implementation

### Shipyard.refresh() — the pipeline

```text
refresh()
  guard phase == ready else return
  guard gate.begin() else return                      // queued; runs again after this one
  config = configStore.lastValid
  do
    snapshot = await github.fetch(config.projects, config.settings)
  catch unauthorized
    phase = signedOut; gate.finish(); return
  catch rateLimited(api, resetAt) / secondaryLimit(retryAfter)
    budget.record(error); fetchError = error; gate.finish(); scheduler.arm(budget.nextDelay(…)); return
  catch other
    fetchError = other; gate.finish(); return         // keep old snapshot
  newProjects = config.projectNames - appState.knownProjects
  events = EventDetector.events(appState.known, snapshot, newProjects)
  for e in events where e.id ∉ appState.notified
    if NotificationRules.shouldNotify(e, config.settings(for: e.project))
      notifier.post(e)
    appState.notified.insert(e.id)
  appState.known = snapshot.knownItems; appState.knownProjects ∪= newProjects
  appState.attention.prune(snapshot); appStateStore.save()
  self.snapshot = snapshot; fetchError = nil          // Panel re-renders from MenuModel
  budget.record(snapshot.rateLimits)
  scheduler.arm(budget.nextDelay(config.refreshIntervalSeconds, config.rateLimit.maxSharePercent))
  if gate.finish() then refresh()                     // a queued trigger arrived meanwhile
```

### Attention.needsAttention(item)

```text
needsAttention(item, t)
  if item.state in {merged, closed, succeeded} return false   // runs: failed runs are "open"-like until seen
  seenPrint = seen[item.id]
  if seenPrint == item.fingerprint return false        // clicked since last change → cleared
  if seenPrint == nil      return t.unseen  or (t.reviewRequested and item.reviewRequestedFromViewer) or (t.checksFailed and item.checks == failed)
  /* seen, then changed */ return t.changed or (t.reviewRequested and …) or (t.checksFailed and …)
```

### ConfigStore on change

```text
onDirectoryEvent (debounced)
  data = read(url)                    // missing file → Configuration() with no projects
  try config = Configuration.decode(data)
    lastValid = config; error = nil
    shipyard.configChanged(config)     // phase may move to/from needsProjects; triggers refresh
  catch e
    error = ConfigError(e, line)       // lastValid untouched
```

### Rate limit arithmetic: does 2 minutes fit?

Two separate hourly limits, both 5,000 for a signed-in user, and **both shared with every other tool using your GitHub account**, including your agents' `gh` calls. Shipyard's budget at 10% is 500 of each per hour. A 120 s interval is 30 refreshes an hour.

| Budget line | Per refresh | Per hour at 120 s | Share of 5,000 |
|---|---|---|---|
| GraphQL, 5 repositories, PRs + issues (**measured**: dry run on job-search, e-commerce-×2, blog-×2) | 7 points | 210 | 4.2% |
| GraphQL, 10 repositories, PRs + issues | ~14 points | ~420 | 8.4% |
| GraphQL, 20 repositories, PRs + issues | ~28 points | → stretched to ~200 s | 10% |
| REST runs, 10 repositories, nothing changed (304) | 10 requests, 0 counted | 0 | 0% |
| REST runs, 10 repositories, all changed | 10 requests | 300 | 6% |

GraphQL points are GitHub's estimate: roughly the total nodes the query could return ÷ 100, and the nested per-PR lists (`reviewRequests`, last commit's checks) dominate it. To keep it low, `reviewRequests` asks for `first: 10` and the head commit for `last: 1`, and closed items for `first: 20`. The 5-repository row is measured with `rateLimit(dryRun: true)` against the query shape above; the others scale it. The real cost comes back in `rateLimit.cost` on every response, and `RateBudget` uses the measured figure, not this table. So a user with 10 repositories gets their 2 minutes; a user with 40 gets about 7 minutes and a panel line "Refreshing every 7 min to stay within 10% of your rate limit".

### Trace 1: an agent opens a PR (happy path)

Setup: phase `ready`, project `e-commerce` known, `known` holds e-commerce-backend's 3 open PRs, attention count 0. An agent opens e-commerce-backend#57.

| Step | Call (owner) | State after |
|---|---|---|
| 1 | timer fires → `RefreshScheduler` → `Shipyard.refresh()` | gate running |
| 2 | `GitHubClient.fetch` (GitHub/) | snapshot has 4 open PRs, #57 `checks: pending`, `author: me` |
| 3 | `EventDetector.events` (Items/) | `[pr.opened #57 author=me]` |
| 4 | `NotificationRules.shouldNotify` (Items/) | default rule `pr.opened any` → true |
| 5 | `Notifier.post` | macOS notification "e-commerce · New PR #57 · …"; `notified += pr.opened#57` |
| 6 | `AppStateStore.save` | `known` has #57 (checks pending) |
| 7 | `MenuModel.build` → `MenuBarLabel` | #57 unseen → count **1**, green row, gray check dot |
| 8 | 2 min later CI fails; refresh | fingerprint changed; event `pr.checks_failed` (no rule → silent); still unseen → count 1, red check dot |
| 9 | user clicks #57 → `Shipyard.open` → `Attention.markSeen` | `seen[#57] = fingerprint`; count **0**; browser opens |
| 10 | agent pushes a fix; refresh | `updatedAt` changed → fingerprint changed → count **1** again |

### Trace 2: a broken edit (rejection)

| Step | Call | State after |
|---|---|---|
| 1 | agent writes `config.toml` with `event = "pr.openned"` | — |
| 2 | directory watch → `ConfigStore` → `Configuration.decode` throws `unknownEvent("pr.openned", line 14)` | `lastValid` unchanged, `error` set |
| 3 | `Panel` | banner: "config.toml line 14: unknown event `pr.openned` (did you mean `pr.opened`?). Using the last valid configuration." |
| 4 | refreshes keep running with `lastValid` | list unchanged |
| 5 | agent fixes the file | `error = nil`, banner gone, refresh triggered |

### Trace 3: agents drain the limit (rejection by budget)

Setup: 10 repositories, one refresh measured at 14 GraphQL points. Several agents are running `gh` heavily.

| Step | Call (owner) | State after |
|---|---|---|
| 1 | refresh → `fetch` returns `graphql.remaining = 900 / 5,000` (18%) | snapshot fine |
| 2 | `RateBudget.nextDelay(120, 10%)` | below 20% → `backedOff(600 s)` |
| 3 | `Panel` | amber footer `GraphQL 900 / 5,000 · resets 16:42`, banner "Your rate limit is low (other tools are using it). Refreshing every 10 min." |
| 4 | agents keep going; next refresh gets 403, `x-ratelimit-remaining: 0`, `x-ratelimit-reset` = 16:42 | `pausedUntil = 16:42`, `fetchError = rateLimited` |
| 5 | menu bar icon shows the paused glyph; ⌘R does nothing and says why | last snapshot still listed, "Last updated 14 min ago" |
| 6 | 16:42: timer armed for `pausedUntil` fires | quota back to 5,000; next delay 120 s; banner gone |

What the traces turned up and the design now handles: the first refresh after adding a project must not notify for every existing PR (the `newProjects` guard in step 3), and `pr.checks_failed` has to be an event whether or not a rule is enabled, so a rule added later behaves the same.

---

## 5. Extensibility

| Change | What you touch |
|---|---|
| New event (e.g. `pr.review_submitted`) | `EventDetector` (one transition), the event enum in `Configuration`, `schema/`, `SKILL.md` |
| Split count by kind in the menu bar | nothing: `[menu-bar] count = "per-kind"` already exists |
| Quick actions (merge, close) | `GitHubClient` (one mutation), `ItemRow` context menu |
| Mark agent PRs (body marker / co-author trailer) | `ProjectQuery` fetches `body` tail, `Item.isAgent`, author filter gains `agents` |
| New item kind (discussions, releases) | `Item.kind`, a query fragment, `MenuModel`, config section, schema. Five files, accepted: it's rare |
| Quiet hours / Do-Not-Disturb rules | `NotificationRules` + a config field |
| GitHub Enterprise | a `host` config field read by `GitHubClient` and `DeviceFlow` |
| Notarized releases | `Makefile` only |
| Fetch less when nothing moved (e.g. only query repositories whose `pushedAt` changed) | `ProjectQuery` + `GitHubClient`; `RateBudget` needs nothing, it measures the cost |
| Breaking config change | `version` field + a migration in `Configuration.decode` |

Refused for now: a plugin system for item kinds (one registration seam for a change that happens rarely), a protocol over `GitHubClient` for other forges (one implementation), a CLI (ADR 0001), multi-account support.

---

## Decisions taken in review

- **Panel technology: SwiftUI `MenuBarExtra` in `.window` style**, not AppKit `NSMenu`. The panel stays open while sections collapse and ⌥-clicks happen, colours and rows are fully controlled, and onboarding lives in the same panel. Cost accepted: it doesn't behave exactly like a native menu (no type-to-select).
- **A click clears everything about an item until it changes again**, including a review request or failed checks. The attention count means "things to look at", not "work outstanding".
- **Workflow runs come from REST, one conditional request per repository per refresh**, sent one after another, and only when runs are shown. GraphQL can't list runs.
- **Decided without asking, for review when building:** macOS 14 minimum (the only platform shipped; `ShipyardCore` builds on Linux for development only); one dependency (dduan/TOMLDecoder, MIT, decode-only); 120 s default refresh (min 30), stretched by a 10% rate budget, backing off below 20% remaining; rate-limit indicator shown `always`; open PRs capped at 50 and closed at 20 per repository per refresh; launch at login on by default; the device flow needs an OAuth App registered under the maintainer's account (one-time, free); versions start at 0.0.1 and stay below 0.1.0 until the public launch.

---

## References (GitHub documentation)

The facts are written up in `docs/references/` (committed with the repo). Read the one for an area before implementing it; checked 2026-09-25.

| Topic | Page | What the design takes from it |
|---|---|---|
| GraphQL rate limit | [Rate limits and query limits for the GraphQL API](https://docs.github.com/en/graphql/overview/rate-limits-and-query-limits-for-the-graphql-api) | 5,000 points/hour per user, **including OAuth apps acting for the user**; cost = connection requests ÷ 100, rounded, min 1; exhausted → status 200 with an error and `x-ratelimit-remaining: 0`; secondary: 2,000 points/min, 100 concurrent; prefer headers to querying `rateLimit` |
| REST rate limit | [Rate limits for the REST API](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api) | 5,000 requests/hour **shared by every token and app for one user**; `x-ratelimit-limit/remaining/used/reset/resource` headers; 403/429 when exceeded; obey `retry-after`, else wait until `x-ratelimit-reset` or 60 s |
| Polling and conditional requests | [Best practices for using the REST API](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api) | a `304 Not Modified` from `If-None-Match` doesn't count against the limit; requests serially, not concurrently; respect `x-poll-interval` when present |
| Workflow runs | [REST: workflow runs](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-repository) | the `created`, `status`, `branch` filters for `WorkflowRuns` |
| `rateLimit` object | [GraphQL reference: RateLimit](https://docs.github.com/en/graphql/reference/objects#ratelimit) | `cost`, `limit`, `remaining`, `resetAt`, `used`; `dryRun` for measuring a query |
| Device flow | [Authorizing OAuth apps: device flow](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow) | `DeviceFlow`: request code, poll interval, `slow_down`, expiry |
