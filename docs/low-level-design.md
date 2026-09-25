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
| R10 | Refresh on an interval (default 120 s), when the Mac wakes, when the configuration changes, and on ⌘R. Opening the panel doesn't refresh: it shows the last fetched data and spends no GitHub request. |
| R11 | Read everything the user controls from `~/.config/shipyard/config.toml` (honouring `$XDG_CONFIG_HOME`), apply edits live, and publish a JSON Schema for it (referenced by `#:schema`, checked with `taplo check`). |
| R12 | Keep app state (seen, known items, collapsed sections, notified) in `~/Library/Application Support/Shipyard/state.json`, never in the configuration. |
| R13 | Onboarding: connect GitHub by reusing `gh`'s token silently; in 0.0.x `gh` is the only way in, and without a usable `gh` token the panel shows a connect screen explaining `gh auth login` (sign-in without `gh`, the device flow with the token in the Keychain, is deferred to #22); then, whenever there are no projects, show the project picker, which writes projects to the configuration. |
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
| Token missing or rejected (401) | Go to the signed-out state → onboarding's connect step, which says why (no `gh` token, or GitHub rejected it) and to run `gh auth login`. |
| One repository not found or not accessible | That project shows an error row for it; other repositories and projects still show. |
| Network down / GitHub 5xx | Keep the last items, show "Last updated 4 min ago · can't reach GitHub" in the panel. Retry on the next trigger. |
| Rate limit exhausted: GraphQL answers **200** with a rate-limit error and `x-ratelimit-remaining: 0`; REST answers 403/429 | Keep the last items; banner "GraphQL rate limit reached · updates resume at 16:42" (`PanelText.refreshDelay`); the reset time comes from the response (`resetAt` / `x-ratelimit-reset`), not ghbar's one-hour guess. |
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
| Snapshot | **Entity** (value): all items of all projects from one refresh, plus per-source errors (a repository and a kind) and the rate limits seen. |
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
Shipyard -> RateBudget             record(limits) / record(error); nextDelay(configured, share) -> RefreshDelay
Shipyard -> AppStateStore          owns Attention + known items + notified + collapsed
Shipyard -> EventDetector          events(known, snapshot, projects) -> [Event]
Shipyard -> NotificationRules      shouldNotify(event, project settings, hidden authors) -> Bool
Shipyard -> Notifier               post(notification)
Notifier -> Shipyard               openNotification(itemURL) on a click
Shipyard -> MenuModel              build(snapshot, config, appState) -> what Panel draws
Panel    -> Shipyard               click(item), collapse(project), markAllSeen(), refresh()
Onboarding -> Shipyard            suggestedRepositories(), checkRepository(text), addProjects(projects)
Shipyard -> ConfigStore            append(projects:) (the one writer), then follows the reload
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
signedOutReason: noToken | rejected(TokenSource) | signedOut(SignOutResult) | nil
                                   (why signedOut, for the connect screen; nil while signed in and while start() looks for a token)
config: Configuration              (from ConfigStore)
configError: ConfigError?
snapshot: Snapshot?                (last good)
fetchError: GitHubError?           (last refresh's failure, if any)
menu: MenuModel                    (what the panel draws; a failed refresh keeps its rows and sets fetchError; before any succeeded, it lists every project not loaded yet)
budget: RateBudget                 (limits, recent costs, pause; reset on sign-out)
appStateStore: AppStateStore       (seen, collapsed; loaded at start, kept on sign-out)
gate: RefreshGate                  (one refresh at a time, queues one more)
timer: RefreshTimer                (port; armed with the budget's delay after every refresh, disarmed outside ready)
loginItem: LoginItem               (port; told launch-at-login at start and on every valid configuration change)
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
| `start()` | load config; `loginItem.setEnabled(launch-at-login)`; resolve token → phase; in `ready`, the first refresh. The connect screen's Try again calls it too | no token → `signedOut` with `noToken`; a file broken at launch leaves the login item alone (the defaults would re-register one the user turned off) |
| `refresh()` | the refresh pipeline (§4); the timer, ⌘R, wake and a configuration change call it (opening the panel doesn't); arms the timer after with the budget's delay | no-op outside `ready`; while one runs, returns at once and the running one goes again after (several calls make one more run); while the budget pauses, sends nothing and re-arms the timer for the pause's end |
| `canRefreshNow` | false only while the budget pauses (⌘R and the Refresh button read it; `menu.canRefreshNow` says the same) | — |
| `reloadConfiguration()` | `configStore.reload()`; on a change, `loginItem.setEnabled(launch-at-login)` (so the switch applies live), phase follows `hasProjects`, the menu is rebuilt at once from the last snapshot (or none) under the new configuration, keeping `fetchError`, `refreshDelay` and `rateIndicator` (so an edit shows even while refreshing is paused or failing: a project added since shows "Not loaded yet", a removed one disappears), and it refreshes (or disarms the timer) | a rejected edit changes nothing but `configError`, which the panel's banner shows (set at `start()`, every reload and `addProjects`) |
| `open(row)` / `markSeen(row)` | opens the URL through the `URLOpening` port (or not, for ⌥-click), `attention.markSeen` with the row's item; saves app state and re-applies attention to the menu model | — |
| `openNotification(itemURL)` | a notification was clicked: opens the URL and marks the item seen, the version in the last snapshot, else the one in `known` (a click that launched the app before its first refresh) | an item neither lists is only opened |
| `markAllSeen(project?)` | marks every open row of that project (or of all projects) seen | rows hidden by the configuration are left alone |
| `toggleCollapsed(project)` | flips app state; the section keeps its rows and its count | — |
| `beginDeviceFlow()` / `cancelDeviceFlow()` | drives `Auth`; the code shows as `connecting(code)`; the token is saved to the token store. Built and tested in the core, but 0.0.x's app never calls it (#22) | only in `signedOut`; expiry, denial or failure → `signedOut` with `signInError`, and it can begin again |
| `suggestedRepositories()` | the picker's list: `GitHubClient.recentRepositories` through `request` | throws `GitHubError`; a 401 signs out; a spent limit is recorded in the budget (the same limit refreshes use) |
| `checkRepository(text) -> RepositoryCheck` | a typed `owner/name` (trimmed; a `github.com/owner/name` link, `.git` and a trailing slash are taken apart too) is looked up with `GitHubClient.repository`; `accepted(RepoSummary)` carries GitHub's spelling, which is what the picker writes | `rejected` with a reason and its `message`: `notASlug` (no request sent), `notFound` (404: missing, or the token can't see it), `forbidden` (403, e.g. SSO), `couldNotCheck` (network, rate limit, 401, which also signs out) |
| `addProjects([NewProject])` | `configStore.append(projects:)` then follows the reload like `reloadConfiguration()`: with projects, `needsProjects → ready` and the first refresh, no restart | throws `ConfigError` (empty or used name, no repositories, bad slug) before writing anything |
| `signOut()` | clears the token store → `signedOut` with `signedOut(result)`; app state (seen, collapsed) is kept. The header's gear menu has Sign out | if the token came from `gh` (always, in 0.0.x), `ghStillSignedIn`: the connect screen says to run `gh auth logout`, since Try again or the next launch picks `gh`'s token up again |
| `request(body)` (internal) | every GitHub API call runs through it | a 401 → `signedOut` with `rejected(source)`, dropping the stored token when it came from the token store |

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

[menu]
layout = "list"                  # "list" | "tabs"

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
| `static decode(Data) throws(ConfigError) -> Decoded` | the configuration plus warnings; rejects, each with a line and a message (every problem is listed, not only the first): invalid TOML, a value of the wrong type, an unknown choice (event, author filter, count style…) with the nearest valid one suggested, bad repo slug (`owner/name`), a project without a name or repositories, a repository listed twice in one project (ignoring case), duplicate project names, negative windows, interval < 30, share outside 1–50, a `version` other than 1 |
| `settings(for: Project) -> ProjectSettings` | defaults merged with the project's overrides (objects merge by field; `notifications` replaces) |
| `appendText(projects:) -> String` | the `[[projects]]` blocks the picker appends; the app never rewrites the file |

Unknown keys are ignored with a warning, so a newer file doesn't break an older app. TOMLDecoder parses the file but doesn't say where a value came from, so `ConfigurationReader` walks the parsed `TOMLTable` key by key and `TOMLSourceMap` (a light second pass over the text) finds the line of each key path for the messages. The published schema is `schema/config.schema.json`; tests check the example above and a file setting every key against it.

### ConfigStore — `ShipyardCore/Config/ConfigStore.swift`

State: `url` (`$XDG_CONFIG_HOME/shipyard/config.toml`, else `~/.config/shipyard/config.toml`), `lastValid: Configuration`, `error: ConfigError?`, `warnings: [ConfigIssue]`.
Operations: `reload() -> changed(Configuration) | unchanged | invalid(ConfigError)`, `createIfMissing()` (the gear menu's "Open configuration file": writes the commented header alone when there's no file; never touches one that exists), `append(projects:)` (appends `[[projects]]` blocks to the end, creating the file with a commented header and the `#:schema` line when missing; never rewrites, so comments survive; rejects bad slugs, a repository listed twice in one project and names already used before writing). The core has no file watcher; the app's `ConfigWatcher` calls `Shipyard.reloadConfiguration()`, which reloads the store and follows the result.
The app's `ConfigWatcher` watches the **directory**, not just the file: editors and agents write by replacing the file (rename), which kills a watch on the old file descriptor. An in-place write (`>>`) doesn't touch the directory, so the file is watched too, and both watches are reopened after every change. A missing directory is watched through its nearest existing ancestor, so creating it is noticed. Changes are debounced 200 ms.

### Auth — `ShipyardCore/GitHub/Auth/` (+ `ShipyardApp/Keychain.swift`, #22)

**0.0.x connects through `gh` only.** The app reads `gh auth token` silently and never starts the device flow; without a usable `gh` token the panel's connect screen says to install `gh` and run `gh auth login`. The device flow and the Keychain below stay in the core, tested, and come to the app with sign-in without `gh` (#22); until then the app's token store is `SessionTokenStore` (`Placeholders.swift`), which nothing writes to.

Kept from ghbar almost as is, because it worked well:
- `TokenProvider.current()`: Keychain first (the user signed in explicitly), then `gh auth token` found at known paths (`/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, then `PATH`), since an `.app` starts with an almost empty `PATH`. Spawning `gh` sits behind the `GhTokenLookup` protocol (`GhCLI` runs it with `Process`), so tests use a fake lookup.
- `DeviceFlow`: request code → show code and open github.com/login/device → poll every `interval` s (+5 s per `slow_down`) → store in Keychain. Stops with `.expired` after the code's 15 minutes. Needs a GitHub OAuth App client ID (scopes `repo`, `read:org`): the one build-time constant `OAuthApp.clientID`, a placeholder until the maintainer registers the app (the flow refuses to start while it's the placeholder). Waiting and the clock are injected, so tests poll without real time passing.
- `Keychain` (app target): the `TokenStore` port, get/set/delete one token. Tests use an in-memory store.

### GitHubClient — `ShipyardCore/GitHub/GitHubClient.swift`

State: token, `HTTPTransport` (`URLSessionTransport` in the app; tests stub responses at this layer). Operations:

| Operation | Returns / rejects |
|---|---|
| `viewer() -> Viewer` (login, id) | 401 → `.unauthorized` |
| `fetch(projects: [ProjectSettings], at:) -> Snapshot` | one GraphQL call for PRs and issues (all repositories as aliases), plus one REST call per repository for runs when runs are on; partial errors land per source (repository + kind) in the snapshot: a repository GraphQL can't resolve fails every kind each project shows from it. The GraphQL query also asks for `rateLimit { limit remaining resetAt cost }`; REST reads the `x-ratelimit-*` headers and sends `If-None-Match` so unchanged runs come back as 304, which GitHub doesn't count against the limit. The snapshot's `rateLimits.rest` is the last runs response's headers with the counted (non-304) requests as `cost`. A runs request that fails with another HTTP status (or an unreadable body) becomes an error for that repository's runs source only (an error row in the projects that show runs) while its pull requests and issues still list; a spent limit, a 401 or a network failure fails the whole fetch, as for GraphQL |
| rate-limit errors | `.rateLimited(resetAt, api)` from `x-ratelimit-reset` (403/429 with `x-ratelimit-remaining: 0`, or GraphQL's 200 with a `RATE_LIMITED` error or with `x-ratelimit-remaining: 0` and an error); `api` comes from `x-ratelimit-resource` (`graphql`, else REST), or the URL without it. `.secondaryLimit(retryAfter)` from `retry-after` (it wins over the reset time), else 60 s for a bare 429 or a 403 whose message says "secondary rate limit"; any other 403 is `.http(403)`. Every response's `x-ratelimit-*` headers are read into a `RateLimit`; the snapshot carries GraphQL's (headers first, `cost` from the body). GraphQL's exhausted case is a 200 with an error, so the check reads headers, not only the status code. REST calls for runs go one after another, never in parallel (GitHub's guidance against secondary limits) |
| `recentRepositories(at:) -> [RepoSummary]` | for the picker, one GraphQL request (`GitHub/Repositories.swift`): `viewer.repositories` (owner and collaborator, `isArchived: false`) and `viewer.repositoriesContributedTo`, each `first: 25` ordered by `PUSHED_AT`; merged, each repository once (case-insensitive), archived ones dropped (the contributed list has no `isArchived` argument), newest push first, never-pushed last. Rate-limit errors as for `fetch` |
| `repository(slug) -> RepoSummary` | REST `GET /repos/{owner}/{repo}`, for the picker's check of a typed name; `full_name` is GitHub's spelling; 404 → `.http(404)` |

The query text lives next to its parser in `GitHub/ProjectQuery.swift` (build + parse, one owner). Each repository is asked for once (aliases `repo0`, `repo1`… with `$owner<i>`/`$name<i>` variables), even when several projects list it, and the query also asks for `viewer { login }` (to tell `me` and the viewer's review requests apart) and `rateLimit`. An alias that comes back `null` with a `NOT_FOUND` (missing, or no access) or `FORBIDDEN` error becomes that repository's error in the snapshot; the others still parse. Per repository alias it asks for: open PRs (first 50), PRs closed or merged ordered by `UPDATED_AT` (first 20, filtered by `closedAt` locally), and per PR `isDraft`, `author { login, __typename }`, `updatedAt`, `closedAt`, `mergedAt`, comment + review counts, `reviewRequests` (to find the viewer), and the head commit's `statusCheckRollup.state`. Issues are asked for the same way (`openIssues`: open, first 50; `closedIssues`: closed, first 20, both by `UPDATED_AT`; per issue `state`, `author { login, __typename }`, `createdAt`, `updatedAt`, `closedAt` and the comment count, with no nested lists), and only in the aliases of repositories that some project's effective settings show issues for, so turning issues off keeps them out of the query's cost; the `IssueFields` fragment is sent only when one does. A repository shared by two projects is asked for once with the union of what they show, and each project keeps only the kinds it shows.
Runs come from REST, because GraphQL doesn't list workflow runs (`GitHub/WorkflowRuns.swift` builds the request, parses it and holds the branch filter). Each repository that some project shows runs for (and that GraphQL didn't report missing) gets one `GET /repos/{o}/{r}/actions/runs?created=>=<since>&exclude_pull_requests=true&per_page=100` per refresh, one after another. `since` is an hour before the widest `finished-window-hours` of those projects, rounded down to the hour, so the URL stays the same for an hour (and its `ETag` can match) and a run of up to an hour that finished inside the window is still in the answer; a run that started earlier than that isn't listed, even while it runs. The client keeps each repository's last URL, `ETag` and parsed runs in memory (`WorkflowRunCache`, for as long as the `GitHubClient` of one sign-in lives; a relaunch asks afresh once): the next request to the same URL sends `If-None-Match`, and a `304` reuses those runs. A run's state: anything not `completed` (and `action_required`) is `running`; `success` and `neutral` are `succeeded`; `failure`, `timed_out` and `startup_failure` are `failed`; `cancelled`, `skipped` and `stale` runs aren't listed. The runs are parsed once per repository and filtered per project: `branches = "all"` keeps them all; `"default-and-pull-requests"` keeps those whose `head_branch` is the repository's default branch or an open pull request's head. The GraphQL query supplies both for those repositories (`defaultBranchRef { name }`, `headRefName` in `PullRequestFields`, and, where no project shows the repository's pull requests, `openPullRequestHeads: pullRequests(states: OPEN, first: 50) { nodes { headRefName } }`), so no extra REST calls. The window itself is the menu model's.

### Item and Snapshot — `ShipyardCore/Items/`

```text
Item
  id: String                  (URL; unique across PRs, issues, runs)
  kind: pullRequest | issue | workflowRun
  repository: String          ("owner/name")
  number/title/url/author/authorKind(me|other|bot)   (a Bot's login keeps GitHub's `[bot]` suffix; a deleted account is `ghost`; a run: its run number, the workflow's name, the actor)
  state: open | draft | merged | closed | running | succeeded | failed   (issues: open | closed; runs: queued counts as running)
  checks: none | pending | passed | failed      (PRs; a run's own result: running pending, succeeded passed, failed failed)
  branch: String?             (runs: the head branch)
  reviewRequestedFromViewer: Bool
  createdAt, updatedAt, closedAt?   (runs: started, last updated, finished)
  activity: Int               (comments + reviews; an issue's comments)
  fingerprint: String          (state|updatedAt|checks|reviewRequested|activity) — any change = "changed"

Snapshot
  fetchedAt
  items: [ProjectName: [Item]]
  errors: [ItemSource: RepositoryError]      (per repository + kind; notFound | forbidden | other, GitHub's message)
  rateLimits: { graphql: RateLimit?, rest: RateLimit? }   (limit, remaining, used, resetAt, cost of this refresh: GraphQL's `rateLimit.cost`; REST's counted (non-304) requests)
  viewerLogin
```

### Attention — `ShipyardCore/Items/Attention.swift`

Owns the rule, so the rule sits with the data it reads (seen records). It's keyed on the generic `Item`, so issues and runs reuse it.
State: `seen: [ItemID: SeenRecord]`, where `SeenRecord` = the fingerprint seen and `present`, the last time a refresh still listed the item (bumped at most once a day, so the file isn't rewritten every refresh).

| Operation | Returns |
|---|---|
| `needsAttention(item, toggles) -> Bool` | false if closed, merged, running or succeeded (a failed run can, its `checks` failed so `checks-failed` covers it); true if unseen, or `seen[id] != fingerprint`, or review requested, or checks failed, each gated by its toggle, and **all cleared by a click until the fingerprint changes** |
| `markSeen(item, at:)` | stores the current fingerprint |
| `counts(items, toggles) -> AttentionCounts` | per kind (`pullRequests`, `issues`, `workflowRuns`) and `total`; an item listed in two projects counts once |
| `prune(present: items, at:) -> Bool` | bumps `present` for listed items, drops records for items gone for 30 days; says whether to save |

### EventDetector — `ShipyardCore/Items/EventDetector.swift`

Pure: `events(known: KnownItems, snapshot, projects: [ProjectSettings]) -> [Event]`, per project in configuration order.
`KnownItems` = `items: [ItemID: KnownItem]` (the last state, checks, review request, activity, repository and fingerprint of each item, and `present`: when a refresh last listed it, bumped at most once a day) and `sources: [ProjectName: Set<ItemSource>]`, where an `ItemSource` is one repository and one item kind. Items from a source the project hasn't been fetched from before produce no events: the first refresh ever, a project or repository just added, a kind just shown. `known.updated(with: snapshot, projects:)` is what the next refresh compares with: the snapshot's items and fetched sources; a source that failed keeps its known-ness (so its return isn't a burst), and only that source: a runs 403 doesn't hold back the repository's pull requests; an item missing from the snapshot (out of the most recent 50, or its repository failed) is kept for 30 days after it was last listed, and while its repository fails, so when it comes back it's compared with its last version (no `opened`; `merged` if it merged meanwhile) rather than announced as new; a project, repository or kind no longer fetched is forgotten (adding it back is a first sight again).
The detector finds generic `ItemChange`s and `EventKind.of(change, for: item.kind)` names them, so issues and runs only add names (and runs their own changes): absent → open (drafts too) = opened (absent → closed is nothing: it may be an old item coming back into the closed list); open → merged = merged; open → closed = closed; closed → open = reopened; review requested newly true (open) = review_requested; checks newly failed (open) = checks_failed; activity went up = commented. For issues only opened, closed and commented have names (`issue.*`); an issue reopened is no event, and its next close is a new occurrence of `issue.closed`. Runs have their own changes: failed (found failed, unknown or not failed before) = `run.failed`, succeeded likewise = `run.succeeded`; a run found already finished counts, since only recent runs are asked for, so it finished between two refreshes. Both recur (a re-run that fails again is a new occurrence). Runs of one repository are a source of their own, so turning runs on is a silent first sight. Pull requests and issues of one repository are separate sources, so showing issues in a project that already has its pull requests known is a silent first sight. An `Event` has the kind, project, item and an occurrence: empty for events that happen once in an item's life (opened, merged), the item's fingerprint for ones that recur; `id` = kind + item URL (+ occurrence), the same in every project.

### NotificationRules — `ShipyardCore/Items/NotificationRules.swift`

Pure: `shouldNotify(event, settings: ProjectSettings, hiddenAuthors) -> Bool` — the project's rule list contains the event, and the author filter matches the item's author (`me` = viewer, `bots` = `Bot` type or `[bot]` login, `others` = neither). Authors in `hide-authors`, and drafts in a project whose `pull-requests.drafts` is false, are never notified, as they're never listed. `notification(for: event)` makes the `PostedNotification`: event id, project, title text ("New PR #57", "Run #41 failed"), the item's title (for a run, "CI · main": workflow and branch) and URL.
`NotifiedEvents` (app state, apart from the seen records) holds every event handled, notified or passed over, per item: `contains(event)`, `insert(event, at:)`, and `prune(present:at:)`, which keeps an item's record while it's known and 30 days after, so an item that leaves the list and comes back isn't announced again.

### AppStateStore — `ShipyardCore/State/AppStateStore.swift`

One JSON file, `state.json`, in a directory the app provides (`~/Library/Application Support/Shipyard/`; tests pass a temporary one). App-owned, never hand-edited, so Foundation's JSON is enough. `AppState` holds `attention` (seen records), `collapsed: Set<ProjectName>`, `known: KnownItems` (written as `known` and `knownProjects`) and `notified: NotifiedEvents`.

```json
{
  "version": 1,
  "seen": { "https://github.com/o/r/pull/57": { "fingerprint": "open|…", "present": "2026-09-25T12:00:00Z" } },
  "collapsed": ["job-search"],
  "known": { "https://github.com/o/r/pull/57": { "repository": "o/r", "state": "open", "checks": "pending", "reviewRequested": false, "activity": 0, "fingerprint": "open|…", "present": "2026-09-25T12:00:00Z" } },
  "knownProjects": { "e-commerce": [{ "repository": "o/r", "kind": "pullRequest" }] },
  "notified": { "https://github.com/o/r/pull/57": { "events": ["pr.opened"], "present": "2026-09-25T12:00:00Z" } }
}
```

Every field is optional when read and unknown fields are ignored, so adding a field doesn't bump `version`: an older file loads with the new field empty (a file without `knownProjects` makes the first refresh after the upgrade silent), and a file a newer build wrote at the same `version` still loads in an older build. `known`, `knownProjects` and `notified` that can't be read are dropped rather than failing the file (the next refresh is then silent, the safe way to fail), and an entry inside them this build can't read is skipped. A known item without `present` (written before it was kept) loads as present long ago: kept while listed, dropped the first time it isn't. `version` changes only for a change an older reader would misunderstand, with a migration in `AppState.init(from:)`; a file whose `version` is newer than this build's `currentVersion` isn't read (it would be misread) but set aside like an unreadable one, and shipyard starts as on a first run.
Operations: `load(at:) -> missing | loaded | setAside(URL)` at `Shipyard.start()`; `update { state in … }` changes the state and saves it (atomically, no debounce: the file is small and changes on clicks, on refreshes that found a change, and about once a day from pruning) when it changed. A file that isn't readable app state (or has a newer `version`) is renamed to `state-corrupt-<yyyyMMdd-HHmmss>.json` and shipyard starts as on a first run, with no notifications on the first refresh (bootstrap).

### Notifier — `ShipyardApp/Notifier.swift` (the `Notifying` port; tests use a recording one)

Wraps `UNUserNotificationCenter`: asks permission on the first notification (not at launch), posts a `PostedNotification` as title "e-commerce · New PR #107" (`title`: project · headline) and body "Fix checkout totals" (the item's title), with the event id as the request identifier and the item URL in its user info. Clicking the notification calls `Shipyard.openNotification(itemURL)`, which opens the item and marks it seen. `post` queues the notification and returns at once, so a refresh never waits on the permission prompt; deliveries run in order, and the first one asks. It is `@Observable`: `permission` (unknown, not asked, allowed, denied) is read without asking at launch and whenever the panel opens, and while it's denied the panel shows a "notifications are off" banner with a button to shipyard's page in System Settings. Notifications are shown even while the panel is open (the app is then frontmost), grouped per project. Outside a `.app` bundle (`make run`) there is no notification center, and it only logs.

### LaunchAtLogin — `ShipyardApp/LaunchAtLogin.swift` (the `LoginItem` port; tests use a recording one)

Wraps `SMAppService.mainApp`: `setEnabled(true)` registers the running `.app` (normally `/Applications/Shipyard.app`) as a login item, `setEnabled(false)` removes it, on a serial queue off the main thread. It compares with the service's status first, so a repeat changes nothing, and an item the user switched off in System Settings > General > Login Items (`requiresApproval`) isn't registered again at each launch; setting `launch-at-login = false` removes it either way. Failures are logged. Outside a `.app` bundle (`make run`) it only logs.

### MenuModel — `ShipyardCore/Menu/MenuModel.swift`

Pure: `build(snapshot?, config, appState, now) -> MenuModel`: sections per project in configuration order (without a snapshot, before any refresh succeeded, every project still gets a section, with no rows and `isLoaded` false, which the panel shows as "Not loaded yet" (`PanelText.emptySection`); so does a project the snapshot has no entry for, one added to the configuration since it was fetched), items filtered (kind shown, the kind's own closed window counted back from `now` with 0 hiding closed items (runs: finished ones within `finished-window-hours`, running ones always), `hide-authors`, drafts), grouped by kind (pull requests, then issues, then runs) and within each kind sorted (open or running by `updatedAt` desc, then closed or finished by `closedAt` desc), each row with its number, title (a run: its workflow's name), author, URL, semantic state (open, draft, merged, closed, running, succeeded, failed; the app's `Palette` colours it by kind: an issue's closed is purple, a pull request's red), `branch` (runs only), check dot (open and draft PRs only), `since` for its age (opened or started, or closed or finished), its `needsAttention` flag and the `item` it shows (marking it seen records that version); an error row per repository with a failed source of a kind the project shows (one row per repository, so a runs failure isn't shown where runs are off); each section's `showsRepository` (true only when its project has more than one repository, so a row's second line names the repository only there); `lastUpdated` and `fetchError` for the banner, and `bannerFetchError`, which leaves out a rate-limit error while refreshing is paused (the pause banner already says why); `refreshDelay` (configured, stretched, backed off or paused, with the API and why), `rateIndicator` and `canRefreshNow`, which `Shipyard` fills in from the rate budget; plus, from attention, each section's `attentionCount` and `isCollapsed` (a collapsed section keeps its rows and still counts), the model's `attention: AttentionCounts` and the `layout` (`list` or `tabs`, per `[menu] layout`, rebuilt with the model so a configuration change switches the open panel), the `menuBarLabel` (`total(n)`, `perKind(counts)` or `hidden`, per `[menu-bar] count`, with its text, e.g. "3" or "2 PRs · 1 run", `nil` at 0; `Shipyard` hides it outside `ready`, so a menu without projects or signed out shows no count). `applyAttention(appState, config)` recomputes just those, so a click or a collapse updates the model without a refresh. All of R3–R6's display rules live here, where tests can reach them without SwiftUI.

### UI — `ShipyardApp/UI/`

SwiftUI `MenuBarExtra` in `.window` style (a panel, not an `NSMenu`):

```tsx
<ShipyardApp> (ShipyardApp/ShipyardApp.swift)
  <MenuBarExtra label={<MenuBarLabelView>}>   icon (a pause glyph while paused) + menuBarLabel.text
    <Panel>                                   the shared frame; switch shipyard.phase
      header                  "Shipyard" · "3 need attention" · Refresh (⌘R, spins while refreshing) ·
                              gear menu: Open configuration file · Install agent skill… · Sign out (once signed in)
      signedOut              → <ConnectView>  (Onboarding/)
      connecting             → spinner        (only the device flow reaches it; its screen comes with #22)
      needsProjects          → <ProjectPicker>(Onboarding/): a field for owner/name or a link · the suggestions and typed
                              repositories as checkboxes, each chosen one with its project name and "Group with" ·
                              "Adds …" summary · Add N projects
                              <SkillInstallCard> (the offer to install the agent skill, always shown here)
      banners                 config error (any phase) · once ready: refresh delay (stretched, backed off: amber;
                              paused: red) · fetch error · notifications off (with a button to System Settings);
                              each slides in and out
      ready → switch menu.layout ([menu] layout), each given the menu model and LayoutActions
        <ListLayout>          (Layouts/) "list": a scroll view as tall as the measured rows, up to 560 pt; the window
                              sizes the panel from a zero-height proposal, so the height is fixed rather than
                              flexible (#27, MeasuredScrollView)
          header ×N           pinned while its rows scroll: chevron (click collapses/expands, spring), folder, name,
                              attention count (muted while expanded), "Nothing open" / "Not loaded yet", or on hover
                              "Mark all seen"
          row ×N              one line in columns: attention dot, state icon (check dot on it; a running run pulses),
                              number, title (semibold when it needs attention; a run: workflow name and its branch
                              as a chip), author (the repository in multi-repository projects), age; a line where
                              the kind changes; the tooltip holds the state and the full "#21 · …" detail;
                              click opens and marks seen, ⌥-click marks seen only
        <TabsLayout>          (Layouts/) "tabs": one project at a time (#36)
      <SkillInstallCard>      above the footer, after the gear menu's "Install agent skill…" (disabled in needsProjects, which shows the card), with a close button
      footer                  last updated · global "Mark all seen" · Quit (⌘Q) · rate limit lines, each with a bar
                              (amber low, red exhausted)
```

The frame and the layouts share `Design.swift`'s tokens (the spacing `Grid`, the `TypeScale`, the `Palette` of state and surface colours for light and dark, and `Motion`) and `Components.swift`'s pieces (`MeasuredScrollView`, `Banner`, `CountBadge`, `CommandBox`, the icon, pill and text button styles). A layout is a view `(model: MenuModel, actions: LayoutActions)`; `LayoutActions` (`open`, `markSeen`, `markAllSeen`, `toggleCollapsed`) comes from `AppServices`, and a layout reads the time for ages from the `panelNow` environment value the panel's 30 s timeline sets.

`ConnectView` draws `PanelText.connect(signedOutReason)`: the app's icon and a title, what happened, the `gh` command with a Copy button (`gh auth login`, or `gh auth logout` after signing out of `gh`'s token), a pointer to installing `gh` when there's no token at all, and Try again (`start()`), which says why (`PanelText.stillSignedOut`) when it leaves shipyard signed out. Try again isn't the default action, so Return can't undo a sign-out. While `start()` looks for a token (no reason yet) it shows "Connecting to GitHub…", keeping the last reason on screen during Try again. The header's gear menu has Sign out once signed in (not while `start()` is still connecting). `ProjectPicker` loads `suggestedRepositories()` when it appears (a failure says why, with Retry, and typing still works), checks a typed `owner/name` or link with `checkRepository(_:)` (a rejection shows its `message`), and keeps what the user picked in a `ProjectChoices` (`ShipyardCore/Onboarding/`, pure): the repositories offered (typed ones first, so one just added is in sight, then the suggestions), the chosen ones in order, and each one's project name, which starts as the repository's name (`owner/name` when a project already has that name, so choosing never groups by accident). Naming and grouping are one field: chosen repositories with the same trimmed name make one project, and "Group with" copies another project's name. `projects` is what Add passes to `addProjects(_:)`; `hasUnnamedProject` blocks Add while a name is empty. Adding moves the phase to `ready`, so the panel shows the list without a restart; the list scrolls inside a measured fixed height, like the sections (#27). `SkillInstallCard` draws `PanelText.skillInstall(state)` for the app's one `SkillInstallation` (owned by `AppServices`, so an install goes on while the panel is closed): the offer with the command and Install, Cancel while running, then installed with its output, the failure's output, npx not found, or timed out, each but the success with the command and a Copy button and Try again.

The words the panel shows (a row's age and second line ("#21 · yahyabedirhan · 37m" for a pull request or an issue; "#41 · main · failed · 12m" for a run, whose first line is its workflow's name; the repository after the number only when the project has more than one), a state's word and the state icon's VoiceOver label, the header ("Shipyard", "3 need attention"), "Last updated 5 min ago", the configuration, fetch error, refresh-delay and notifications-off banners, the rate-limit lines, the connect screen, the picker's Add button ("Add 2 projects") and its summary line, the skill install card) come from `PanelText` in `ShipyardCore/Menu/`, so they're tested with the menu model. The app wires the core in `AppServices` (`ShipyardApp.swift`): `ConfigWatcher` and `WakeObserver` call `reloadConfiguration()` and `refresh()`, opening the panel only rereads the notification permission (it doesn't refresh), ⌘R is the header's Refresh button, and `layoutActions` hands the layouts their `LayoutActions`. `AppServices` owns the `Notifier`, routes its clicks to `openNotification(_:)`, tells the panel whether notifications are off, and holds the `SkillInstallation`.

### RateBudget — `ShipyardCore/GitHub/RateBudget.swift`

Pure value, so the arithmetic is tested without a network. It's the answer to "can we afford the configured interval?".

State: last `RateLimit` per API (`RateAPI`: `graphql`, `rest`), the costs of the last 5 refreshes per API (averaged), and a `RatePause` (until, reason: `exhausted(api)` or `secondaryLimit`). Every question takes `now`, so it stays pure.

| Operation | Returns |
|---|---|
| `record(snapshot.rateLimits, at:)` | updates each API's limit and adds its `cost` to the average; an API the refresh didn't use (no limit reported, e.g. REST while runs are off) adds 0 once it has been measured; a limit reported at 0 with a future reset pauses until then |
| `record(error, at:)` | `.rateLimited(resetAt, api)` marks that API at 0 and pauses until `resetAt`; `.secondaryLimit(retryAfter)` pauses for `retryAfter` (60 s when it's 0 or less); the later pause wins; other errors change nothing |
| `nextDelay(configured, sharePercent, at:) -> RefreshDelay` | `paused(until, reason)` while paused; `backedOff(max(600 s, stretched), api)` if any API whose window hasn't reset has under 20% left; else `max(configured, 3600 × cost ÷ (limit × share))` over the APIs, reported as `stretched(seconds, api, cost)` when it beat `configured`, else `configured` |
| `canRefresh(at:) -> Bool` | false only while paused (⌘R uses this) |
| `indicator(show, in: apis, at:) -> RateIndicator?` | what the footer draws: per API in use (`Shipyard` passes REST only while some project shows workflow runs, so a REST line doesn't linger stale once runs are off) remaining / limit, reset time and level (`normal`, `low` under 25% (ghbar's threshold), `exhausted` at 0; a window that has reset counts as normal), and the worst level for the colour; `nil` for `never`, for `when-low` while all are normal, or before any limit is known |

After every refresh `Shipyard` asks `nextDelay`, publishes it and the indicator in the menu model, and arms the refresh timer with it (`paused` arms for the time left until the pause ends), so a busy hour slows shipyard down on its own instead of running the limit dry. Workflow runs (REST) only have to report `rateLimits.rest` with the counted requests as `cost`.

### SkillInstaller — `ShipyardCore/Skill/SkillInstaller.swift`

Runs the user's login shell as an interactive one (`$SHELL -l -i -c 'npx -y skills add yahyabedirhan/shipyard -g -y'`, `/bin/zsh` when `$SHELL` isn't an absolute path) so nvm/asdf/Homebrew `PATH` setups are loaded. Spawning sits behind the `ShellRunning` port (`ProcessShellRunner` runs it with `Process`, standard input empty, output and errors read together), so tests use a fake shell. Cancelling `ProcessShellRunner`'s task returns `nil` at once and sends SIGTERM, then SIGKILL a second later, to the shell and every process under it (found with `ps`): an interactive shell ignores SIGTERM and runs the command as a job in its own process group, which would outlive it and hold the output pipe open. The panel doesn't call `install()` itself: `SkillInstallation` (`Skill/SkillInstallation.swift`, `@MainActor @Observable`) runs one install at a time and holds its state (`idle`, `running`, `finished(result)`, `timedOut(seconds)`); `start()` races the install against a 180 s timeout (the sleep is injected, so tests don't wait), `cancel()` goes back to `idle` at once and stops the shell (a result that arrives after is dropped, so Install can start again straight away), and a timeout stops the shell and says so.

| Operation | Returns |
|---|---|
| `install() async -> SkillInstallResult` | `installed(output)` on status 0; `npxNotFound(command)` on status 127 (the shell couldn't find `npx`), with `SkillInstaller.command` for the Copy button; `failed(output)` otherwise: what it printed, colour codes stripped, or "exited with status N" when it printed nothing, or "couldn't start <shell>" |

The skill it installs is `skills/shipyard/SKILL.md`, where `npx skills add` looks for a repository's skills (`skills/<name>/SKILL.md`, with `name` and `description` frontmatter). It documents the configuration file for agents; `SkillDocumentTests` decode each of its TOML examples with `Configuration.decode`, check them against the schema, and check that it names every key, default, event and author filter the code has.

### Folder tree

```text
shipyard/
├── Package.swift                     # SwiftPM: ShipyardCore (library) + ShipyardApp (macOS app target, `Shipyard` executable, declared only on macOS) + tests; one dependency: TOMLDecoder
├── .github/workflows/ci.yml          # core build + tests on Ubuntu (Swift 6); everything built, bundled and tested on macOS
├── Makefile                          # build, test (finds the Testing framework under Command Line Tools), bundle .app, ad-hoc sign, zip, install
├── Packaging/Info.plist              # LSUIElement (no Dock icon), bundle id, version
├── schema/config.schema.json         # public contract for config.toml (ADR 0001); JSON Schema describes TOML too
├── skills/shipyard/SKILL.md          # teaches agents the config file; installed by `npx skills add`
├── Sources/ShipyardCore/             # Foundation, FoundationNetworking, Observation and TOMLDecoder only, so agents can build and test it on a Linux VPS
│   ├── Shipyard.swift                # orchestrator: phase, refresh pipeline, user actions (@Observable)
│   ├── Lifecycle.swift               # Phase (signedOut, connecting, needsProjects, ready) and its transitions
│   ├── Version.swift                 # ShipyardVersion.current: the one place the version is recorded
│   ├── RefreshScheduler.swift        # RefreshGate (one at a time, queues one more) + RefreshTimer port and its Task-based timer
│   ├── Ports.swift                   # what the app plugs in: Notifying, TokenStore, WallClock, URLOpening, LoginItem
│   ├── Config/
│   │   ├── Configuration.swift       # file model, defaults, per-project merge, append text
│   │   ├── ConfigurationReader.swift # decode + validation: typed reads, errors, unknown-key warnings, suggestions
│   │   ├── TOMLSourceMap.swift       # key path → line, for validation messages
│   │   └── ConfigStore.swift         # path, reload, last-valid fallback, append projects
│   ├── GitHub/
│   │   ├── HTTPTransport.swift       # the one request seam: URLSession in the app, recorded responses in tests
│   │   ├── GitHubClient.swift        # transport (GraphQL + REST), errors, viewer, rate-limit headers, ETags
│   │   ├── RateBudget.swift          # quota per API, refresh cost, next allowed delay, indicator
│   │   ├── ProjectQuery.swift        # builds the GraphQL query and parses it into Items
│   │   ├── Repositories.swift        # the picker's calls: recent repositories (GraphQL), checking a typed one (REST); RepoSummary, RepositoryCheck
│   │   ├── WorkflowRuns.swift        # REST runs request + parse + branch filter
│   │   └── Auth/
│   │       ├── TokenProvider.swift   # TokenStore → gh → none; GhCLI finds and runs gh
│   │       └── DeviceFlow.swift      # OAuth device flow
│   ├── Items/
│   │   ├── Item.swift                # Item, Snapshot, RepositoryError, RateLimit, fingerprint
│   │   ├── Attention.swift           # needs-attention rule, seen records, counts
│   │   ├── EventDetector.swift       # known items + snapshot → events; Event, ItemChange, KnownItems
│   │   └── NotificationRules.swift   # event + project settings → notify?; what to post; NotifiedEvents
│   ├── State/
│   │   └── AppStateStore.swift       # AppState + state.json: seen, collapsed, known items and sources, notified; tolerant, versioned
│   ├── Menu/
│   │   ├── MenuModel.swift           # pure: sections, rows, semantic state colours, label
│   │   └── PanelText.swift           # pure: row age and second line, a state's word and the state icon's VoiceOver label, "Last updated N min ago", config, fetch error, refresh-delay and notifications-off banners, rate-limit lines, the connect screen's words, the picker's Add button and summary, the skill install card
│   ├── Onboarding/
│   │   └── ProjectChoices.swift      # pure: the picker's offered and chosen repositories, names and grouping → [NewProject]
│   └── Skill/
│       ├── SkillInstaller.swift      # runs npx skills add in the login shell (ShellRunning port, cancellable), SkillInstallResult
│       └── SkillInstallation.swift   # one install as the panel shows it: running, result, timeout, cancel
├── Sources/ShipyardApp/              # macOS app (module ShipyardApp, executable Shipyard): thin Apple-framework layer over ShipyardCore
│   ├── ShipyardApp.swift             # @main, MenuBarExtra wiring; AppServices builds the core with the adapters below, routes notification clicks and holds the panel's actions
│   ├── ConfigWatcher.swift           # watches the config directory (and file), calls Shipyard.reloadConfiguration()
│   ├── Wake.swift                    # NSWorkspace wake → refresh trigger
│   ├── Workspace.swift               # URLOpening on NSWorkspace; opens config.toml in its editor (TextEdit when none)
│   ├── Placeholders.swift            # session-only token store (never written in 0.0.x: gh only) until Keychain.swift (#22)
│   ├── Keychain.swift                # TokenStore on the login keychain (#22, with sign-in without gh)
│   ├── Notifier.swift                # Notifying on UNUserNotificationCenter; permission on first post; click → openNotification
│   ├── LaunchAtLogin.swift           # LoginItem on SMAppService.mainApp: registers or removes the running .app; a repeat, or an item the user switched off in System Settings, is left as it is
│   └── UI/
│       ├── Panel.swift               # the shared frame: header, banners, phase switch, layout switch, footer
│       ├── Design.swift              # design tokens: spacing grid, type scale, Palette (state and surface colours, light/dark), motion
│       ├── Components.swift          # shared pieces: measured scroll view (#27), banner, count badge, command box, button styles
│       ├── SkillInstallCard.swift    # the skill install: offer, Cancel, result, command to copy
│       ├── Layouts/
│       │   ├── LayoutActions.swift   # what a layout can do: open, mark seen, mark all seen, collapse
│       │   ├── ListLayout.swift      # [menu] layout = "list": pinned project headers, one line per item
│       │   └── TabsLayout.swift      # [menu] layout = "tabs" (#36)
│       └── Onboarding/
│           ├── ConnectView.swift     # why signed out, the gh command to copy, Try again
│           └── ProjectPicker.swift   # suggestions, a typed repository, names and grouping, Add
└── Tests/ShipyardCoreTests/          # end-to-end through Shipyard + focused tests per pure module
    ├── Harness.swift                 # the main seam: a Shipyard over the doubles, temp config + app-state dirs, fixture answers, relaunch
    ├── PullRequestsResponse.swift    # builds a GraphQL answer (PRs and, when asked, issues per repository), for scenarios that change an item between refreshes
    ├── WorkflowRunsResponse.swift    # builds a REST runs answer (with ETag, or a 304), for scenarios that change runs between refreshes
    ├── Onboarding/                   # ProjectChoices: choosing, typing, naming, grouping
    ├── Skill/                        # the installer against a fake shell, SkillInstallation against a hanging one; the skill document against the code and the schema
    ├── Fixtures/                     # recorded-shape GitHub responses (GraphQL, REST runs, errors); excluded from the target, read from the source tree
    └── Doubles/                      # in-memory ports: token store, recording notifier, manual clock, manual refresh timer, recording URL opener, recording login item; stub HTTP transport, fake gh, fake shell, hanging shell, instant sleeper
```

Shipyard is a macOS app and only ships for macOS. The package has two targets so that the implementation agents, which run on a Linux VPS, can build and test everything holding a rule without a Mac; Linux is a development environment, not a platform shipyard supports. `ShipyardCore` imports only Foundation, FoundationNetworking (on Linux), Observation and TOMLDecoder, all of which exist on Linux (Observation ships with the Swift toolchain; the rule keeps Apple-only frameworks out); the rules live there: configuration, the GitHub client, attention, events, notification rules, the rate budget, the menu model, and the orchestrator itself. It reaches Apple-only services through a few small protocols in `Ports.swift`, and the `ShipyardApp` target supplies them (its module isn't called `Shipyard`, which is the core's orchestrator class): the Keychain, notifications, file watching (`DispatchSource` file-system sources are Darwin-only), wake, login item, and the SwiftUI views. Tests target `ShipyardCore`, so they run on the VPS; the app target is built and checked on macOS.

---

## 4. Implementation

### Shipyard.refresh() — the pipeline

```text
refresh()
  guard phase == ready else return
  guard budget.canRefresh(now) else { timer.arm(until pause ends); return }   // ⌘R, wake: nothing sent while paused
  guard gate.begin() else return                      // queued; runs again after this one
  config = configStore.lastValid
  do
    snapshot = await request { github.fetch(projects: config.projects.map(config.settings), at: clock.now) }   // every call goes through request (401 → signedOut)
  catch unauthorized
    phase = signedOut; gate.finish(); return
  catch rateLimited(resetAt, api) / secondaryLimit(retryAfter)
    rebuildMenu(config)   // MenuModel.build(snapshot (or nil: not loaded yet), config, …), keeping fetchError, refreshDelay, rateIndicator
    budget.record(error, now); fetchError = error; menu.fetchError = error; gate.finish(); timer.arm(budget.nextDelay(…)); return
  catch other
    rebuildMenu(config)
    fetchError = other; menu.fetchError = other; gate.finish(); return   // keep old snapshot, rows and lastUpdated
  appStateStore.update { state in                     // saves only if it changed
    events = EventDetector.events(state.known, snapshot, projects)   // first sight of a project's source: none
    for id, occurrences in events grouped by id where id ∉ state.notified   // an item in two projects: one event
      if first occurrence whose project's rules select it (NotificationRules.shouldNotify, hide-authors)
        toPost.append(NotificationRules.notification(for: it))
      state.notified.insert(id)                         // notified or not, never again
    state.known = state.known.updated(with: snapshot, projects); state.notified.prune(present: known items, now)
    state.attention.prune(present: snapshot items, now)
  }
  self.snapshot = snapshot; fetchError = nil
  budget.record(snapshot.rateLimits, now)
  menu = MenuModel.build(snapshot, config, appState, now)   // Panel re-renders from it
  delay = budget.nextDelay(config.refreshIntervalSeconds, config.rateLimit.maxSharePercent, now)
  menu.refreshDelay = delay; menu.rateIndicator = budget.indicator(config.rateLimit.show, in: [graphql] + [rest if any project shows runs], now)
  for n in toPost: await notifier.post(n)              // after saving: a crash loses one rather than repeating it
  timer.arm(delay.seconds(from: now))
  if gate.finish() then refresh()                     // a queued trigger arrived meanwhile
```

### Attention.needsAttention(item)

```text
needsAttention(item, t)
  if item.state in {merged, closed, running, succeeded} return false   // runs: only failed ones, until seen
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
    shipyard.follow(.changed(config))  // phase may move to/from needsProjects; rebuildMenu(config) from the last snapshot at once (paused or failing too); triggers refresh
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

GraphQL points are GitHub's estimate: roughly the total nodes the query could return ÷ 100, and the nested per-PR lists (`reviewRequests`, last commit's checks) dominate it. To keep it low, `reviewRequests` asks for `first: 10` and the head commit for `last: 1`, and closed items for `first: 20`. The 5-repository row is measured with `rateLimit(dryRun: true)` against the query shape above; the others scale it. The real cost comes back in `rateLimit.cost` on every response, and `RateBudget` uses the measured figure, not this table. So a user with 10 repositories gets their 2 minutes; a user with 40 gets about 7 minutes and a panel line "Refreshing every 7 min to stay within 10% of your GraphQL rate limit (a refresh costs 56 points)".

### Trace 1: an agent opens a PR (happy path)

Setup: phase `ready`, project `e-commerce` known, `known` holds e-commerce-backend's 3 open PRs, attention count 0. An agent opens e-commerce-backend#57.

| Step | Call (owner) | State after |
|---|---|---|
| 1 | refresh timer fires → `Shipyard.refresh()` | gate running |
| 2 | `GitHubClient.fetch` (GitHub/) | snapshot has 4 open PRs, #57 `checks: pending`, `author: me` |
| 3 | `EventDetector.events` (Items/) | `[pr.opened #57 author=me]` |
| 4 | `NotificationRules.shouldNotify` (Items/) | default rule `pr.opened any` → true |
| 5 | `AppStateStore.update` (saved before posting) | `notified` has #57's `pr.opened`; `known` has #57 (checks pending) |
| 6 | `Notifier.post` | macOS notification "e-commerce · New PR #57" / "Add order export" |
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
| 3 | `Panel` | amber footer `GraphQL 900 / 5,000 · resets 16:42`, banner "Your GraphQL rate limit is low (other tools are using it). Refreshing every 10 min." |
| 4 | agents keep going; next refresh gets 403, `x-ratelimit-remaining: 0`, `x-ratelimit-reset` = 16:42 | `pausedUntil = 16:42`, `fetchError = rateLimited` |
| 5 | menu bar icon shows the paused glyph; ⌘R does nothing and says why | last snapshot still listed, "Last updated 14 min ago" |
| 6 | 16:42: timer armed for `pausedUntil` fires | quota back to 5,000; next delay 120 s; banner gone |

What the traces turned up and the design now handles: the first refresh after adding a project must not notify for every existing PR (the first-sight guard in step 3: a project's sources not fetched before make no events), and `pr.checks_failed` has to be an event whether or not a rule is enabled, so a rule added later behaves the same.

---

## 5. Extensibility

| Change | What you touch |
|---|---|
| New event (e.g. `pr.review_submitted`) | `EventDetector` (one transition), the event enum in `Configuration`, `schema/`, `SKILL.md` |
| Split count by kind in the menu bar | nothing: `[menu-bar] count = "per-kind"` already exists |
| Quick actions (merge, close) | `GitHubClient` (one mutation), `ListLayout` row context menu |
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
