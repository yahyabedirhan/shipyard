# Shipyard: low-level design

Agreed 2026-09-25; the 0.0.2 changes agreed 2026-09-26 (their decisions, with the reasons, are in `.handoff/2026-09-26-shipyard-0.0.2-decisions.md`; the lasting ones are ADRs 0002 and 0003). Terms are the ones in `GLOSSARY.md`; the configuration decision is `docs/adr/0001-configuration-is-a-toml-file-agents-edit.md`; facts about GitHub's API are in `docs/references/`. When the code and this document disagree, fix one of them in the same change.

**For a newcomer, in one screen.** Shipyard is one Swift executable. `Shipyard` (the orchestrator) owns the app's lifecycle and runs a **refresh**. A refresh reads the **configuration**, fetches every project's items from GitHub, compares the result with what it saw last time to find **events**, sends the notifications the **rules** allow, and publishes a **menu model** the SwiftUI panel draws. Everything the app remembers about the user (seen items, collapsed sections, the last items it knew) is **app state**, kept apart from the configuration.

Since 0.0.2 a refresh also **resolves** each project's repository selectors (groups such as `owned`, and wildcards such as `owner/*`) into repositories, fetches them in batches with one **review search** (the open PRs waiting on the user, teams included), and then works from each project's **listing**: the items its filters keep. The menu, the counts and the notifications all read the listing, and an **arrangement** groups, sorts and caps it for the panel.

Since 0.0.5 agents also send the user **pings** with the `shipyard` command line, a second executable bundled in the app (ADR 0004). The **ping command** files a ping under the projects that watch the repository of the agent's working folder (or `--repo`, or the one `--project` names), matching against the configuration and the repository lists the app last resolved, and writes it to the **ping store**, one file per ping in Application Support, which the app watches; a ping is listed as a fourth kind of item beside the fetched ones, with no GitHub request.

```text
agent ──▶ shipyard ping (CLI) ──▶ PingCommand ──▶ PingStore (Pings/<id>.json) ──watched──▶ Shipyard.reloadPings()
                                       ▲                                                     │
              config.toml (projects) + repositories.json (last resolved)    Listing (pings among the items) ──▶ MenuModel
              + git remote origin (working folder)
```

```text
config.toml ──▶ ConfigStore ─┐
                             ▼
             RepositoryResolver ──▶ GitHub (repository lists, hourly)
                             │ concrete repositories
                             ▼
GitHub ◀── GitHubClient ◀── Shipyard (refresh) ──▶ Notifier ──▶ macOS notifications
  (batches + review search)  │   ▲
                             ▼   │ click / fold / Show more
                          Listing (what each project has) ──▶ EventDetector / NotificationRules
                             │
                             ▼
                   MenuModel + Arrangement ──▶ Panel (SwiftUI)
                             ▲
                       AppStateStore (seen, known, collapsed projects and groups)
```

---

## 1. Requirements

### Capabilities

| # | Requirement |
|---|---|
| R1 | Live in the macOS menu bar as an icon plus one **attention count**; clicking it opens a panel. |
| R2 | Show one collapsible section per **project**, in configuration order. A project is one or more GitHub repositories. |
| R3 | In each project, list pull requests: open ones, then ones closed within the **closed window** (default 7 days), newest first; which ones is the project's **listing**, decided by its filters (F1–F5). |
| R4 | Colour pull requests by GitHub's convention: open green, draft gray, merged purple, closed red. Open PRs show a check-status dot. |
| R5 | List issues the same way when the configuration turns them on (off by default). |
| R6 | List **workflow runs** when turned on (off by default): running now, plus finished within the last N hours (default 3), on the default branch and open PR branches. |
| R7 | Clicking an item opens it on GitHub and marks it **seen**. ⌥-click marks it seen without opening. "Mark all seen" exists per project and globally. Opening the panel marks nothing. |
| R8 | An open item **needs attention** when it is unseen, changed since seen (commits, comments, reviews, checks, review request), requests the user's review, or has failed checks. Closed items never do. |
| R9 | Send macOS notifications for **events** matched by **notification rules** (event + scope + author selectors, F2). Default: `pr.opened`, any author, all projects; since 0.0.5 `ping.sent` too (N7). |
| R10 | Refresh on an interval (default 120 s), when the Mac wakes, when the configuration changes, and on ⌘R. Opening the panel doesn't refresh: it shows the last fetched data and spends no GitHub request. |
| R11 | Read everything the user controls from `~/.config/shipyard/config.toml` (honouring `$XDG_CONFIG_HOME`), apply edits live, and publish a JSON Schema for it (referenced by `#:schema`, checked with `taplo check`). |
| R12 | Keep app state (seen, known items, collapsed sections, notified) in `~/Library/Application Support/Shipyard/state.json`, never in the configuration. |
| R11a | After every reload, record the verdict on the configuration file (accepted, or each problem with its line and the banner's text) in `~/Library/Application Support/Shipyard/config-status.json`, with when it was checked and the file's modification time, so an agent can confirm the app took its edit without seeing the banner (#48). |
| R13 | Onboarding: connect GitHub by reusing `gh`'s token silently, or with **Sign in with GitHub** (the device flow, the token in the login Keychain, S1); then, whenever there are no projects, choose a **preset** and pick repositories (P2), which writes the configuration. |
| R14 | Offer to install the shipyard skill during onboarding and from the panel's menu, by running `npx -y skills add yahyabedirhan/shipyard -g -y` for the user. |
| R15 | Launch at login (on by default, configurable). |
| R10a | Spend at most `max-share-percent` (default 10%) of each GitHub hourly limit (GraphQL points, REST requests). If a refresh at the configured interval would spend more, stretch the interval and say so in the panel. |
| R10b | The limit is shared with everything else using your token (your agents' `gh` calls included). Below 20% remaining, refresh every 10 min; at 0, pause until the reset time. ⌘R still works while any limit remains. |
| R16 | Show the rate limit in the panel footer: remaining / limit per API and when it resets (ghbar's indicator). Configurable: `always` (default), `when-low`, `never`. When paused, the menu bar icon changes and a banner says why. |
**Added in 0.0.2** (effort `shipyard-0-0-2`):

| # | Requirement |
|---|---|
| F1 | Each kind (`pull-requests`, `issues`, `workflow-runs`) takes `authors = { show = […], hide = […] }`, in `[defaults.*]` and per project. An item is listed when its author matches `show` (empty: everyone) and doesn't match `hide`; `hide` wins. It replaces the top-level `hide-authors`. |
| F2 | An **author selector** is an author group (`me`, `others`, `bots`) or a login written `@login` (`@dependabot[bot]`), matched ignoring case (ADR 0002). `me` is the signed-in account, so agents working as the user count as `me`; `bots` is a GitHub `Bot` account or a login ending in `[bot]`; `others` is everyone else. Notification rules take the same selectors. |
| F3 | Each kind takes `states`: pull requests `open`, `merged`, `closed` (default all three); issues `open`, `closed`; runs `in-progress`, `failed`, `succeeded`. `drafts`, `closed-window` and `finished-window` stay: `states` picks which, the window says for how long. |
| F4 | `pull-requests.review-requested = true` lists only open PRs waiting on the user's review. A request to the user or to one of their teams counts, and the same meaning drives attention's `review-requested` and the `pr.review_requested` event. |
| F5 | An item a project's filters leave out is not listed, not counted (header, tab, menu bar) and not notified; a notification rule's `authors` only narrows what's listed (ADR 0003). Filters apply the same in both layouts, the All tab included. |
| G1 | `repositories` takes **repository selectors**: `owner/name`, `owner/*` (everything under a user or organization), and the **repository groups** `owned` (the user's own account), `organizations` (through membership of an organization, teams included) and `collaborator` (someone else's repository that added the user). There's no top-level scope switch. |
| G2 | `anywhere` is a repository group for open PRs anywhere on GitHub waiting on the user's review. A project using it must show pull requests with `review-requested = true`, and shows no issues or runs. |
| G3 | `archived` (default `false`) and `forks` (default `true`), in `[defaults]` and per project, decide whether groups and wildcards bring in archived repositories and forks. A repository named as `owner/name` is always included. |
| G4 | The repositories behind groups and wildcards are looked up at launch, after a configuration change, on ⌘R and otherwise at most hourly, so a new repository shows up without editing the file. A repository appears once per project, however many selectors bring it in. |
| G5 | Any number of repositories refreshes: the fetch goes out in batches, and the rate budget stretches the interval as it does today. |
| A1 | `group-by = "kind" \| "repository" \| "date" \| "author" \| "none"` (default `"kind"`, today's grouping), in `[defaults]` and per project; one level of groups. |
| A2 | `subsections = true \| false`: groups drawn as subheaders (a name and a count) or as dividers. Unset, each layout keeps what it does today: dividers in the list, subheaders in a tab. A value set applies to both layouts. |
| A3 | `sort-by = "updated" \| "created" \| "title"` (default `"updated"`) sorts within a group, newest first or A to Z; open (or running) items always come before closed (or finished) ones. `group-by = "date"` buckets by the `sort-by` date (`updated` for `title`): Today, Yesterday, This week, This month, Older. |
| A4 | A subsection folds like a project (click its subheader, ← and →); the fold is app state and survives restarts. |
| A5 | `show-first = N` (default `0`, all) shows a group's first N rows and a **Show N more** row, which becomes **Show less**; the keys reach it and Return toggles it. Expansions reset when the panel closes. With `group-by = "none"` the cap applies to the whole project. |
| A6 | The list layout and a project's tab arrange a project the same way; the All tab keeps a fixed look: grouped by kind, newest first. |
| P1 | Three **presets** are part of the app: `my-agents`, `incoming-contributions`, `review-queue`, each a complete configuration to start from. The skill lists them, and a test keeps its copies equal to the app's. |
| P2 | Onboarding starts by choosing a preset: `my-agents` then shows the repository picker; `incoming-contributions` offers "all my repositories (`owned`)", on by default, or picking; `review-queue` needs no repositories. |
| S1 | Sign in without `gh` (formerly #22): the connect screen offers **Sign in with GitHub** (the device flow) beside the `gh` instructions; the token goes to the login Keychain and survives restarts; Sign out deletes it; a revoked token returns to the connect screen; the README says how a fork sets its own OAuth App client ID. |

**Added in 0.0.5** (effort `shipyard-0-0-5`, pings, spec #96; Trace 6 follows one ping through them):

| # | Requirement |
|---|---|
| N1 | `shipyard ping "<title>"` stores a **ping**, filed as N6 says or under the one project `--project <name>` names, prints its id (N12) and exits 0. A `--project` the configuration doesn't name fails with the projects listed and exit 1; arguments that don't read fail with exit 2. Exit 0 is done, 1 refused, 2 a usage error, and every error is one line on standard error (#97). |
| N2 | The `shipyard` CLI is a second executable in `Shipyard.app` (`Contents/Helpers/shipyard`), a thin wrapper over the core's `ShipyardCLI`; `ping` is its one command so far (ADR 0004). It needs neither the app running nor GitHub, and the app links it onto the PATH (N10). |
| N3 | A ping is a fourth kind of item: listed under its project, in a "Pings" group under `group-by = "kind"`, in the list, its project's tab and the All tab. It needs attention until seen (whatever `[attention]` says) and counts in its project, its tab and the menu bar. Clicking its row (or ⌥-click, or Mark all seen) marks it seen. |
| N4 | Pings are kept in the **ping store**, apart from `state.json`, and survive restarts: one sent while the app isn't running shows when it starts, one sent while it runs shows when the store changes, with no GitHub request, even before GitHub has answered. |
| N5 | `[defaults.pings] show` (default `true`) and a project's `pings = { show = … }` decide whether pings are listed; `states`, `authors`, `drafts` and `review-requested` under pings are rejected with their line. |
| N6 | Without `--project`, a ping is filed under every project that watches the repository of the agent's working folder (its git remote `origin`, as `owner/name`); `--repo <owner/name>` names the repository instead, and `--repo` with `--project` is a usage error (exit 2). A project watches a repository its configuration names as `owner/name`, or one the app last resolved for it (a group or `owner/*`), matching ignoring case; the CLI never calls GitHub. No match (not a git folder, no `origin`, a remote that isn't `owner/name`, or a repository no project watches) fails with the projects listed and exit 1 (#98). |
| N7 | A new ping posts one macOS notification through the ordinary notification rules, as the event `ping.sent`, which is in the default rules: titled "<project> · <ping title>", its body the ping's body and "from <sender>" (each when given). A project whose rules leave out `ping.sent` doesn't notify for pings, and a rule with `authors` never selects one (a ping has no GitHub author). A ping is notified at most once, keyed by its id, so a replace never posts again; clicking the notification marks the ping seen (#99). |
| N8 | `--open <url>` (any scheme, app deep links included) or `--app <bundle id or name>` gives a ping its action; more than one action flag, a URL without a scheme or an empty app is a usage error (exit 2); no action is allowed. `--body <text>` and `--from <label>` are stored (empty is none). Clicking the ping's row or its notification runs the action through the action port and marks the ping seen; a ping without an action is only marked seen; ⌥-click marks it seen without running it. A failed action keeps the ping as it was (unseen stays unseen) and shows the port's short reason on its row (the tabs' second line, the list's meta column, the hover card) until the next click that works, an ⌥-click, Mark all seen or a dismiss. The row's icon says what clicking does (link, app, terminal for Herdr, none); its second line is the sender and the body, its card the whole body and where it goes. `group-by = "author"` groups pings by sender, after the GitHub authors; pings without one sit in the "Pings" group, last (#100). |
| N9 | A seen ping stays listed for its project's `seen-window` (`[defaults.pings] seen-window`, default `"24h"`, written like `closed-window`; a project's `pings = { seen-window = … }` overrides it; `"0"` lets it leave once seen), counted from when it was seen, then leaves; an unseen ping never leaves on its own. A ping that has left every project it's filed under is removed from the ping store, checked on every refresh and whenever the pings are read again (a store change, a click, a dismiss). Mark all seen, per project and for all, marks pings seen too. A ping's row has a ✕ while it's highlighted, and ⌫ on the highlighted ping row does the same: the ping is removed now, seen or not, from every project, with any failure on it (#103). |
| N10 | Like the skill install (R14), onboarding and the panel's menu offer to link the bundled CLI: **Link** makes `~/.local/bin/shipyard` a symbolic link to `Shipyard.app/Contents/Helpers/shipyard` (making `~/.local/bin` when it's missing). It never replaces anything: a link already pointing at this app's CLI shows as linked and is left alone; anything else there (a file, a folder, a link elsewhere, as from an older copy of the app) or a link that can't be made (no permission) shows why, with `mkdir -p ~/.local/bin && ln -sf <the app's CLI> ~/.local/bin/shipyard` and a Copy button, and Try again. A copy of the app without the CLI inside (`make run`) says there's nothing to link. Linked, it reminds the user to put `~/.local/bin` on their PATH (#104). |
| N11 | `--herdr [<tab or pane id>]` gives a ping a Herdr action, a third action flag (still one at most). The argument after it is its id only when it's shaped like a Herdr id (`<workspace>:t<n>` or `<workspace>:p<n>`, as Herdr prints them); otherwise `--herdr` means the agent's own pane, `HERDR_PANE_ID`, and without that variable (outside Herdr) it's a usage error (exit 2). Clicking the ping (row or notification) focuses the tab, or the tab the pane is in (`herdr pane get`, then `herdr tab focus`; Herdr's CLI focuses no pane by id), then brings `[herdr] terminal` (an app name or bundle id, unset by default) forward as an `--app` action would; without it only the focus runs. A gone pane or tab, `herdr` not found, Herdr not running, or a terminal that won't come forward fails the action as in N8. The row's icon is a terminal, its card "Focuses <id> in Herdr" (#101). |
| N12 | Ids are global: one names one ping wherever it's filed. `--id <id>` names a ping (1 to 64 lowercase letters, digits, `-` and `_`, starting with a letter or digit; anything else is exit 2); without it one is made up and printed. Sending an id that's stored replaces that ping: title, body, sender, action and filing are the new ones, its sent time stays, it's unseen again with no failure (so it needs attention again), and no second notification is posted. `shipyard ping withdraw <id>` removes the ping, prints the id and exits 0; the app takes it out of the menu and its notification out of Notification Center. An id no ping has fails with one line and exit 1; no id, two, or one that isn't an id is exit 2. Withdraw reads no `config.toml`. `--` ends the flags, so a title can be `withdraw` or start with `--` (`shipyard ping -- withdraw`). A ping that leaves any way (withdrawn, dismissed, past its seen-window, or gone while the app wasn't running) takes its notification with it and is forgotten, so its id sent again later is a new ping that notifies again (#102). |
| N13 | The shipyard skill teaches agents the CLI beside the configuration: when to ping, every flag, the exit codes, where a ping is filed, replacing and withdrawing, and worked examples ("ping me when the PR is ready", "bring me back to this pane" with `--herdr`, "withdraw it when I've answered"). It says a file that lists its own notification rules needs `ping.sent` added, and lists `[defaults.pings]` and `[herdr]` with the other keys. A test checks the skill against `PingCommand`'s help and reads each example command as the CLI does (#105). |

### Rules and completion

- The app writes the configuration in three targeted ways only (ADR 0001): the project picker appends projects (R13), the layout button sets `[menu] layout`, and onboarding writes a preset (P2), only to a file whose only live key is `version` (the app's own commented header). Every other change comes from the user or their agents editing the file.
- Resolved repository lists are app memory, not app state: they're resolved again at launch. Since 0.0.5 each resolve also writes them to `repositories.json` for the `shipyard` CLI (`ResolvedRepositoriesStore`), which the app never reads back.
- Every fetched item is recorded as known, listed or not, so an item a later filter change brings into view doesn't notify as though it were new (ADR 0003).
- The first time shipyard sees a project, it records its items as known **without** notifying (no flood on first launch or on adding a project). This is ghbar's "bootstrap" lesson.
- An item is notified at most once per event (ghbar's other lesson: "seen" and "notified" are separate sets).

### Error handling

| Situation | Behaviour |
|---|---|
| Configuration file is invalid TOML or fails validation | Keep the last valid configuration, show the error (file, line, message) at the top of the panel and record it in `config-status.json`. Never blank the list. |
| No configuration file | Treat as defaults with no projects → project picker. |
| Token missing or rejected (401) | Go to the signed-out state → onboarding's connect step, which says why (no `gh` token, or GitHub rejected it) and to run `gh auth login`. |
| One repository not found or not accessible | That project shows an error row for it; other repositories and projects still show. |
| Network down / GitHub 5xx | Keep the last items, show "Last updated 4 min ago · can't reach GitHub" in the panel. Retry on the next trigger. |
| Rate limit exhausted: GraphQL answers **200** with a rate-limit error and `x-ratelimit-remaining: 0`; REST answers 403/429 | Keep the last items; banner "GraphQL rate limit reached · updates resume at 16:42" (`PanelText.refreshDelay`); the reset time comes from the response (`resetAt` / `x-ratelimit-reset`), not ghbar's one-hour guess. |
| Secondary rate limit (403/429 with `retry-after`) | Wait `retry-after` seconds, then resume; banner says so. |
| `npx` not found | Show the command with a Copy button instead of running it. |
| A bare word in `authors` that isn't an author group | Rejected with its line: "unknown author `bots2` (did you mean `bots` or `@bots2`?)" |
| A repository group in `authors`, or an author group in `repositories` | Rejected: "`owned` is a repository group; `authors` takes `me`, `others`, `bots` or an `@login`" |
| `anywhere` without `review-requested = true`, or with issues or runs shown | Rejected: "`anywhere` needs `pull-requests = { review-requested = true }`, and lists no issues or runs" |
| An unknown `group-by`, `sort-by` or `states` value | Rejected with the nearest valid one suggested |
| `owner/*` for an owner that doesn't exist or can't be seen | An error row in that project for the selector; its other selectors still list |
| A group resolves to no repositories | The project shows "Nothing open", not an error |
| Resolving fails (network, rate limit) | Keep the last resolved lists and fetch with them; the fetch error shows as today |
| The review search fails | Watched repositories still list; `review-requested` projects and `anywhere` show the search's error row |
| An old `hide-authors`, or an old notification `authors = "others"` | Read as the new form with a warning (the quiet banner and `config-status.json`), so the file keeps working |

### Out of scope

| Excluded | Why |
|---|---|
| Reviewing inside the app (diff, comments), merge/close actions | Agreed: click-through to GitHub for now. |
| A CLI for the configuration, or a settings window | ADR 0001: the file is the interface. The panel's menu only has "Open configuration file". The `shipyard` CLI (0.0.5) sends pings only (ADR 0004). |
| GitLab, GitHub Enterprise, several accounts | Nobody asked; the GraphQL host is one constant if GHE comes up. |
| Telling agent PRs from hand-written ones | Agreed: not reliable today (see Extensibility). |
| Mac App Store build | The sandbox forbids running `gh`/`npx` and reading `~/.config`. |
| Developer ID signing, notarization | Agreed: ad-hoc signed zips and the `xattr` line until 0.1.0 at the earliest. |
| Push updates (webhooks) | Needs a server; polling is enough at this scale. |
| Deployments waiting for the user's approval | Deferred from 0.0.2: a later `workflow-runs` filter |
| `assigned` and `mentioned` filters | Nobody needs them yet; each is a field and one check in `Listing` later |
| Oldest first, a sort direction, nested grouping | Not asked for; each is one more choice later |
| Folding busy projects automatically (ghbar folds repositories with more than three items) | Deferred: the maintainer doesn't need it yet |
| The picker offering repository groups other than a preset's `owned` | Groups come through the skill in 0.0.2 |
| More than 100 review requests at once | The search returns the first 100; the section says so when there are more |
| More than one action per ping, buttons on its notification, or a shell command as an action | Spec #96: one clear action, and nothing a ping runs beyond opening, activating or focusing |
| Pings filed under no project, a maximum age for unseen pings, a sender inferred from Herdr | Spec #96: a ping is always filed, stays until seen, and says only what the agent passes |
| Pings from other machines, remote Herdr, syncing pings | Spec #96: pings stay on the Mac, in the ping store |

---

## 2. Entities and relationships

Nouns from the requirements, sorted:

| Noun | Entity or field? |
|---|---|
| Shipyard (the app) | **Entity**, orchestrator: lifecycle state, refresh. |
| Configuration | **Entity** (value) with rules: defaults, per-project overrides, validation. |
| Project | Field group inside Configuration (name, repositories, overrides). |
| Item (PR, issue, run, ping) | **Entity** (value): kind, state, author, fingerprint; a ping's item carries its `Ping`. |
| Ping | **Entity** (value): id, title, the projects it's filed under, when it was sent and seen; optionally its repository, body, sender, action (`PingAction`: `url`, `app` or `herdr`) and its action's last failure. |
| Action port | **Port** (`ActionRunning`): opens GitHub pages and runs a ping's link or app action, reporting `done` or `failed(reason)`. |
| Herdr focus | **Entity** (`HerdrFocus`, over the `ShellRunning` port): runs `herdr` to focus a ping's tab or pane, reporting `done` or `failed(reason)`. Each `herdr` run races a timeout (`defaultTimeout`, 5 s; tests pass a short one): one that doesn't answer is cancelled (`ProcessShellRunner` stops the process) and fails with "Herdr didn't answer". |
| Ping store | **Entity** (store): the pings, one file each, written by the CLI and the app. |
| Ping command | **Entity** (pure, over the store): reads `shipyard ping`'s arguments, files and saves the ping. |
| Snapshot | **Entity** (value): all items of all projects from one refresh, plus per-source errors (a repository and a kind) and the rate limits seen. |
| Rate budget | **Entity**: owns the quota rule (share, back-off, pause). |
| Attention (seen records) | **Entity**: owns the "needs attention" rule and seen records. |
| Event | **Entity** (value), produced by diffing known → snapshot. |
| Notification rule | Field group inside Configuration; evaluated by `NotificationRules`. |
| App state | **Entity** (store): seen, known, notified, collapsed. |
| Account / token | **Entity**: `Auth` owns where the token comes from. |
| Menu model | **Entity** (value): what the panel draws. |
| Attention count, closed window, colour | Fields/derived values, not entities. |
| Author selector, author filter (`show`, `hide`) | **Values** with a rule: parse `me` / `others` / `bots` / `@login`, match an item's author |
| Repository selector | **Value**: `owner/name`, `owner/*`, `owned`, `organizations`, `collaborator`, `anywhere` |
| Repository resolver | **Entity**: owns the resolved lists and when they're stale |
| Review search | Part of the fetch: one search per refresh answering "which open PRs wait on me" |
| Listing | **Entity** (pure): owns "what a project has", the one filtering rule |
| Arrangement, group | **Entity** (pure) and its **value**: grouping, sorting and the cap; a group's key, title, rows, count, fold |
| Preset | **Value**: a name, a summary, its configuration text and what onboarding asks for |
| Group fold, Show more | Fields: `collapsedGroups` in app state; `expandedGroups` in `Shipyard`'s memory, cleared when the panel closes |

Relationships:

```text
Shipyard -> ConfigStore            reads current Configuration, is told when it changes
Shipyard -> Auth                   asks for a token; drives device flow
Shipyard -> RepositoryResolver     resolve(projects, force:) -> [ProjectName: ResolvedRepositories]
RepositoryResolver -> GitHubClient  repositories(of: group or owner), pages of 100
Shipyard -> GitHubClient           fetch(projects, resolved) -> Snapshot: repository batches + the review search (with rate limits)
Shipyard -> Listing                items(project, snapshot, viewer, now) -> the project's listed items
Shipyard -> RateBudget             record(limits) / record(error); nextDelay(configured, share) -> RefreshDelay
Shipyard -> AppStateStore          owns Attention + known items + notified + collapsed
Shipyard -> ConfigStatusStore      record(verdict) after every reload, for agents
Shipyard -> PingStore              all() at start and on every change the app's watcher sees; markSeen(ping) on a click that works or an ⌥-click; recordFailure(ping, reason) on one that doesn't; remove(id) on a dismiss; removeIfUnchanged(ping) for a seen ping past its seen-window
Shipyard -> ActionRunning          open(url) for GitHub pages; run(ping's action) -> done | failed(reason) on a ping's click; run(.app([herdr] terminal)) after a Herdr focus
Shipyard -> HerdrFocus             focus(tab or pane id) -> done | failed(reason) on a Herdr ping's click (#101)
HerdrFocus -> ShellRunning         herdr pane get <pane> (its tab_id), herdr tab focus <tab>
Shipyard -> ResolvedRepositoriesStore  record(each project's repositories) after every resolve, for the CLI
CLILink -> LinkFileSystem          fileExists(app's CLI), entry(~/.local/bin/shipyard) -> none | link(destination) | other; createDirectory, createSymbolicLink on Link
ShipyardCLI -> ResolvedRepositoriesStore  load() -> each project's repositories as last resolved
ShipyardCLI -> PingCommand         run(arguments, environment, configuration, resolved, store) -> output, exit status
PingCommand -> GitRemoteLookup     origin(in: working folder) (through CommandEnvironment) -> the remote's URL
PingCommand -> PingStore           save(ping) under the projects that watch its repository, or the one --project names
ShipyardCLI -> HerdrEvent          run(environment, configuration, resolved, store) for herdr-event -> output, exit status
HerdrEvent -> CommandEnvironment.run  herdr pane get <pane> (tab_id, cwd), herdr tab get <tab> (label)
HerdrEvent -> PingCommand          send(request herdr-<pane>, folder: the pane's cwd, unfiled) on blocked
HerdrEvent -> PingStore            remove(id: herdr-<pane>) when the agent goes on or its pane closes
Shipyard -> EventDetector          events(known, snapshot, projects) -> [Event]; pingEvents(listings, projects) -> a ping.sent per unseen listed ping
Shipyard -> NotificationRules      shouldNotify(event, project settings, viewer) -> Bool   (only for listed items)
Shipyard -> Notifier               post(notification); removeDelivered(id) for a ping that left (#102)
Notifier -> Shipyard               openNotification(itemURL) on a click
Shipyard -> MenuModel              build(listings, snapshot (errors, when fetched), config, appState, expandedGroups) -> what Panel draws
MenuModel -> Arrangement           groups(items, settings, folds, expanded, now) -> [RowGroup]
Panel    -> Shipyard               click(item), collapse(project), markAllSeen(), refresh()
Onboarding -> Shipyard            suggestedRepositories(), checkRepository(text), addProjects(projects)
Panel    -> Shipyard               switchToNextLayout() (the header's layout button)
Panel    -> Shipyard               toggleGroup(group), showMore(group), showLess(group), panelClosed()
Onboarding -> Shipyard            presets, choosePreset(preset, projects), beginDeviceFlow()
Shipyard -> ConfigStore            append(projects:), setLayout(layout) and writePreset(preset, projects) (the three writers), then follows the reload
Snapshot  has  [Project -> [Item]], reviewRequested: Set<ItemID>, the search's PRs, errors per source and per selector
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
| Which repositories a selector means; when to look again | `RepositoryResolver` |
| Whether a PR waits on the user (teams included) | the review search, read into `Item.reviewRequestedFromViewer` |
| Whether a project lists an item (kind shown, states, window, drafts, authors, review requested) | `Listing` |
| Which author a selector matches | `AuthorSelector` |
| How listed items are grouped, sorted and capped | `Arrangement` |
| Whether a group is folded / expanded past its cap | `AppState.collapsedGroups` / `Shipyard.expandedGroups` |
| Which preset text is written, and when writing it is safe | `Preset` + `ConfigStore.writePreset` |
| Which projects a ping is filed under; its id | `PingCommand` (against the configuration and `ResolvedRepositoriesStore`) |
| Which repository a git remote names | `GitRemote` |
| Whether a ping was seen | the ping itself, in `PingStore` (read by `Attention`) |
| What clicking a ping does; whether it worked | `PingAction` on the ping; `Shipyard.runAction(ofPing:)` over the action port (a Herdr action through `HerdrFocus`, then `[herdr] terminal` over the action port); the failure on the ping, in `PingStore` |
| Which `herdr` command focuses a tab or pane, and where `herdr` is | `HerdrFocus` |

---

## 3. Class design

### Shipyard (orchestrator) — `ShipyardCore/Shipyard.swift`

An `@MainActor @Observable` class; the panel observes it.

State:

```text
phase: signedOut | connecting(DeviceCode) | needsProjects | ready
signedOutReason: noToken | rejected(TokenSource) | userSignedOut(SignOutResult) | nil
                                   (why signedOut, for the connect screen; nil while signed in and while start() looks for a token)
config: Configuration              (from ConfigStore)
configError: ConfigError?
snapshot: Snapshot?                (last good)
fetchError: GitHubError?           (last refresh's failure, if any)
menu: MenuModel                    (what the panel draws; a failed refresh keeps its rows and sets fetchError; before any succeeded, it lists every project not loaded yet)
budget: RateBudget                 (limits, recent costs, pause; reset on sign-out)
appStateStore: AppStateStore       (seen, collapsed; loaded at start, kept on sign-out)
pingStore: PingStore               (the pings agents send; the CLI writes to it too)
repositoriesStore: ResolvedRepositoriesStore (repositories.json: each project's repositories after every resolve, for the CLI; write-only)
pings: [Ping]                      (the store as last read: at start and on reloadPings(); listed by every refresh and rebuild)
configStatusStore: ConfigStatusStore (config-status.json: the verdict after every reload, for agents; write-only)
gate: RefreshGate                  (one refresh at a time, queues one more)
actions: ActionRunning             (port; opens GitHub pages, runs pings' link and app actions)
herdr: HerdrFocus                  (focuses a Herdr ping's tab over ShellRunning; tests pass one over FakeHerdr)
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
| `start()` | create `config.toml` with its commented header when it's missing (`configStore.createIfMissing()`, on every start, not only the first; an existing file is never touched; a failed write is ignored and the missing file reads as the defaults); load config; `reloadPings()`, so pings sent while the app wasn't running list and notify at once, signed in or not, and those that left take their banners; `loginItem.setEnabled(launch-at-login)`; resolve token → phase; in `ready`, the first refresh. The connect screen's Connect with `gh` calls it too | no token → `signedOut` with `noToken`; a file broken at launch leaves the login item alone (the defaults would re-register one the user turned off) |
| `refreshNow()` | the header's Refresh button (⌘R): creates `config.toml` with its commented header when it's missing, as `start()` does, then `refresh()` | as `refresh()`; an existing file is never touched |
| `refresh()` | the refresh pipeline (§4), which resolves repository selectors first (forced after a configuration change and on ⌘R, else at most hourly); the timer, wake and a configuration change call it, and ⌘R through `refreshNow()` (opening the panel doesn't); arms the timer after with the budget's delay outside `ready` it only lists the pings again (below), so a seen ping past its window leaves, with its banner, even signed out; while one runs, returns at once and the running one goes again after (several calls make one more run); while the budget pauses, sends nothing, rebuilds the menu from the last snapshot (so a closed item past its window leaves) and re-arms the timer for the configured interval or the pause's end, whichever is sooner. Each call first reads the pings again (`listPings()`), removing the seen ones past their seen-window (#103), and removes the banners of those that left, before the phase check |
| `canRefreshNow` | false only while the budget pauses (⌘R and the Refresh button read it; `menu.canRefreshNow` says the same) | — |
| `reloadConfiguration()` | `configStore.reload()`; on a change, `loginItem.setEnabled(launch-at-login)` (so the switch applies live), phase follows `hasProjects`, the menu is rebuilt at once from the last snapshot (or none) under the new configuration, keeping `fetchError` (so an edit shows even while refreshing is paused or failing: a project added since shows "Not loaded yet", a removed one disappears); while refreshes may run, `refreshDelay` and `rateIndicator` are worked out again at once from the rate budget under the new `[rate-limit]`, before the refresh comes back; then it refreshes (or disarms the timer) | a rejected edit changes nothing but `configError`, which the panel's banner shows (set at `start()`, every reload and `addProjects`, in `publishConfigStatus()`, which also writes the verdict to `configStatusStore`, accepted, rejected or unchanged); `configWarnings`, set alongside it, lists the unknown settings the last clean read ignored for the panel's quiet banner, and is emptied when a read fails so only the error shows |
| `open(row)` / `markSeen(row)` | opens the URL through the `ActionRunning` port (or not, for ⌥-click), `attention.markSeen` with the row's item; saves app state and re-applies attention to the menu model. `open` returns a `Task` (discardable) for a ping's action still running, which tests await | a ping's row runs its action instead (`runAction(ofPing:)`, below); ⌥-click on a ping is `pingStore.markSeen(id)`, which clears a failure too, then the pings are listed again |
| `runAction(ofPing: id)` (private) | a ping's row or notification was clicked: reads the ping from the store (a replace may have changed its action); none: marks it seen; else `await actions.run(action)`: `done` marks it seen (clearing an earlier failure), `failed(reason)` records the reason with `pingStore.recordFailure` and lists the pings again, leaving it seen or unseen as it was (#100). Both write only to the sending that ran (`Ping.isSameSending`): a ping withdrawn, replaced or sent anew while its action ran is left as the CLI wrote it | a ping gone from the store does nothing |
| `reloadPings()` (async) | the app's watcher on the ping store calls it: reads the store and, when a ping arrived, changed or went, rebuilds the menu from the last snapshot (or none) with the pings listed; no GitHub request. A ping that went (withdrawn) has its notification removed first (#102). Then each unseen listed ping whose `ping.sent` isn't in `notified` is recorded there and posted when its first listing project's rules select it, as a refresh does (#99) | an unchanged store changes nothing; a file that doesn't read is skipped; a ping no project lists (`pings.show = false`) isn't recorded, so it notifies if a later edit lists it while it's still unseen |
| `openRepository(of: section)` | Return on a project's header (#45): opens the section's `repositoryURL`, the first repository the configuration lists for the project, on GitHub; marks nothing seen | a section without repositories opens nothing |
| `openProfile()` | a click on the header's account (#49): opens `viewer.profileURL` through `ActionRunning`; the app then closes the menu, as for a row | opens nothing while `viewer` is `nil` |
| `openNotification(itemURL)` | a notification was clicked: opens the URL and marks the item seen, the version in the last snapshot, else the one in `known` (a click that launched the app before its first refresh). A ping's URL (`shipyard://ping/<id>`, `Ping.id(from:)`) runs the ping's action as its row does (`runAction(ofPing:)`, #100); returns that `Task` (discardable) | an item neither lists is only opened; a ping gone from the store changes nothing |
| `markAllSeen(project?)` | marks every open row of that project (or of all projects) seen, pings in the ping store | rows hidden by the configuration are left alone |
| `dismiss(row)` | a ping row's ✕ or ⌫ (#103): `pingStore.remove(id)`, then the pings are listed again; the ping leaves every project it was filed under, seen or not, with its failure, and its notification leaves Notification Center (#102). Returns that removal's `Task` (discardable), which tests await | any other row changes nothing; a store that can't be written leaves the ping listed |
| `listPings()` (private) | reads the ping store; a seen ping whose seen-window has passed in every project it's filed under (a project no longer configured counts with `[defaults.pings]`'s window) is removed from the store (`removeIfUnchanged`: only as it was read, so one the CLI replaced or sent anew meanwhile is listed as it is now) and not listed; when what's left differs from `pings`, rebuilds the menu. `refresh()`, `reloadPings()`, a click, ⌥-click, Mark all seen and a dismiss all go through it (#103). Each time, `forgetLeftPings` drops from `notified` every ping's `ping.sent` record that names no stored ping, or another instance than the stored one (withdrawn and sent anew), and queues those notifications' ids; `refresh()`, `reloadPings()` and `dismiss` then call `notifier.removeDelivered` for each (`removeLeftBanners()`), before posting anything (#102) | a ping that can't be removed stays in the store, but `Listing` leaves it out anyway |
| `toggleCollapsed(project)` | flips app state; the section keeps its rows and its count | — |
| `beginDeviceFlow()` / `cancelDeviceFlow()` | drives `Auth`; the code shows as `connecting(code)`; the token is saved to the token store. Built and tested in the core since 0.0.1; since 0.0.2 the connect screen's Sign in with GitHub calls it (S1), offered while `canSignInWithGitHub` (the client ID isn't the placeholder; shipyard's own is compiled in since #23) | only in `signedOut`; expiry, denial or failure → `signedOut` with `signInError`, and it can begin again; with the placeholder client ID, `signInError` is `clientIDMissing` and GitHub is never asked |
| `openVerificationPage()` | the code screen's Copy code and open GitHub (the app copies the code first): opens the code's `verificationURL` (github.com/login/device) through `ActionRunning` | only while `connecting(code)`; otherwise does nothing |
| `suggestedRepositories()` | the picker's list: `GitHubClient.recentRepositories` through `request` | throws `GitHubError`; a 401 signs out; a spent limit is recorded in the budget (the same limit refreshes use) |
| `checkRepository(text) -> RepositoryCheck` | a typed `owner/name` (trimmed; a `github.com/owner/name` link, `.git` and a trailing slash are taken apart too) is looked up with `GitHubClient.repository`; `accepted(RepoSummary)` carries GitHub's spelling, which is what the picker writes | `rejected` with a reason and its `message`: `notASlug` (no request sent), `notFound` (404: missing, or the token can't see it), `forbidden` (403, e.g. SSO), `couldNotCheck` (network, rate limit, 401, which also signs out) |
| `addProjects([NewProject])` | `configStore.append(projects:)` then follows the reload like `reloadConfiguration()`: with projects, `needsProjects → ready` and the first refresh, no restart | throws `ConfigError` (empty or used name, no repositories, bad slug) before writing anything |
| `switchToNextLayout()` | the header's layout button: `configStore.setLayout(lastValid.menu.layout.next)` then follows the reload like `reloadConfiguration()`, so the menu switches as for a hand edit (rows kept, then a refresh) | a file that doesn't read, a `[menu]` the writer doesn't edit or a failed write changes nothing: `configError` says why (the banner) until the next reload |
| `toggleGroup(group)` | flips the group's fold in `collapsedGroups` (app state, saved) and re-applies the folds to the menu (`applyAttention`) without a refresh; the subheader keeps its count | only a subsection folds (`MenuModel.subsection(_:)`, in a project or the All tab); a group without a subheader, or one no longer listed, changes nothing |
| `showMore(group)` / `showLess(group)` | adds the group to, or removes it from, `expandedGroups` (memory) and re-caps the menu's groups in place (`MenuModel.applyExpansions`), without a refresh or a save; a refresh while the menu is open keeps the expansion | Show more on a group that isn't capped (or isn't listed) changes nothing |
| `panelClosed()` | empties `expandedGroups` and re-caps; the panel calls it from `onDisappear` when the menu window closes, so a reopened menu shows every cap again | — |
| `presets` / `choosePreset(preset, [NewProject])` | onboarding's first step: `configStore.writePreset(preset, projects)`, then follows the reload like `addProjects` | refused (a `ConfigError`, nothing written) when the file has live settings besides `version`; onboarding then shows the plain picker |
| `signOut()` | clears the token store (deletes the Keychain item) → `signedOut` with `userSignedOut(result)`; app state (seen, collapsed) is kept. The header's gear menu has Sign out | if the token came from `gh`, `ghStillSignedIn`: the connect screen says `gh` is still signed in and leads with Connect with `gh`, since the next `start()` picks `gh`'s token up again |
| `request(body)` (internal) | every GitHub API call runs through it | a 401 → `signedOut` with `rejected(source)`, dropping the stored token when it came from the token store |

### Configuration — `ShipyardCore/Config/Configuration.swift`

A `Codable` value decoded with TOMLDecoder. Every key is optional; missing keys take defaults, so an empty file is valid. Defaults shown, as the file a user would write:

```toml
#:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json
version = 1

refresh-interval-seconds = 120   # min 30; a floor, stretched by the rate budget if needed
launch-at-login = true
# hide-authors: removed in 0.0.2; read as a hide in each kind's authors, with a warning

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

[herdr]
# terminal: unset; an app name ("Ghostty") or bundle id, brought forward after a ping's --herdr focuses its tab

# What every project shows, unless the project overrides it.
[defaults.pull-requests]
show = true
states = ["open", "merged", "closed"]
closed-window = "7d"                     # a whole number and one unit: s, m, h or d; "0" hides closed ones
drafts = true
review-requested = false
authors = { show = [], hide = [] }       # [] in show: everyone; hide wins (F1)

[defaults.issues]
show = false
states = ["open", "closed"]
closed-window = "7d"
authors = { show = [], hide = [] }

[defaults.workflow-runs]
show = false
finished-window = "3h"
branches = "default-and-pull-requests"   # | "all"
states = ["in-progress", "failed", "succeeded"]
authors = { show = [], hide = [] }

[defaults.pings]
show = true                               # the pings agents send with `shipyard ping`; no states, authors, drafts or review-requested

[defaults]                                # how a project is arranged, and what groups bring in (per project too)
group-by = "kind"                         # "kind" | "repository" | "date" | "author" | "none"
# subsections: unset keeps each layout's own (dividers in the list, subheaders in tabs)
sort-by = "updated"                       # "updated" | "created" | "title"
show-first = 0                            # 0: show all
archived = false
forks = true

[[defaults.notifications]]
event = "pr.opened"
authors = []                              # author selectors; [] (or the old "any") is everyone

[[defaults.notifications]]
event = "ping.sent"                       # a new ping; a rule with authors never selects one
authors = []

# One [[projects]] block per project, shown in this order.
[[projects]]
name = "e-commerce"
repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]
issues = { show = true }          # overrides merge key by key onto defaults
notifications = [                 # replaces the default list for this project
  { event = "pr.opened", authors = ["others"] },
  { event = "run.failed" },
]

[[projects]]
name = "job-search"
repositories = ["yahyabedirhan/job-search"]

[[projects]]
name = "contributions"
repositories = ["owned", "my-org/*", "cobanov/ghbar"]   # groups, wildcards and single repositories
group-by = "repository"
subsections = true
pull-requests = { authors = { hide = ["me", "bots"] } }

[[projects]]
name = "review queue"
repositories = ["anywhere"]
pull-requests = { review-requested = true }
```

Keys are kebab-case (TOML's usual style, as in Cargo and Starship). Per-project overrides are written as inline tables so each `[[projects]]` block stays self-contained and can be appended on its own.

Events: `pr.opened pr.merged pr.closed pr.reopened pr.review_requested pr.checks_failed pr.commented issue.opened issue.closed issue.commented run.failed run.succeeded ping.sent` (0.0.5; in the default rules beside `pr.opened`). Author selectors: `me`, `others`, `bots` or `@login` (ADR 0002); the old notification strings `any | me | others | bots` still read, with a warning.

**Selectors** (`Config/Selectors.swift`): `AuthorSelector` and `RepositorySelector` parse a string or reject it with the hints in §1's error table; the key a selector sits under says which set it's from, so a bare word is a group, `@` marks a login and `/` a repository. `AuthorSelector.matches(author, authorKind, viewer)` is the only author match in the codebase; `AuthorFilter.includes` is `(show.isEmpty || show.contains(where: matches)) && !hide.contains(where: matches)`. `ProjectSettings.repositories` is `[RepositorySelector]`, and each kind's settings carry `states` (a set of `StateGroup`, the values that kind takes; `ItemState.group` maps a draft to `open` and a running run to `in-progress`) and `authors` (and pull requests `reviewRequested`); `ArrangementSettings` holds `groupBy`, `subsections` (optional: unset keeps the layout's own), `sortBy` and `showFirst`, and `archived` and `forks` sit beside them. All merge key by key in `settings(for:)`. The cross-key rule for `anywhere` (G2) is checked in the reader. The schema keeps `hide-authors` and the old notification strings, marked deprecated, so `taplo check` still passes on files the app accepts.

Operations:

| Operation | Returns / rejects |
|---|---|
| `static decode(Data) throws(ConfigError) -> Decoded` | the configuration plus warnings; rejects, each with a line and a message (every problem is listed, not only the first): invalid TOML, a value of the wrong type, an unknown choice (event, author filter, count style…) with the nearest valid one suggested, bad repo slug (`owner/name`), a project without a name or repositories, a repository listed twice in one project (ignoring case), duplicate project names, a window that isn't a whole number and one unit (`s`, `m`, `h`, `d`) with the nearest spelling suggested, an old `closed-window-days` or `finished-window-hours` beside its new key in one table (alone, the old key reads as days or hours, with a warning), interval < 30, share outside 1–50, a `version` other than 1 |
| `settings(for: Project) -> ProjectSettings` | defaults merged with the project's overrides (objects merge by field; `notifications` replaces) |
| `appendText(projects:) -> String` | the `[[projects]]` blocks the picker appends; the app never rewrites the file as a whole |
| `settingLayout(layout, in: text) throws(ConfigError) -> String` (`LayoutSetting.swift`) | the file's text with `[menu] layout` set and every other line kept: replaces an existing value (keeping its comment), adds the key under an existing `[menu]`, uncomments the header's `# [menu]` example when no live key follows it before the next table, else adds `[menu]` before the first table (or at the end); rejects a file that doesn't read (its own error), a `[menu]` in another form (inline table, dotted keys, `[menu.x]`) and any result that wouldn't read back as the same configuration with only the layout changed |
| `MenuLayout.next` | the layout after this one; the enum's case order is the cycle (list → tabs → list), so a new layout joins it by being added |

Unknown keys are ignored with a warning, so a newer file doesn't break an older app. TOMLDecoder parses the file but doesn't say where a value came from, so `ConfigurationReader` walks the parsed `TOMLTable` key by key and `TOMLSourceMap` (a light second pass over the text) finds the line of each key path for the messages. The published schema is `schema/config.schema.json`; tests check the example above and a file setting every key against it.

### ConfigStore — `ShipyardCore/Config/ConfigStore.swift`

State: `url` (`$XDG_CONFIG_HOME/shipyard/config.toml`, else `~/.config/shipyard/config.toml`), `lastValid: Configuration`, `error: ConfigError?`, `warnings: [ConfigIssue]`, `modified: Date?` (the file's modification time as the latest reload read it, taken before the bytes; `nil` with no file).
Operations: `reload() -> changed(Configuration) | unchanged | invalid(ConfigError)`, `createIfMissing()` (writes the commented header alone when there's no file; never touches one that exists. `Shipyard.start()` and `refreshNow()` (the Refresh button) call it, and so does the gear menu's "Open configuration file". The header, `Configuration.header`, shows the settings people reach for first commented out at their defaults: `[defaults.pull-requests] authors` (in place of `hide-authors` since 0.0.2), `[menu] layout`, `[menu-bar] count`, `[defaults] group-by`, `sort-by` and `show-first`, `[defaults.issues]` `show` and `states`, `[defaults.workflow-runs]` `show`, `[defaults.pings]` `show`, a `[[defaults.notifications]]` rule, a comment pointing Herdr users at `[herdr] terminal` and `[rate-limit] max-share-percent`, top-level keys above every table so any example, or all of them, can be uncommented), `append(projects:)` (appends `[[projects]]` blocks to the end, creating the file with a commented header and the `#:schema` line when missing; never rewrites, so comments survive; rejects bad slugs, a repository listed twice in one project and names already used before writing), `setLayout(layout)` (the layout button's writer: creates the file when missing, writes `Configuration.settingLayout` in place so a symlink stays one, and returns the reload; throws and writes nothing when the edit is refused or the file system fails), `writePreset(preset, projects)` (the third writer, below) and `acceptsPreset` (whether the latest reload found a file a preset may be written over). The core has no file watcher; the app's `ConfigWatcher` calls `Shipyard.reloadConfiguration()`, which reloads the store and follows the result.
The app's `ConfigWatcher` watches the **directory**, not just the file: editors and agents write by replacing the file (rename), which kills a watch on the old file descriptor. An in-place write (`>>`) doesn't touch the directory, so the file is watched too, and both watches are reopened after every change. A missing directory is watched through its nearest existing ancestor, so creating it is noticed. Changes are debounced 200 ms.

### ConfigStatusStore — `ShipyardCore/Config/ConfigStatus.swift`

Writes the latest `ConfigStatus` (`checked`, `config`, `configModified`, `error`, `warnings`) to `config-status.json` in a directory the app provides, the same one as `state.json` (tests pass a temporary one). Not beside `config.toml`: `ConfigWatcher` watches that directory, so a write there would reload again. Write-only and replaced atomically; the app never reads it back. Each problem is written with its `line`, `message` and `banner`, the banner's line from `PanelText.configIssue`. The format is in `docs/configuration.md`.

### Presets — `ShipyardCore/Config/Presets.swift` (+ `PresetSetting.swift`)

`Preset`: `name`, `title`, `summary`, `asks: .repositories | .ownedOrRepositories | .nothing`, and `text(projects: [NewProject]) -> String`, a whole commented configuration file (the `#:schema` line, a comment naming the preset, `version`, then its tables and projects) that decodes with no warnings and passes the schema. `Preset.all` lists the three in onboarding's order and `Preset.named(_:)` finds one by name. The skill's `skills/shipyard/presets.md` shows the same three files, with example repositories where onboarding's picks go; a test keeps them equal.

| Preset | Contents |
|---|---|
| `my-agents` | issues shown (`[defaults.issues] show = true`); `[defaults] group-by = "kind"`; each of `projects` as its own block (onboarding passes one per chosen repository); the default notification. The maintainer's setup. |
| `incoming-contributions` | in the defaults, so projects added later are the same: `authors = { hide = ["me", "bots"] }` for pull requests and issues, issues shown, `group-by = "repository"`, `subsections = true`, notifications `pr.opened` and `issue.opened` from `others`, and `ping.sent` (0.0.5). Then `projects` as given, or, when empty, a project "Incoming" (`Preset.incomingProjectName`) with `owned`; then a project "Review requests" with `anywhere`, `review-requested = true`, `issues = { show = false }` (`anywhere` lists no issues, and the defaults show them) and its own `notifications = [pr.review_requested, ping.sent]`, since a request, not a new PR, is its news. ghbar's view. |
| `review-queue` | one project, "Review queue", with `anywhere`, `review-requested = true`, `group-by = "repository"`, `subsections = true`; notifications `pr.review_requested` and `ping.sent`. Ignores `projects`. |

`ConfigStore.writePreset(preset, projects)` is the third writer (ADR 0001's amendment): it writes `preset.text(projects:)` in place when the file is missing or its only live key is `version`, and otherwise refuses with a `ConfigError` so onboarding falls back to the picker. "Only live key" is `Configuration.acceptsPreset(text)`: the file reads, and `TOMLSourceMap` finds no entry but `version` (comments don't count; any table does). Each reload records it as `acceptsPreset`, which `Shipyard.presets` follows; `writePreset` checks the file again before writing, and also refuses invalid picked projects and a preset that wouldn't read with them.
### Auth — `ShipyardCore/GitHub/Auth/` (+ `ShipyardApp/Keychain.swift`, #22)

**0.0.1 connected through `gh` only; 0.0.2 adds the device flow (S1).** In 0.0.1 the app read `gh auth token` silently, never started the device flow, and kept tokens in a session-only store. 0.0.2 compiles in shipyard's OAuth App client ID (`OAuthApp.clientID`, one line, registered under the maintainer's account in #23), makes `Keychain` the app's token store, and puts **Sign in with GitHub** on the connect screen; the `gh` token stays the silent path for anyone who has it. A build whose client ID is the placeholder (a fork's, before it sets its own) shows Sign in with GitHub disabled, with why, and connects through `gh` only.

Kept from ghbar almost as is, because it worked well:
- `TokenProvider.current()`: Keychain first (the user signed in explicitly), then `gh auth token` found at known paths (`/opt/homebrew/bin/gh`, `/usr/local/bin/gh`, then `PATH`), since an `.app` starts with an almost empty `PATH`. Spawning `gh` sits behind the `GhTokenLookup` protocol (`GhCLI` runs it with `Process`), so tests use a fake lookup.
- `DeviceFlow`: request code → show code and open github.com/login/device → poll every `interval` s (+5 s per `slow_down`) → store in Keychain. Stops with `.expired` after the code's 15 minutes. Needs a GitHub OAuth App client ID (scopes `repo`, `read:org`): the one build-time constant `OAuthApp.clientID`, shipyard's own OAuth App (the flow refuses to start with `OAuthApp.placeholderClientID`, which tests pass to cover a build without one). Waiting and the clock are injected, so tests poll without real time passing.
- `Keychain` (app target): the `TokenStore` port, get/set/delete one generic password in the login Keychain (service `com.yahyabedirhan.shipyard`, account `github-token`). Tests use an in-memory store; the app target has no tests, and agents never touch the real Keychain.

### GitHubClient — `ShipyardCore/GitHub/GitHubClient.swift`

State: token, `HTTPTransport` (`URLSessionTransport` in the app; tests stub responses at this layer). Operations:

| Operation | Returns / rejects |
|---|---|
| `viewer() -> Viewer` (login, id, name, `avatarURL` from `avatar_url`, `profileURL` from `html_url`, else `https://github.com/<login>`), from `GET /user` at sign-in only | 401 → `.unauthorized`; a missing or unreadable name, avatar or profile link is left out (`nil`, or the constructed profile), never failing the sign-in |
| `fetch(projects: [ProjectSettings], resolved: [ProjectName: ResolvedRepositories], at:) -> Snapshot` | each project watches what `resolved` has for it (else only the `owner/name` it names); GraphQL for PRs and issues (every repository as an alias, in batches of 25 per request, one request after another; a failed batch fails the fetch), plus one REST call per repository for runs when runs are on; partial errors land per source (repository + kind) in the snapshot: a repository GraphQL can't resolve fails every kind each project shows from it. The GraphQL query also asks for `rateLimit { limit remaining resetAt cost }`; REST reads the `x-ratelimit-*` headers and sends `If-None-Match` so unchanged runs come back as 304, which GitHub doesn't count against the limit. The snapshot's `rateLimits.rest` is the last runs response's headers with the counted (non-304) requests as `cost`. A runs request that fails with another HTTP status (or an unreadable body) becomes an error for that repository's runs source only (an error row in the projects that show runs) while its pull requests and issues still list; a spent limit, a 401 or a network failure fails the whole fetch, as for GraphQL |
| rate-limit errors | `.rateLimited(resetAt, api)` from `x-ratelimit-reset` (403/429 with `x-ratelimit-remaining: 0`, or GraphQL's 200 with a `RATE_LIMITED` error or with `x-ratelimit-remaining: 0` and an error); `api` comes from `x-ratelimit-resource` (`graphql`, else REST), or the URL without it. `.secondaryLimit(retryAfter)` from `retry-after` (it wins over the reset time), else 60 s for a bare 429 or a 403 whose message says "secondary rate limit"; any other 403 is `.http(403)`. Every response's `x-ratelimit-*` headers are read into a `RateLimit`; the snapshot carries GraphQL's (headers first, `cost` from the body). GraphQL's exhausted case is a 200 with an error, so the check reads headers, not only the status code. REST calls for runs go one after another, never in parallel (GitHub's guidance against secondary limits) |
| `recentRepositories(at:) -> [RepoSummary]` | for the picker, one GraphQL request (`GitHub/Repositories.swift`): `viewer.repositories` (owner and collaborator, `isArchived: false`) and `viewer.repositoriesContributedTo`, each `first: 25` ordered by `PUSHED_AT`; merged, each repository once (case-insensitive), archived ones dropped (the contributed list has no `isArchived` argument), newest push first, never-pushed last. Rate-limit errors as for `fetch` |
| `repository(slug) -> RepoSummary` | REST `GET /repos/{owner}/{repo}`, for the picker's check of a typed name; `full_name` is GitHub's spelling; 404 → `.http(404)` |

The query text lives next to its parser in `GitHub/ProjectQuery.swift` (build + parse, one owner). Each repository is asked for once (aliases `repo0`, `repo1`… with `$owner<i>`/`$name<i>` variables, numbered within each batch of `ProjectQuery.repositoriesPerRequest` = 25), even when several projects list it, and every batch's query also asks for `viewer { login }` (to tell `me` and the viewer's review requests apart) and `rateLimit`. An alias that comes back `null` with a `NOT_FOUND` (missing, or no access) or `FORBIDDEN` error becomes that repository's error in the snapshot; the others still parse. Per repository alias it asks for: open PRs (first 50), PRs closed or merged ordered by `UPDATED_AT` (first 20, filtered by `closedAt` locally), and per PR `isDraft`, `author { login, __typename, avatarUrl }`, for the row's hover card `baseRefName`, `additions`, `deletions`, `changedFiles` and `reviewDecision` (plain fields, which add nothing to the query's cost), `updatedAt`, `closedAt`, `mergedAt`, comment + review counts, and the head commit's `statusCheckRollup.state` (since 0.0.2 not `reviewRequests`: the review search, below, says which PRs wait on the viewer). Issues are asked for the same way (`openIssues`: open, first 50; `closedIssues`: closed, first 20, both by `UPDATED_AT`; per issue `state`, `author { login, __typename }`, `createdAt`, `updatedAt`, `closedAt` and the comment count, with no nested lists), and only in the aliases of repositories that some project's effective settings show issues for, so turning issues off keeps them out of the query's cost; the `IssueFields` fragment is sent only when one does. A repository shared by two projects is asked for once with the union of what they show, and each project keeps only the kinds it shows.
Runs come from REST, because GraphQL doesn't list workflow runs (`GitHub/WorkflowRuns.swift` builds the request, parses it and holds the branch filter). Each repository that some project shows runs for (and that GraphQL didn't report missing) gets one `GET /repos/{o}/{r}/actions/runs?created=>=<since>&exclude_pull_requests=true&per_page=100` per refresh, one after another. `since` is an hour before the widest `finished-window` of those projects, rounded down to the hour, so the URL stays the same for an hour (and its `ETag` can match) and a run of up to an hour that finished inside the window is still in the answer; a run that started earlier than that isn't listed, even while it runs. The client keeps each repository's last URL, `ETag` and parsed runs in memory (`WorkflowRunCache`, for as long as the `GitHubClient` of one sign-in lives; a relaunch asks afresh once): the next request to the same URL sends `If-None-Match`, and a `304` reuses those runs. A run's state: anything not `completed` (and `action_required`) is `running`; `success` and `neutral` are `succeeded`; `failure`, `timed_out` and `startup_failure` are `failed`; `cancelled`, `skipped` and `stale` runs aren't listed. The runs are parsed once per repository and filtered per project: `branches = "all"` keeps them all; `"default-and-pull-requests"` keeps those whose `head_branch` is the repository's default branch or an open pull request's head. The GraphQL query supplies both for those repositories (`defaultBranchRef { name }`, `headRefName` in `PullRequestFields`, and, where no project shows the repository's pull requests, `openPullRequestHeads: pullRequests(states: OPEN, first: 50) { nodes { headRefName } }`), so no extra REST calls. The window itself is the menu model's.

**Since 0.0.2**, `fetch(projects, resolved:)` sends the repository aliases in **batches of 25** per GraphQL request, one after another, so one request stays well inside GitHub's node limit (500,000) and its 10-second timeout however many repositories a group brings in (see `docs/references/github-rate-limits.md`); the cost is their sum, which `RateBudget` measures as today, and the limit is the last batch's headers. A failed batch (a spent limit, a 401, a network failure) fails the whole refresh as a single request's failure did, and a repository missing from one batch is still that repository's error. The first batch also asks for the **review search**, `search(type: ISSUE, query: "is:pr is:open archived:false review-requested:@me", first: 100)`, with the same pull request fields the repositories use. It yields `Snapshot.reviewRequested: Set<ItemID>` and the PRs themselves, which `anywhere` projects list. `review-requested:@me` includes requests to the user's teams, which is why the search replaces reading each PR's `reviewRequests`, and that part of the per-repository query goes; `Item.reviewRequestedFromViewer` is filled from the set, so attention and `pr.review_requested` gain team requests with no change of their own. The search is asked for only when some project shows pull requests. It can fail on its own (`reviewSearch: null` with an error on that path) while the repositories answer: the refresh still succeeds, the client (which keeps the last search's PRs for as long as it lives, like the runs' ETags) fills the set and the flags from the last search that answered, so a blip neither withdraws requests nor makes them new again, and `Snapshot.reviewSearchError` gives `MenuModel` an error row ("review requests: <GitHub's message>") in each project with `review-requested = true`, which every `anywhere` project is. A project using `anywhere` (G2, #61) gets the search's PRs among its items in the snapshot, after its own repositories' and each once, so the listing, the counts and the event detector treat them like any fetched PR; `issueCount` (every match, not just the page) becomes `Snapshot.reviewSearchTotal`, and when it's more than the page holds the section carries a note, "Only the first 100 of 134 review requests are listed" (`MenuSection.notes`, drawn after the error rows, in the list and in the tabs). Because the search sees only open PRs, `KnownItems.updated` keeps the review request a closed PR had, so reopening it is `pr.reopened` without a second `pr.review_requested`. The search's facts are in `docs/references/github-search.md`.

### RepositoryResolver — `ShipyardCore/GitHub/RepositoryResolver.swift` (0.0.2)

A `@MainActor` class `Shipyard` owns. State: one entry per `RepositoryLookup` (a group, or an owner's login lowercased, so `o/*` in two projects is one lookup): the last list GitHub gave (`[RepoSummary]`, archived ones and forks included and marked), when it arrived, and why the latest lookup failed (or that the owner can't be seen), in memory only. `ResolvedRepositories` is a project's result: `repositories: [String]` (`owner/name`, each once) and `errors: [RepositoryError]` (one per selector, named after it).

| Operation | Does | Rejects / edge |
|---|---|---|
| `resolve(projects, force: Bool, at: now, lookup:) async throws -> [ProjectName: ResolvedRepositories]` | looks up each group or `owner/*` the projects use, once however many use it, when it wasn't answered within `interval` (an hour), when its last lookup failed, or always when `force`; then per project, in selector order: an `owner/name` as written, a looked-up list without archived repositories unless `archived` and without forks unless `forks`; each repository once, ignoring case (the first spelling wins). `lookup` is `GitHubClient.repositories(of:at:)` through `Shipyard.request`, so a 401 signs out | a failed lookup (network, rate limit, an unreadable answer) keeps the last list silently, and is tried again at the next refresh; with no list to keep, the selector gets an error row ("owned: couldn't list its repositories (…)"). An owner GitHub answers `null` for is an answer, kept for the hour: an error row ("ghost-org/*: not found, or no access") and no repositories. Only `.unauthorized` and cancellation are thrown. Lookups no project uses any more are dropped |
| `reset()` | forgets every list, on sign-out (another account reaches other repositories) | — |

`Shipyard` forces the next resolve at launch, after a valid configuration change, on ⌘R (`refreshNow()`) and after signing in again; the refresh timer's runs look up only what's stale. It passes the configured projects and the resolution to `fetch(projects:resolved:at:)`, which watches `ProjectSettings.resolved(by:)` (each project's selectors replaced by what they resolved to, as `owner/name`), records it in `Snapshot.repositories` and the error rows in `Snapshot.selectorErrors`; the notification step's known sources come from the same resolved settings, so a repository a group brings in later is a first sight: its items are recorded, not notified.

The calls sit in `GitHub/Repositories.swift` (`RepositoryListQuery`, `GitHubClient.repositories(of:at:) -> [RepoSummary]?`): `owned`, `organizations` and `collaborator` are `viewer.repositories(affiliations: [OWNER | ORGANIZATION_MEMBER | COLLABORATOR], ownerAffiliations: the same)`; `owner/*` is `repositoryOwner(login).repositories(ownerAffiliations: [OWNER])`, `nil` when the owner is `null`; both in pages of 100 by name, with `isArchived` and `isFork` on each node. The GitHub facts behind them are in `docs/references/github-repositories.md`. `anywhere` (G2) resolves to nothing: its PRs come from the review search.
### Item and Snapshot — `ShipyardCore/Items/`

```text
Item
  id: String                  (URL; unique across PRs, issues, runs)
  kind: pullRequest | issue | workflowRun | ping
  repository: String          ("owner/name")
  number/title/url/author/authorKind(me|other|bot)   (a Bot's login keeps GitHub's `[bot]` suffix; a deleted account is `ghost`; a run: its run number, the workflow's name, the actor)
  state: open | draft | merged | closed | running | succeeded | failed   (issues: open | closed; runs: queued counts as running)
  checks: none | pending | passed | failed      (PRs; a run's own result: running pending, succeeded passed, failed failed)
  branch: String?             (runs: the head branch)
  reviewRequestedFromViewer: Bool
  createdAt, updatedAt, closedAt?   (runs: started, last updated, finished)
  activity: Int               (comments + reviews; an issue's comments)
  avatarURL: URL?             (the author's; a run: the actor's)
  details: ItemDetails        (only the row's hover card shows these: a PR's head and base branch, additions, deletions,
                               changed files, reviewDecision, comments and reviews; an issue's comments; a run's
                               display_title, event and run_attempt; not in the fingerprint)
  ping: Ping?                 (0.0.5, kind ping only: the ping it lists, whose `seen` attention reads. A ping's item is open,
                               has no number or GitHub author (its sender stays on the ping, so author filters and rules
                               never see it), its repository only when filed by one, is aged from when it was sent, and is
                               known by shipyard://ping/<id>, which no GitHub item can be. `MenuRow.pingIcon`, `sender` and
                               `actionError` read it for the row)
  fingerprint: String          (state|updatedAt|checks|reviewRequested|activity) — any change = "changed"

Snapshot
  fetchedAt
  items: [ProjectName: [Item]]
  errors: [ItemSource: RepositoryError]      (per repository + kind; notFound | forbidden | other, GitHub's message)
  rateLimits: { graphql: RateLimit?, rest: RateLimit? }   (limit, remaining, used, resetAt, cost of this refresh: GraphQL's `rateLimit.cost`; REST's counted (non-304) requests)
  viewerLogin
  reviewRequested: Set<ItemID>               (0.0.2: open PRs waiting on the user, teams included, from the review search)
  searchPullRequests: [Item]                 (0.0.2: the search's PRs, in any repository, for `anywhere`; at most one page of 100)
  reviewSearchTotal: Int                     (0.0.2: how many PRs the search matched in all, its `issueCount`)
  reviewSearchError: RepositoryError?        (0.0.2: the search failed; the two above are then the last search's)
  repositories: [ProjectName: [String]]      (0.0.2: what each project watched, its groups and wildcards resolved; the menu's error rows and repository names read it)
  selectorErrors: [ProjectName: [RepositoryError]]   (0.0.2: the selectors that couldn't be resolved, each an error row named after the selector)
```

### Listing — `ShipyardCore/Items/Listing.swift` (0.0.2)

Pure, and the only place that decides what a project has (ADR 0003):

| Operation | Returns |
|---|---|
| `items(for: ProjectSettings, in: Snapshot, viewer, now) -> [Item]` | the snapshot's items for the project (from its resolved repositories, and for `anywhere` the search's PRs, which the fetch puts among them) that pass every check, combined with AND: kind shown, `states`, the window, `drafts`, `authors`, `review-requested` |
| `listings(for: [ProjectSettings], in: Snapshot?, pings: [Ping], now) -> [ProjectName: [Item]]` | every project's listing, the viewer being the snapshot's `viewerLogin`: its fetched items, then the pings filed under it, through the same checks (a ping passes on `pings.show` alone). A project with neither (added since the snapshot) has none; without a snapshot a project lists its pings alone. Whether a section is loaded is the snapshot's to say, not the listing's |

`MenuModel`, `Attention.counts` and the notification filter all take a listing, so they can't disagree; the two `hide-authors` checks (in `MenuModel` and in `Shipyard`'s notification step) go.
### Attention — `ShipyardCore/Items/Attention.swift`

Owns the rule, so the rule sits with the data it reads (seen records). It's keyed on the generic `Item`, so issues and runs reuse it.
A ping (0.0.5) is the exception: it needs attention (`unseen`) until it's seen, whatever `[attention]` says, and whether it was seen is the `seen` time on the ping, in the ping store, so a seen-window can count from it later without GitHub data; `counts` has a `pings` kind.
State: `seen: [ItemID: SeenRecord]`, where `SeenRecord` = the fingerprint seen and `present`, the last time a refresh still listed the item (bumped at most once a day, so the file isn't rewritten every refresh).

| Operation | Returns |
|---|---|
| `reasons(item, toggles) -> [Reason]` | why it needs attention, in order: `unseen` or `changed`, then `reviewRequested`, `checksFailed`; empty when it doesn't (the rule below); the row carries them as `attentionReasons` for its hover card |
| `needsAttention(item, toggles) -> Bool` | `reasons` isn't empty: false if closed, merged, running or succeeded (a failed run can, its `checks` failed so `checks-failed` covers it); true if unseen, or `seen[id] != fingerprint`, or review requested, or checks failed, each gated by its toggle, and **all cleared by a click until the fingerprint changes** |
| `markSeen(item, at:)` | stores the current fingerprint |
| `counts(items, toggles) -> AttentionCounts` | per kind (`pullRequests`, `issues`, `workflowRuns`) and `total`; an item listed in two projects counts once |
| `prune(present: items, at:) -> Bool` | bumps `present` for listed items, drops records for items gone for 30 days; says whether to save |

### EventDetector — `ShipyardCore/Items/EventDetector.swift`

Pure: `events(known: KnownItems, snapshot, projects: [ProjectSettings]) -> [Event]`, per project in configuration order.
`KnownItems` = `items: [ItemID: KnownItem]` (the last state, checks, review request, activity, repository and fingerprint of each item, and `present`: when a refresh last listed it, bumped at most once a day) and `sources: [ProjectName: Set<ItemSource>]`, where an `ItemSource` is one repository and one item kind. Items from a source the project hasn't been fetched from before produce no events: the first refresh ever, a project or repository just added, a kind just shown. `known.updated(with: snapshot, projects:)` is what the next refresh compares with: the snapshot's items and fetched sources; a source that failed keeps its known-ness (so its return isn't a burst), and only that source: a runs 403 doesn't hold back the repository's pull requests; an item missing from the snapshot (out of the most recent 50, or its repository failed) is kept for 30 days after it was last listed, and while its repository fails, so when it comes back it's compared with its last version (no `opened`; `merged` if it merged meanwhile) rather than announced as new; a project, repository or kind no longer fetched is forgotten (adding it back is a first sight again).
The detector finds generic `ItemChange`s and `EventKind.of(change, for: item.kind)` names them, so issues and runs only add names (and runs their own changes): absent → open (drafts too) = opened (absent → closed is nothing: it may be an old item coming back into the closed list); open → merged = merged; open → closed = closed; closed → open = reopened; review requested newly true (open) = review_requested; checks newly failed (open) = checks_failed; activity went up = commented. For issues only opened, closed and commented have names (`issue.*`); an issue reopened is no event, and its next close is a new occurrence of `issue.closed`. Runs have their own changes: failed (found failed, unknown or not failed before) = `run.failed`, succeeded likewise = `run.succeeded`; a run found already finished counts, since only recent runs are asked for, so it finished between two refreshes. Both recur (a re-run that fails again is a new occurrence). Runs of one repository are a source of their own, so turning runs on is a silent first sight. Pull requests and issues of one repository are separate sources, so showing issues in a project that already has its pull requests known is a silent first sight. **Since 0.0.2**, a project using `anywhere` has one more source, `ItemSource.anywhere` (the review search), for its PRs from repositories it doesn't watch: its first answer is a silent first sight (and a failed search's stand-in isn't one); after that a PR the search finds for the first time is `pr.opened` and `pr.review_requested` both, since it's a new item and a request that just arrived, whatever rules pick. While a project uses `anywhere`, `KnownItems.updated` keeps known items of any repository for their retention, so a PR that leaves the search and comes back isn't new again. An `Event` has the kind, project, item and an occurrence: empty for events that happen once in an item's life (opened, merged), the item's fingerprint for ones that recur; `id` = kind + item URL (+ occurrence), the same in every project.
**Since 0.0.5**, `pingEvents(listings:projects:)` makes a `ping.sent` (no occurrence) for every unseen ping each project lists. Pings aren't fetched, so they aren't compared with `KnownItems`: a ping is new until its `ping.sent` is in `NotifiedEvents`, keyed by the ping's URL (its id), with the ping's `instance` as its occurrence: the CLI makes a new instance each time an id is sent as a new ping and a replace keeps it, so a replace (same id, new content) is never new again, while a ping withdrawn and sent anew under its id is, however soon and even while the app wasn't running (a ping written before `instance` has none, an empty occurrence). A ping that leaves the store, or comes back as another instance, loses its record (`Shipyard.forgetLeftPings`, #102). There's no first-sight silence for pings: one sent while the app wasn't running notifies at the first refresh.

### NotificationRules — `ShipyardCore/Items/NotificationRules.swift`

Pure: `shouldNotify(event, settings: ProjectSettings, viewer) -> Bool`, asked only for items the project lists (since 0.0.2; before, it took `hiddenAuthors`) — the project's rule list contains the event, and the rule's author selectors match the item's author (`me` = viewer, `bots` = `Bot` type or `[bot]` login, `others` = neither, or an `@login`). `notification(for: event)` makes the `PostedNotification`: event id, project, title text ("New PR #57", "Run #41 failed"), the item's title (for a run, "CI · main": workflow and branch) and URL. A `ping.sent`'s title text is the ping's title and its body `Ping.notificationBody` (the body, then "from <sender>"); `NotificationRule.covers` never lets a rule with `authors` cover a ping.
`NotifiedEvents` (app state, apart from the seen records) holds every event handled, notified or passed over, per item: `contains(event)`, `insert(event, at:)`, and `prune(present:at:)`, which keeps an item's record while it's known and 30 days after, so an item that leaves the list and comes back isn't announced again. A ping's record counts as present while the ping is in the store, and `remove(itemID:where:)` drops the events it picks (a ping's that left, or its old instance's), returning their ids, which are the notifications' ids (#102).

### AppStateStore — `ShipyardCore/State/AppStateStore.swift`

One JSON file, `state.json`, in a directory the app provides (`~/Library/Application Support/Shipyard/`; tests pass a temporary one). App-owned, never hand-edited, so Foundation's JSON is enough. `AppState` holds `attention` (seen records), `collapsed: Set<ProjectName>`, `known: KnownItems` (written as `known` and `knownProjects`) and `notified: NotifiedEvents`.

```json
{
  "version": 1,
  "seen": { "https://github.com/o/r/pull/57": { "fingerprint": "open|…", "present": "2026-09-25T12:00:00Z" } },
  "collapsed": ["job-search"],
  "collapsedGroups": [{ "project": "shop", "group": "kind:issue" }],
  "known": { "https://github.com/o/r/pull/57": { "repository": "o/r", "state": "open", "checks": "pending", "reviewRequested": false, "activity": 0, "fingerprint": "open|…", "present": "2026-09-25T12:00:00Z" } },
  "knownProjects": { "e-commerce": [{ "repository": "o/r", "kind": "pullRequest" }] },
  "notified": { "https://github.com/o/r/pull/57": { "events": ["pr.opened"], "present": "2026-09-25T12:00:00Z" } }
}
```

Every field is optional when read and unknown fields are ignored, so adding a field doesn't bump `version`: an older file loads with the new field empty (a file without `knownProjects` makes the first refresh after the upgrade silent), and a file a newer build wrote at the same `version` still loads in an older build. `known`, `knownProjects` and `notified` that can't be read are dropped rather than failing the file (the next refresh is then silent, the safe way to fail), and an entry inside them this build can't read is skipped. A known item without `present` (written before it was kept) loads as present long ago: kept while listed, dropped the first time it isn't. `version` changes only for a change an older reader would misunderstand, with a migration in `AppState.init(from:)`; a file whose `version` is newer than this build's `currentVersion` isn't read (it would be misread) but set aside like an unreadable one, and shipyard starts as on a first run.
Since 0.0.2, `AppState` also holds `collapsedGroups: Set<GroupID>` (a project and a group key), optional when read, so no version bump. A fold is written as its project (empty for the All tab) and its key as text (`kind:issue`, `repository:owner/name`, `date:thisWeek`, `author:login`, `ungrouped`); a fold this build can't read is skipped, and a `collapsedGroups` that can't be read is dropped. After each successful refresh `MenuModel.foldsToKeep` prunes it: a fold is kept while its group is listed (under a subheader or a divider, so turning `subsections` off and on again keeps it), or while its project isn't loaded or has an error row (its groups may come back); a removed project's folds, and a group gone from its project or from the All tab, are dropped.
Operations: `load(at:) -> missing | loaded | setAside(URL)` at `Shipyard.start()`; `update { state in … }` changes the state and saves it (atomically, no debounce: the file is small and changes on clicks, on refreshes that found a change, and about once a day from pruning) when it changed. A file that isn't readable app state (or has a newer `version`) is renamed to `state-corrupt-<yyyyMMdd-HHmmss>.json` and shipyard starts as on a first run, with no notifications on the first refresh (bootstrap).

### Notifier — `ShipyardApp/Notifier.swift` (the `Notifying` port; tests use a recording one)

Wraps `UNUserNotificationCenter`: asks permission on the first notification (not at launch), posts a `PostedNotification` as title "e-commerce · New PR #107" (`title`: project · headline) and body "Fix checkout totals" (the item's title), with the event id as the request identifier and the item URL in its user info. Clicking the notification calls `Shipyard.openNotification(itemURL)`, which opens the item and marks it seen. `post` queues the notification and returns at once, so a refresh never waits on the permission prompt; deliveries run in order, and the first one asks. It is `@Observable`: `permission` (unknown, not asked, allowed, denied) is read without asking at launch and whenever the panel opens, and while it's denied the panel shows a "notifications are off" banner with a button to shipyard's page in System Settings. Notifications are shown even while the panel is open (the app is then frontmost), grouped per project. Outside a `.app` bundle (`make run`) there is no notification center, and it only logs. **Since 0.0.5**, `removeDelivered(id:)` takes a notification out of Notification Center by its request identifier (the event id), for a ping that left (#102); it's queued behind the deliveries, so a notification still waiting to be posted is posted, then removed.

### LaunchAtLogin — `ShipyardApp/LaunchAtLogin.swift` (the `LoginItem` port; tests use a recording one)

Wraps `SMAppService.mainApp`: `setEnabled(true)` registers the running `.app` (normally `/Applications/Shipyard.app`) as a login item, `setEnabled(false)` removes it, on a serial queue off the main thread. It compares with the service's status first, so a repeat changes nothing, and an item the user switched off in System Settings > General > Login Items (`requiresApproval`) isn't registered again at each launch; setting `launch-at-login = false` removes it either way. Failures are logged. Outside a `.app` bundle (`make run`) it only logs.

### MenuModel — `ShipyardCore/Menu/MenuModel.swift`

Pure: `build(listings:snapshot:configuration:state:expanded:now:) -> MenuModel`: sections per project in configuration order, built from the projects' listings, the snapshot giving only the error rows and when it was fetched (without a snapshot, before any refresh succeeded, every project still gets a section, with no rows and `isLoaded` false, which the panel shows as "Not loaded yet" (`PanelText.emptySection`); so does a project the snapshot has no entry for, one added to the configuration since it was fetched), the items `Listing` lists (kind shown, states, the kind's own closed window counted back from `now` with 0 hiding closed items (runs: finished ones within `finished-window-hours`, running ones always), drafts, `authors`), each section's `groups: [RowGroup]` as `Arrangement` groups, sorts and caps them (the defaults, `group-by = "kind"` and `sort-by = "updated"`, give the old order: pull requests, then issues, then runs, open or running first; `expanded` holds the groups Show more revealed past their cap), each row with its number, title (a run: its workflow's name), author, URL, semantic state (open, draft, merged, closed, running, succeeded, failed; the app's `Palette` colours it by kind: an issue's closed is purple, a pull request's red), `branch` (runs only), check dot (open and draft PRs only), `since` for its age (opened or started, or closed or finished), its `needsAttention` flag and the `item` it shows (marking it seen records that version); an error row per repository with a failed source of a kind the project shows (one row per repository, so a runs failure isn't shown where runs are off); each section's `showsRepository` (true only when its project has more than one repository, so a row's second line names the repository only there); `lastUpdated` and `fetchError` for the banner, and `bannerFetchError`, which leaves out a rate-limit error while refreshing is paused (the pause banner already says why); `refreshDelay` (configured, stretched, backed off or paused, with the API and why), `rateIndicator` and `canRefreshNow`, which `Shipyard` fills in from the rate budget; plus, from attention, each section's `attentionCount` and `isCollapsed` (a collapsed section keeps its rows and still counts), the model's `attention: AttentionCounts` and the `layout` (`list` or `tabs`, per `[menu] layout`, rebuilt with the model so a configuration change switches the open panel), the `menuBarLabel` (`total(n)`, `perKind(counts)` or `hidden`, per `[menu-bar] count`, with its text, e.g. "3" or "2 PRs · 1 run", `nil` at 0; `Shipyard` hides it outside `ready`, so a menu without projects or signed out shows no count). The menu bar count, each header's count and the tabs' counts are of listed items only. `applyAttention(_:configuration:)` recomputes just those, and each subsection's fold from `collapsedGroups`, so a click, a collapse or a fold updates the model without a refresh; `applyExpansions(_:configuration:)` re-caps the groups for Show more and Show less, and `foldsToKeep(_:)` drops the folds of groups or projects that are gone. All of R3–R6's display rules live here, where tests can reach them without SwiftUI.

### Arrangement — `ShipyardCore/Menu/Arrangement.swift` (0.0.2)

Pure: `groups(items, project, settings: ArrangementSettings, layout, folded: Set<GroupID>, expanded: Set<GroupID>, now, calendar) -> [RowGroup]` groups by `group-by` (one untitled group for `none`, with no header), sorts each group (open first, then `sort-by`, then the order given), marks folds, and caps unexpanded groups at `show-first` (`RowGroup.capped(at:expanded:)`, which `MenuModel.applyExpansions` also calls to re-cap in place). `RowGroup`: `id` (project + key), `title` ("Pull requests", "owner/name", "Today", "@login"), `rows` (the ones drawn), `hiddenRows` (the ones past the cap, still the group's: `allRows` is both, and `MenuSection.rows`, which the counts, Mark all seen and the All tab read, is every group's `allRows`), `attentionCount` (of every row, capped or not), `showsHeader` (`subsections`, or the layout's own when unset: dividers in the list, subheaders in a tab), `isFolded`, `hiddenCount`, `isExpanded` (past a cap it has), `hasShowMore` (a cap to toggle: drawn as a `ShowMoreRow` after the rows unless folded). Group order: kinds in today's order; repositories and authors A to Z (ignoring case); dates newest first. A group's key is a `GroupKey` (`kind`, `repository`, `date(DateBucket)`, `author`, `sender` (a ping's `--from` under `group-by = "author"`, titled as written, after the authors, #100), `ungrouped`); `GroupID` is the project's name and that key. The date buckets count calendar days back from `now` (Today, Yesterday, the week so far, the month so far, Older) by `sort-by`'s date: `createdAt` for `created`, else `updatedAt` (a closed item's `closedAt`). The rows come without attention flags, which `applyAttention` sets on each group's rows along with its `attentionCount`; an internal variant arranges rows that already carry them. `applyAttention` also sets each subsection's `isFolded` from `collapsedGroups`, so a fold needs no refresh, and keeps them as the model's `foldedGroups`, which the All tab (its groups' project is empty) is arranged with. `MenuTabs` uses the section's groups for a project's tab; the All tab arranges its rows with fixed settings (kind, updated, subheaders, no cap). The layouts draw a group with `showsHeader` under a `GroupHeader` (a chevron, its title, a kind or a date in capitals, and its row count, folded or not; a click folds or unfolds it, and a folded group draws its subheader alone), and any other group but the first after a `GroupDivider` line (`Components+Groups.swift`). `RowHighlight`'s places gain `groupHeader(GroupID)` and `showMore(GroupID)`, so ↑ and ↓ stop there, ← and → fold a subsection, Return on a subheader folds or unfolds it, and Return toggles Show more (`MenuListTarget.showMore`, `MenuTabContent.showMoreGroup(at:)`); ← on a Show more row goes to its subheader, or its project's header after a divider. Group titles, date bucket names and "Show 3 more" / "Show less" are in `PanelText+Groups.swift`.
### UI — `ShipyardApp/UI/`

SwiftUI `MenuBarExtra` in `.window` style (a panel, not an `NSMenu`):

```tsx
<ShipyardApp> (ShipyardApp/ShipyardApp.swift)
  <MenuBarExtra label={<MenuBarLabelView>}>   icon (a pause glyph while paused) + menuBarLabel.text
    <Panel>                                   the shared frame; switch shipyard.phase
      header                  the account (#49): round avatar + "@handle" (PanelText.title(for: viewer)), one button that
                              opens the profile (openProfile, then closeMenu), pointer cursor, the full name in its hover
                              text (profileHelp), VoiceOver "Open @handle's profile on GitHub"; "Shipyard" while
                              viewer is nil (connecting, signed out, GitHub out of reach at sign-in); the avatar from
                              AvatarCache, a plain circle until it's there or when it can't be had ·
                              "3 need attention" · Layout (ready only: the current layout's icon, list.bullet or
                              rectangle.split.3x1; hover help and VoiceOver PanelText.layoutButton, "Layout: list. Click
                              for tabs."; a click is switchToNextLayout) · Refresh (⌘R; while refreshing, the
                              native mini spinner in place of the arrow) ·
                              gear menu: Open configuration file · Install agent skill… · Link shipyard CLI… · Sign out (once signed in)
      signedOut              → <ConnectView>  (Onboarding/)
      connecting             → <ConnectView>  (the device flow's code, Copy code and open GitHub, Cancel)
      needsProjects, presets → <PresetPicker>(Onboarding/): the presets as a radio group, each titled with its summary ·
                              for incoming-contributions "All my repositories (owned)" (on) or "Pick repositories" ·
                              "Choose repositories" (then <ProjectPicker> with a back button, whose Add writes the
                              preset) or "Start with <preset>" (writes it at once)
      needsProjects, none    → <ProjectPicker>(Onboarding/): a field for owner/name or a link · the suggestions and typed
                              repositories as checkboxes, each chosen one with its project name and "Group with" ·
                              "Adds …" summary · Add N projects
                              <SkillInstallCard> (the offer to install the agent skill, always shown here)
                              <CLILinkCard> (the offer to link the CLI, always shown here, under the skill's)
      banners                 config error (any phase) · config warnings (any phase, gray: unknown settings the
                              file ignores, "config.toml line 1: unknown setting `future-key` (ignored)", with a
                              "did you mean" when one is close) · once ready: refresh delay (stretched, backed off: amber;
                              paused: red) · fetch error · notifications off (with a button to System Settings);
                              each slides in and out
      ready → switch menu.layout ([menu] layout), each given the menu model and LayoutActions
        <ListLayout>          (Layouts/) "list": a scroll view as tall as the measured rows, up to 560 pt; the window
                              sizes the panel from a zero-height proposal, so the height is fixed rather than
                              flexible (#27, MeasuredScrollView)
          header ×N           pinned while its rows scroll: chevron (click collapses/expands, spring), folder, name,
                              attention count (muted while expanded), "Nothing open" / "Not loaded yet", or on hover
                              "Mark all seen"; highlighted like a row (drawn on its own background); ← collapses,
                              → expands or goes to its first item, Return opens the project's first repository
          row ×N              one line in columns: attention dot, state icon (check dot on it; a running run pulses),
                              number, title (semibold when it needs attention; a run: workflow name and its branch
                              as a chip), author (the repository in multi-repository projects), age; a line where
                              the kind changes; the hover help holds the state, the full "#21 · …" detail and the checks;
                              click or Return opens and marks seen, ⌥-click or ⌥Return marks seen only; ↑/↓ move the
                              highlight through headers and rows, wrapping; ← goes to the row's header
        <TabsLayout>          (Layouts/) "tabs": a pill strip (All, one tab per project, attention counts), the
                              line under it with Mark all seen or Mark seen, the tab's rows as its arrangement groups them, All by kind (#36);
                              ↑/↓ move through the tab's rows, wrapping; ←/→ switch tabs (provisional); a row
                              clicks, shows hover help and highlights as the list's does (itemRow)
      <SkillInstallCard>      above the footer, after the gear menu's "Install agent skill…" (disabled in needsProjects, which shows the card), with a close button
      <CLILinkCard>           above the footer, after the gear menu's "Link shipyard CLI…" (disabled in needsProjects, which shows the card), with a close button
      footer                  last updated (the native mini spinner and "Refreshing…" while a refresh runs) ·
                              global "Mark all seen" · Quit (⌘Q) · rate limit lines, each with a bar
                              (amber low, red exhausted)
```

The frame and the layouts share `Design.swift`'s tokens (the spacing `Grid`, the `TypeScale`, the `Palette` of state and surface colours for light and dark, and `Motion`) and `Components.swift`'s pieces (`MeasuredScrollView`, whose height `MeasuredHeight` (`ShipyardCore/Menu/`, pure, #94) decides: the content's measured height capped at `maxHeight`, written only when it moves by half a point or more, since a lazy stack's height estimate depends on the viewport and writing each one looped the panel's layout; `Banner`, `CountBadge`, `CommandBox` and its `CopyButton`, with `Clipboard`; a row's `StateSymbol`, `CheckDot`, `AttentionDot` and `ErrorRow`; `itemRow(…)`, which makes a layout's item row a button that opens it on click and marks it seen on ⌥-click (or the VoiceOver action), with the hover card from `PanelText.rowCard` and the row highlight, and on a ping's row a ✕ (`DismissButton`) over its age while it's highlighted, which dismisses it; `MarkSeenButton`, a project's or tab's Mark all seen; the row, press, icon, pill and text button styles; the row highlight's shape, `rowHighlight(_:in:)`), so the two layouts look like one app. The plumbing behind the highlight and the keys (`highlightable`, `clearsRowHighlight`, `rowKeys`, `RowFrames`, the focus on each open) is in `RowKeys.swift`. A layout is a view `(model: MenuModel, actions: LayoutActions)`; `LayoutActions` (`open`, `markSeen`, `dismiss`, `markAllSeen`, `toggleCollapsed`, `openRepository`) comes from `AppServices`, and a layout reads the time for ages from the `panelNow` environment value the panel's 30 s timeline sets.

Each layout highlights at most one row, and keeps which one in a `RowHighlight` (`ShipyardCore/Menu/RowHighlight.swift`, pure, #44, #45). A row is known by its `MenuRowPlace`: its project in the list layout (where one item can be listed under two projects) and its row id, or, for a project's header in the list layout, `.header(project)` (no row id): headers are rows the pointer and the keys highlight like items. Rows and headers feed the pointer's enter and exit to it (`highlightable(_:_:drawsOwnHighlight:)`): an exit from a row the highlight already left changes nothing, leaving the rows clears it even if the last exit never arrived, and `keep(in:)` clears it once its row stops being listed (collapsed, refreshed away, another tab). The rows a highlight can rest on, top to bottom, are `MenuModel.listRowPlaces` (each project's header, then, while it's expanded, its groups' places) and `MenuTabContent.rowPlaces` (its groups' places); error and placeholder rows aren't among them. Since 0.0.2 a place is a `MenuRowPlace.Kind`: an item, a project's header (`.header(project)`), or a subsection's subheader (`.groupHeader(GroupID, in: section)`, the section `nil` in a tab), which the highlight rests on like a row; `RowGroup.places(in:)` gives a group's places (its subheader, then, unless folded, its rows and its Show more row, `.showMore(GroupID, in: section)`), the one seam a new stop extends. The layout draws the highlight once, behind its rows (`rowHighlight(_:in:)`): one shape placed at the highlighted row's bounds (read from anchor preferences) that glides to the next row, rather than a shape matched between rows, which a lazy stack's recycled rows made jump. Tabs list a row at the same place, and while the list slides from one tab to the next both tabs are on screen, so a tab's rows are marked with `rowList(tab)` and what they report (bounds and spans) is keyed by `RowSlot` (the tab and the place); the tabs layout draws the highlight outside the sliding lists, for the selected tab's slots only, so the outgoing tab isn't lit and the shape fades in on the new tab. A project header pins over the rows, so it draws its own highlight on its background instead. Error rows and placeholders call `pointerLeftRows()` when the pointer enters them (`clearsRowHighlight(_:)`), so a row whose exit was lost doesn't stay lit.

The keys drive the same highlight (#45), so the pointer and the keys can't disagree; every rule is in `RowHighlight` and `RowScroll` and tested there. `rowKeys(_:places:in:pinnedHeader:scroll:left:right:dismiss:activate:)` (`RowKeys.swift`) goes on each layout's scrolling list. ↑ and ↓ call `moveUp(in:)` / `moveDown(in:)` with the layout's row places (the list's, or the selected tab's), which step to the previous or next place (from none: the first or the last) and wrap at the ends, like `NSMenu`. In the list layout, ← and → are `moveLeft(in:)` / `moveRight(in:)`, as in an outline: ← goes from an item to its subheader (or, in a group without one, its project's header), folds an open subheader, goes from a folded one to its project's header, and collapses an expanded header; → expands a collapsed header and goes from an expanded one to what's first under it, unfolds a folded subheader and goes from an open one to its first item; they return the `MenuFold` (collapse or expand a project, fold or unfold a group) the layout passes to `toggleCollapsed` or `toggleGroup`. In the tabs layout, ← and → on a subheader fold and unfold it (`moveLeft(in:)` / `moveRight(in:)` with the tab's content; → on an open one goes to its first item); anywhere else they switch to the previous or next tab (`MenuModel.tab(beside:by:)`, wrapping; provisional) and `moveToFirst(in:)` puts the highlight on the new tab's first place. Return acts on `MenuModel.listTarget(at:)` (an item, a header's project, a subheader's group, or a Show more row's group) or `MenuTabContent.row(at:)` / `subsection(at:)` / `showMoreGroup(at:)`: an item opens and is marked seen, ⌥Return only marks it seen, like a click and an ⌥-click; a header opens its project's `repositoryURL` (the first configured repository) through `openRepository`; a subheader folds or unfolds, as a click on it does; a Show more row shows the rest of its group, or as Show less caps it again; ⌥Return on a header, a subheader or a Show more row does nothing. ⌫ on a ping's row dismisses it (`dismiss`); on any other place it does nothing. An item in a folded subsection is no target. After a key the highlight stops following the pointer (`followsPointer`), so rows scrolling under a resting pointer don't take it back; it still records which row is under the pointer, and when the pointer really moves (a new location from `onContinuousHover`) `pointerMoved()` hands the highlight to that row, or to none.

Scrolling with the keys: the list layout is one lazy stack whose every line (a project's placeholders, error rows and item rows, each with the hairline where the kind changes) is its own child, under `Section`s whose headers pin, and each row and header carries its place as its `.id`, so `ScrollViewReader` can reach a row the lazy stack hasn't laid out. Each laid-out row reports its span in the list's visible area to a `RowFrames` (a reference in the environment, kept out of view state), under its `RowSlot` and a token for the row view, so a row view that disappears (dropped by the lazy stack, or the outgoing tab's) forgets only the span it reported itself; and `RowScroll.reveal` decides: a row in full view doesn't scroll; one past the bottom scrolls to sit on it; one above the top, or under the pinned header, scrolls to sit just below the header (a unit anchor worked out from the list's and the row's heights); one not laid out scrolls towards the way the highlight moved (up: to the top), except a header's first item after the header, which is under the header pinned at the top: just below the header. A wrap (↓ from the last row to the first, ↑ from the first to the last) scrolls straight to the list's far end in the same key press, laid out or not: to `RowListTop` or `RowListBottom`, zero-height views the layout puts above and below its rows, outside the lazy stack. The lazy stack guesses the height of rows it hasn't laid out, so the first scroll to the bottom can stop short of the last row; a `RowWrapLanding` (pure, in `RowScroll.swift`) follows the wrap: each time rows report new spans (`RowFrames.rowsMoved`), once the update is laid out, it checks the wrapped-to row and scrolls to the same end again until the row is in full view, at most four times; any key or pointer move ends it. A row the lazy stack kept but hid reports its last span again when it reappears (a wrap back to the end it came from leaves it where it was, so its geometry doesn't change and it wouldn't report otherwise). The scroll isn't animated, so a held key repeats at the system's rate and the list keeps up; only the highlight shape glides. `onKeyPress` calls the handler it had at the key-down for every repeat of that key, with that handler's copy of the modifier (its rows, and a highlight from before the first step), so the key handlers act through a reference to the modifier as last drawn (`LatestRowKeys`), along with the highlight a key set that the view hasn't been updated with yet; ↑/↓ take `.down` and `.repeat`, and ←, → and Return act once per press. A highlighted item row gets the rounded, inset shape; a highlighted project header fills its whole band, square and full width. A tab switch scrolls to the list's top (`RowListTop`, a zero-height view above the sliding lists), where the new tab's first row is: not to the row itself, which isn't laid out yet and whose id the outgoing tab's row shares.

Hover help (#72): the panel doesn't use macOS's native tooltips (`.help`), which come late, look dated, are cut off at the panel's edge and linger over the rows. A view with help says so with `hoverHelp(_:context:leadingInset:)` (`HoverHelp.swift`), which also gives the text to VoiceOver as the view's hint, as `.help` did; `nil` shows nothing. The panel draws the help once, with `hoverHelpHost()` on its frame: the hovered view reports its bounds and text through an anchor preference (like the row highlight's), and a card on the system's regular material, with the panel's hairline, sits under the view, or over it when there's no room below, lined up with a row's title or centred under a button, kept inside the panel. `HoverHelpPlacement` (`ShipyardCore/Menu/`, pure, tested) decides the frame, so the card never covers the view the pointer is on and the panel's edge never cuts it off; drawn at the frame, it reaches past the scroll view's clip. The context sets the timing (`HoverHelp.timing`). On the header's buttons, the account and the tabs (`toolbar`), the card shows after the pointer rests 0.5 s, at once while it's warm (just shown, or hidden less than 0.6 s ago), and glides to the next button with the highlight's spring. A row's card (`hoverHelp(_ card: RowCard, leadingInset:)`) shows the author's avatar (20 pt, SwiftUI's `AsyncImage`, at `AvatarCache`'s size) centred beside the full title as its header; under the title, a review request (amber) and failed checks (red) as tinted tags, from the row's attention reasons (new and changed get no tag; the row's attention dot says as much), then `RowCard.facts`, a line of them at a time, each an SF Symbol and a short value, coloured only where it says how things stand (added green, removed red, the review and checks by state, a running run amber). An issue with no comments has no facts line. On the item rows (`row`), which the pointer crosses on its way elsewhere, it shows after a 1 s rest, closes as the pointer leaves the row, and every row waits again, so it never follows the pointer down the list. Either way it fades when the pointer leaves and never takes the pointer. `HoverHelp.style` swaps it for SwiftUI's own popover beside the view (the runner-up in `docs/references/macos-hover-help.md`) in one place. Where hover help isn't worth it there's none: a subheader's or a list section's chevron, the skill card's close button, the command box's Copy (its icon turns into a checkmark), the picker's lock; each keeps its VoiceOver label or hint. A note row and an error row wrap instead of truncating, a pull request's check dot has its words in the row's card, and a tab shows its title as help only while the title is cut off.

Focus: the list takes the keyboard focus when it appears and again each time its window becomes key (`NSWindow.didBecomeKeyNotification` for the window it's in, through a zero-size `NSViewRepresentable`), because the `MenuBarExtra`'s view outlives a closed menu and focus set before the window is key is lost; so the arrows work as soon as the menu opens. The panel's window is key while the menu is open, which is what lets the list receive keys (as ⌘R and the picker's text field already do); closed, it's off screen and takes no keys, and nothing here changes when the window becomes key or the app's activation.

`ConnectView` draws `PanelText.connect(signedOutReason, canSignIn: canSignInWithGitHub)` in one shape for every state (#78): the logo (`LogoBadge`, the app icon's squircle and sailboat, #80) and a greeting ("Welcome to Shipyard" with no token or after a sign-out that left nothing signed in, "Welcome back" otherwise), a line or two on what happened, then the ways in as full-width buttons stacked in the order its `lead` gives, the main one prominent. `signIn` (no token, signed out with nothing left signed in, or the Keychain token rejected): **Sign in with GitHub** (`beginDeviceFlow()`), then a collapsed native disclosure, "Use the GitHub CLI `gh` instead", holding the `gh auth login` box (`CommandBox`) with an ⓘ beside it, whose popover gives a cli.github.com link and a copyable `brew install gh`, over **Connect with `gh`**. `ghCommand` (`gh`'s token rejected): the `gh auth login` box over Connect with `gh`, prominent, then Sign in with GitHub. `connectWithGh` (signed out while `gh` is still signed in): two blocks with a native divider between them: "The GitHub CLI `gh` is already signed in on this computer, so connecting takes one click:" over Connect with `gh`, prominent, then the `alternative`, "Alternatively, sign in with GitHub, if you'd rather:", over Sign in with GitHub; no `gh auth logout`, and without a client ID no second block. With the placeholder client ID, `gh` leads (`ghCommand`, with the ⓘ when there's no token, or `connectWithGh` alone) and Sign in with GitHub is disabled with `PanelText.signInUnavailable`. Under Sign in with GitHub, `PanelText.signInFailed(signInError)` after a flow that ended without a token. Connect with `gh` (`start()`) says why (`PanelText.stillSignedOut`) under it when it leaves shipyard signed out, and isn't the default action, so Return can't undo a sign-out. Every `gh` in the words is in backticks, and the panel draws code spans monospaced on a faint chip (`CodeText`, `ShipyardApp/UI/Components.swift`, tested in `Tests/ShipyardAppTests`): SF Mono's "g" and "h" are drawn almost like SF Pro's, so the monospaced font alone left `gh` looking like the words around it. Hover help takes Markdown too (`hoverHelp(markdown:)`). In `connecting(code)` it draws `PanelText.deviceCode(code)`: the user code, large, which a click on it or on its copy icon (`CopyButton`, the command box's, here with its word "Copy" beside it) puts on the clipboard, turning the icon into a checkmark and rolling the word to "Copied" with the counts' `numericText` transition and `Motion.count` spring (the only feedback: the code has no hover help; VoiceOver hears "Copy code", then "Copied"; ten seconds after the last copy, through the button's cancellable `.task(id:)`, it turns back with the same animations, as the command box's does; a new code resets it at once), when it expires, Cancel (`cancelDeviceFlow()`) and Copy code and open GitHub, which puts the code on the clipboard before `openVerificationPage()` (the browser taking focus may close the menu; the flow goes on in `Shipyard`). While `start()` looks for a token (no reason yet) it shows "Connecting to GitHub…", keeping the last reason on screen during Connect with `gh`. The header's gear menu has Sign out once signed in (not while `start()` is still connecting). `ProjectPicker` loads `suggestedRepositories()` when it appears (a failure says why, with Retry, and typing still works), checks a typed `owner/name` or link with `checkRepository(_:)` (a rejection shows its `message`), and keeps what the user picked in a `ProjectChoices` (`ShipyardCore/Onboarding/`, pure): the repositories offered (typed ones first, so one just added is in sight, then the suggestions), the chosen ones in order, and each one's project name, which starts as the repository's name (`owner/name` when a project already has that name, so choosing never groups by accident). Naming and grouping are one field: chosen repositories with the same trimmed name make one project, and "Group with" copies another project's name. `projects` is what Add passes to `addProjects(_:)`; `hasUnnamedProject` blocks Add while a name is empty. While `shipyard.presets` isn't empty (the file holds nothing but `version`), the panel shows `PresetPicker` first: a native radio group of `presets`, each with its title and summary, and for `incoming-contributions` a second one, "All my repositories (`owned`)" (the default) or "Pick repositories". Its state is a `PresetChoice` (`ShipyardCore/Onboarding/`, pure): the chosen preset, `watchesOwned`, and whether the picker comes next (`needsRepositories`). The button says so (`PanelText.presetContinue`): "Choose repositories" shows the `ProjectPicker` with a back button, whose Add calls `choosePreset(preset, projects:)` with the picked projects; "Start with …" calls it at once with none. A refusal empties `presets`, so the panel shows the plain picker. Adding moves the phase to `ready`, so the panel shows the list without a restart; the list scrolls inside a measured fixed height, like the sections (#27). `SkillInstallCard` draws `PanelText.skillInstall(state)` for the app's one `SkillInstallation` (owned by `AppServices`, so an install goes on while the panel is closed): the offer with the command and Install, Cancel while running, then installed with its output, the failure's output, npx not found, or timed out, each but the success with the command and a Copy button and Try again. `CLILinkCard`, shaped like it, draws `PanelText.cliLink(state, command:)` for the app's one `CLILink` (owned by `AppServices`, its CLI `Contents/Helpers/shipyard` in `Bundle.main`, its home the user's): it calls `check()` each time it appears, since the user may have linked it by hand, then the offer with the command and Link, linked (with the PATH reminder), something in the way or a failure (each with the command, a Copy button and Try again), or no CLI to link.

The words the panel shows (a row's age and second line ("#21 · yahyabedirhan · 37m" for a pull request or an issue; "#41 · main · failed · 12m" for a run, whose first line is its workflow's name; the repository after the number only when the project has more than one, named without its owner by `repositoryName`), a row's hover card in either layout (`PanelText.rowCard`, only what the row doesn't show: the author's avatar and full title; a pull request's branches, size, review and checks; comments and when it last changed; a run's title, what started it, who and how long it ran; a review request and failed checks, from `Attention.reasons`; each fact in words for VoiceOver through `PanelText.fact`), the header buttons' hover help, a list section's VoiceOver hint, a state's word and the state icon's VoiceOver label, the header (the account's "@handle", its hover text and VoiceOver label, "Shipyard" until the account is known, "3 need attention"), the Mark all seen buttons, "Last updated 5 min ago", the configuration error and warnings, fetch error, refresh-delay and notifications-off banners, the rate-limit lines, the connect screen, the picker's Add button ("Add 2 projects") and its summary line, the skill install card, the CLI link card) come from `PanelText` in `ShipyardCore/Menu/` (one file for the menu, one per onboarding screen, the skill card and the CLI link card), so they're tested with the menu model. The app wires the core in `AppServices` (`ShipyardApp.swift`): `ConfigWatcher` and `WakeObserver` call `reloadConfiguration()` and `refresh()`, opening the panel only rereads the notification permission (it doesn't refresh), ⌘R is the header's Refresh button (`refreshNow()`, which also creates a missing configuration file), and `layoutActions` hands the layouts their `LayoutActions`. `AppServices` owns the `Notifier`, routes its clicks to `openNotification(_:)`, tells the panel whether notifications are off, and holds the `SkillInstallation` and the `CLILink`. `AppServices` also holds the `AvatarCache` (in `Application Support/Shipyard/Avatar/`) the header's account draws from. Opening something elsewhere (a row's `open`, a notification's item, the header's account through `openProfile()`, "Open configuration file") then calls `closeMenu()`, which closes the menu the way a click on its icon does, through the status item (SwiftUI has no dismiss for a `.window` `MenuBarExtra`); ⌥-click, collapse, tab switches and Mark all seen leave it open (#39).

`TabsLayout` (`UI/Layouts/`, `[menu] layout = "tabs"`) is the ready state's body built from the `MenuModel` and `LayoutActions`: a pill strip with All and one tab per project, each with its attention count (All's is the model's attention count, so a row listed in two projects counts once); under it "5 need attention · 4 projects" (a project's tab leaves out the project count) with Mark all seen, or Mark seen for one project; then the tab's error rows and its rows grouped under Pull requests, Issues and Runs (All: every project's rows in project order, each row once, naming the repository once there's more than one project), each with its age on the right. The rules live in `MenuTabs.swift` (`tabs`, `attentionCount(for:)`, `resolved(_:)`, `tabContent(for:)`) and the words in `PanelText`. The selected tab is view state, kept while the menu is open, and falls back to All when its project leaves the configuration. More tabs than fit scroll sideways: choosing one scrolls it into view, and an end fades while tabs are hidden past it. The strip and the list are measured and fixed in height, like the list layout (#27, `MeasuredScrollView`).

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

After every refresh `Shipyard` asks `nextDelay`, publishes it and the indicator in the menu model, and arms the refresh timer with it (`paused` arms for the configured interval, or the time left until the pause ends when that's sooner: each such firing sends nothing and only lists again from the last snapshot, so a closed item leaves within an interval of its window passing even while paused), so a busy hour slows shipyard down on its own instead of running the limit dry. Workflow runs (REST) only have to report `rateLimits.rest` with the counted requests as `cost`.

### PingStore — `ShipyardCore/Pings/PingStore.swift` (0.0.5)

The pings agents send, one JSON file per ping (`<id>.json`) in `~/Library/Application Support/Shipyard/Pings/` (`PingStore.defaultDirectory`; tests pass a temporary one), apart from `state.json`: app state is what shipyard remembers from use, pings are data agents send. The format is private (ADR 0004); `Ping` is `Codable`, and a field added later is optional, so an older record still reads. The CLI and the running app write to it at the same time: each write replaces one ping's file atomically, so a reader sees a whole ping or none, and two pings' writes never meet. A plain `struct`, not tied to the main actor, since the CLI uses it too.

| Operation | Returns / rejects |
|---|---|
| `all() -> [Ping]` | every `*.json` that reads, oldest first; none when the directory doesn't exist yet. A file that doesn't read is skipped |
| `ping(id:) -> Ping?` | one ping |
| `save(ping) throws` | creates the directory when missing; replaces the ping's file atomically |
| `markSeen(ping, at:) throws` | sets `seen` once (a second click keeps the first time) and clears `failure`. The ping is read again just before the write, and only the same sending as `ping` (`Ping.isSameSending`: same id, instance and content, whatever `seen` and `failure` say) is written: one withdrawn meanwhile stays gone, one replaced or sent anew stays unseen |
| `recordFailure(ping, reason:) throws` | sets `failure`, leaving `seen` as it is; only on the same sending, as `markSeen` (#100) |
| `removeIfUnchanged(ping) throws -> Bool` | removes the ping only while the store holds it exactly as `ping` (read again just before), for a seen ping past its window: one replaced, sent anew or seen again since stays; whether it's gone |
| `remove(id:) throws` | deletes the ping's file, its failure with it; an unknown id changes nothing (#103) |

The app watches the directory with `ConfigWatcher` (as the "file", inside its parent, so creating it is seen too) and calls `Shipyard.reloadPings()`; the parent also holds `state.json`, so most of those calls find nothing new and change nothing.

### PingList — `ShipyardCore/Pings/PingList.swift` (0.0.6)

The remote ping list: the JSON `shipyard ping list --json` prints on a machine and the Mac's shipyard reads from it through Herdr (#109). Unlike the store's files, it's part of the CLI's public contract (ADR 0004): `{"pings":[…],"shipyardVersion":"0.0.6","truncated":false,"version":1}`, compact, keys sorted, dates ISO 8601 in whole seconds. `version` is the contract's major version (`PingList.currentVersion`, 1): a field a reader can ignore keeps it, anything else bumps it. Each ping carries what it's sent with (id, instance, title, body, sender, repository, projects, action, sent); `seen` and `failure` stay on the machine that recorded them. Which pings to list (the machine's live ones) is the caller's choice.

| Operation | Returns / rejects |
|---|---|
| `PingList.encode(pings, shipyardVersion) -> String` | newest first (by `sent`, then id), at most `maxPings` (100), stopping at the first ping that would take the document over `byteBudget` (48 KiB, well under Herdr's 64 KiB action output); `truncated` when it stops early. Always a whole document |
| `PingList.decode(text or data) throws(DecodeError) -> PingList` | reads `version` first: another one is `.unsupportedVersion(version, shipyardVersion:)`, whose `message(machine:)` says to update shipyard on that machine; not JSON, or a field missing or mistyped, is `.unreadable(reason)`. Unknown fields are ignored, and so is an action of a kind it doesn't know (the ping reads without one) |

### ResolvedRepositoriesStore — `ShipyardCore/State/ResolvedRepositoriesStore.swift` (0.0.5)

Each project's repositories as the app last resolved them (`ResolvedRepositories.repositories`, by project name), in `repositories.json` beside `state.json` (`ResolvedRepositoriesStore.defaultDirectory`, `~/Library/Application Support/Shipyard/`, the one definition of that folder: the app's stores and `PingStore.defaultDirectory` are built on it, so the CLI and the app can't disagree; tests pass a temporary one), so the CLI can file a ping by a repository a group or `owner/*` brought in without calling GitHub. The app writes it after every resolve in a refresh (a write that fails is ignored) and never reads it; the CLI only reads it. Private format (ADR 0004): `{ "version": 1, "projects": { "<name>": ["owner/name", …] } }`. A plain `struct`, like `PingStore`, since the CLI uses it too. It fails safe: a missing file, one that doesn't read or a newer `version` reads as no lists, so a ping still matches the configuration's `owner/name` selectors, and the next resolve writes it again. It's left as it is on sign-out; the next account's first resolve replaces it.

| Operation | Returns / rejects |
|---|---|
| `load() -> [ProjectName: [String]]` | the lists; empty when nothing reads |
| `record(lists) throws` | replaces the file atomically; writes nothing when it already holds `lists` (the parent directory is watched for the ping store, so a needless write would wake it) |

### PingCommand and ShipyardCLI — `ShipyardCore/Pings/PingCommand.swift`, `ShipyardCore/CLI/ShipyardCLI.swift`, `ShipyardCore/CLI/GitRemote.swift` (0.0.5)

`ShipyardCLI.run(arguments, environment, configURL, repositories, pingStore, now) -> CommandResult` is the whole `shipyard` executable: `--help`, `--version`, and `ping`, which reads `config.toml` as the app does (a missing file is no projects; one that doesn't read fails with its first problem, since the CLI has no last valid configuration to fall back on) and the lists in `repositories` (a `ResolvedRepositoriesStore`), and runs `PingCommand.run`. `CommandResult` is the output, the error text and the exit status: 0 done, 1 refused (`failedStatus`), 2 arguments that don't read (`usageStatus`). `CommandEnvironment` is the working folder, the environment variables (`HERDR_PANE_ID`, which `--herdr` without an id takes) and `git`, a `GitRemoteLookup` port: `origin(in: folder) -> String?`, the remote's URL or `nil` when the folder isn't in a git repository or has no `origin`. `GitCLI` runs `git -C <folder> remote get-url origin` (through `/usr/bin/env`, so the agent's `PATH` finds git), so worktrees and `insteadOf` read as git reads them; tests pass `FakeGitRemote`, a fake working folder. `GitRemote.repository(fromURL:)` reads `https://`, `ssh://`, `git://` and scp-like `git@host:` URLs whose path is exactly `owner/name` (`.git` and a trailing `/` dropped); a local path, `file://` or a deeper path is no repository.

| Operation | Returns / rejects |
|---|---|
| `PingCommand.run(arguments, environment, configuration, resolved, store, now, newID) -> CommandResult` | `<title>` with `--repo <owner/name>` or `--project <name>` or neither, `--body`, `--from`, and one action flag at most (`actionFlags`: `--open <url>`, `--app <bundle id or name>`, `--herdr [<tab or pane id>]`), in any order; `--herdr` takes the next argument when `isHerdrID` (`<workspace>:t<n>` or `:p<n>`), else `HERDR_PANE_ID` (#101); the body, sender and action are saved with the ping (#100). `--project`: filed under that project, with no repository. Otherwise the repository is `--repo`'s, else the working folder's `origin`, and it's filed under every project (in configuration order) whose `owner/name` selectors or `resolved` list include it, ignoring case; the ping keeps the repository as the first such project spells it (GitHub's spelling once resolved), which `Ping.item` fills. Saves `Ping(id, title, projects, sent: now, repository)` and prints the id. The id is `newID()` (`Ping.newID`: six letters and digits without `0 o 1 l i`), drawn again while the store has it, since ids are global | no title, two titles, an unknown option, a flag without its value, `--repo` that isn't `owner/name`, `--repo` with `--project`, two action flags, `--open` without a scheme, an empty `--app`, or `--herdr` without an id outside Herdr: exit 2; a project the configuration doesn't name: exit 1, listing them (or saying there are none); no `origin`, or one that isn't `owner/name`: exit 1, saying so, with `--repo`/`--project` as the way out and the projects listed; a repository no project watches: exit 1, listing the projects; a store that can't be written: exit 1 |

| `PingCommand.run`, `--id <id>` (#102) | names the ping; `isID` (`\A[a-z0-9][a-z0-9_-]{0,63}\z`, anchored so a trailing newline isn't accepted, which generated ids also match, and which keeps it a safe file name and URL path on a case-insensitive disk). A stored id is replaced: the new title, body, sender, action, projects and repository, the stored `sent` and `instance`, `seen` and `failure` cleared. A new ping gets a new `instance` (a UUID). Without it, `newID()` as above | an id that isn't one: exit 2 |
| `PingCommand.withdraw(arguments, store) -> CommandResult` (#102) | `shipyard ping withdraw <id>`: `store.remove(id:)`, prints the id. `ShipyardCLI` sends `ping withdraw …` here before reading `config.toml`, so a broken file doesn't stop it | no id, two, or one that isn't an id: exit 2; an id no ping has: exit 1 ("no ping has the id …"); a store that can't be written: exit 1 |

`PingCommand.Request.parse` reads the arguments after `ShipyardCLI` has checked for `withdraw` as the first one. `--` ends the flags: everything after it is the title, even `withdraw` (`shipyard ping -- withdraw`) or a word starting with `--`, and `--help` after it isn't help.

`PingCommand.send(request, folder, git, configuration, resolved, store, now, newID, unfiled)` is everything `run` does once the arguments read (filing, the id, a replace, the save), so `HerdrEvent` sends through the same path. `folder` is where the repository is looked up (`nil`: nowhere); `unfiled` saves a ping no project takes under none, with the repository it named, instead of refusing it.

### HerdrEvent — `ShipyardCore/Pings/HerdrEvent.swift` (0.0.6, #112)

`shipyard herdr-event`, which the herdr-shipyard plugin's event hooks run, so a blocked agent pings without remembering to. `ShipyardCLI` sends it `HerdrEvent.run(environment, configuration, resolved, store, now)`; `configuration` is a closure, read only for a blocked agent's ping, so a `config.toml` that doesn't read never stops a withdraw. It reads `HERDR_PLUGIN_EVENT` and `HERDR_PLUGIN_EVENT_JSON`, whose fields (`pane_id`, `workspace_id`, `agent_status`, `agent`, optionally `display_agent`) Herdr puts under `data` (read from the top level too). The ping's id is `herdr-<pane id>`, each character outside the id alphabet a `-` (`w1:p3` → `herdr-w1-p3`), cut to 64.

| Event | Does |
|---|---|
| `pane.agent_status_changed`, `blocked` | `herdr pane get <pane>` (its `tab_id` and `cwd`), then `herdr tab get <tab>` (its `label`), through `CommandEnvironment.run` (the synchronous `GhCLI.Run` port; tests answer with `FakeHerdr.command`), with Herdr's own `HERDR_BIN_PATH`, else `herdr` found as `HerdrFocus` finds it. Then `PingCommand.send` with `--id herdr-<pane>`: title "<Agent> is waiting in <tab label>" ("An agent…" without a name; the pane id without a label, or when `herdr` can't say), sender `display_agent` or `agent`, action `.herdr(pane)`, filed by the `origin` of the pane's `cwd` and saved `unfiled` when no project takes it. Blocking again replaces it (one per pane, no second notification); prints the id. Herdr runs each event's hook on its own, so when `pane get` already says the agent went on (another status), the ping isn't sent and any there is withdrawn, as that later event would. A ping saved `unfiled` isn't listed by the Mac's app until remote pings get their machine section |
| `working`, `idle`, `done`, `unknown`; `pane.closed` | removes `herdr-<pane>` and prints its id; nothing, exit 0, when there's none |
| any other event or status | nothing, exit 0 |

Errors: no `HERDR_PLUGIN_EVENT`, or any argument: exit 2; a payload missing, not a JSON object, without `pane_id`, or (for a status change) without `agent_status`: exit 1, one line naming the event; a `config.toml` that doesn't read (blocked only) or a store that can't be written: exit 1. `herdr` isn't run with a timeout: the hook runs apart from Herdr's own work, and Herdr answers at once when it's well.

### The `shipyard` CLI target — `Sources/ShipyardCLI/main.swift` (0.0.5)

A thin executable target over `ShipyardCore`: it gathers the arguments, the working folder, the environment (with `GitCLI`), `ConfigStore.defaultURL(environment:)`, `ResolvedRepositoriesStore.defaultDirectory` and `PingStore.defaultDirectory`, calls `ShipyardCLI.run`, prints what it returns and exits with its status. Its product is `shipyard-cli` (on a case-insensitive disk `shipyard` and the app's `Shipyard` would be one file), and `make bundle` copies it to `Shipyard.app/Contents/Helpers/shipyard`, signed before the bundle so the bundle's signature seals it. It builds on Linux too, like the core.

### CLILink — `ShipyardCore/CLI/CLILink.swift` (0.0.5)

Puts the CLI on the user's PATH (N10). `CLILink(cli:home:fileSystem:)` is `@MainActor @Observable` and holds `state`: `unlinked`, `linked`, `occupied(destination:)` (a link elsewhere, or `nil` for a file or folder), `failed(reason)` (the system's words), `missingCLI`, or `translocated`: the CLI's path is under `/AppTranslocation/` (`isTranslocated`), macOS running a downloaded copy from a temporary path, so it links nothing and the card says to move Shipyard to Applications first, with no command or button. A link whose destination is gone (an older copy moved or deleted) isn't this app's, so it reads as `occupied`, with the command that replaces it. It looks through the `LinkFileSystem` port: `fileExists(at:)` (following links, for the app's CLI), `entry(at:)` (`none`, `link(destination:)` as written, or `other`, without following the link), `createDirectory(at:)` and `createSymbolicLink(at:to:)`. `FileManagerLinkFileSystem` is the real one; it's Foundation alone, so it lives in the core and the tests run it in a temporary folder (a wrapper that refuses the link stands for no permission). A link counts as this app's when its destination, resolved against `~/.local/bin` when relative, is `cli`'s path. `check()` looks again; `makeLink()` makes the folder and the link only when the state is `unlinked`, otherwise it just says what's there, and after a failure it looks once more so something that appeared meanwhile reads as occupied rather than a failure. `command` is what the card offers to copy: `mkdir -p ~/.local/bin && ln -sf <cli> ~/.local/bin/shipyard`, the CLI's path single-quoted when it isn't plain, which replaces whatever is there, since running it is the user's choice. `CLILink.bundledCLI(in:)` is `Contents/Helpers/shipyard` in a bundle. Linking is instant, so there's no running state, timeout or cancel, unlike the skill install.

### SkillInstaller — `ShipyardCore/Skill/SkillInstaller.swift`

Runs the user's login shell as an interactive one (`$SHELL -l -i -c 'npx -y skills add yahyabedirhan/shipyard -g -y'`, `/bin/zsh` when `$SHELL` isn't an absolute path) so nvm/asdf/Homebrew `PATH` setups are loaded. Spawning sits behind the `ShellRunning` port (`ProcessShellRunner` runs it with `Process`, standard input empty, output and errors read together), so tests use a fake shell. Cancelling `ProcessShellRunner`'s task returns `nil` at once and sends SIGTERM, then SIGKILL a second later, to the shell and every process under it (found with `ps`): an interactive shell ignores SIGTERM and runs the command as a job in its own process group, which would outlive it and hold the output pipe open. The panel doesn't call `install()` itself: `SkillInstallation` (`Skill/SkillInstallation.swift`, `@MainActor @Observable`) runs one install at a time and holds its state (`idle`, `running`, `finished(result)`, `timedOut(seconds)`); `start()` races the install against a 180 s timeout (the sleep is injected, so tests don't wait), `cancel()` goes back to `idle` at once and stops the shell (a result that arrives after is dropped, so Install can start again straight away), and a timeout stops the shell and says so.

| Operation | Returns |
|---|---|
| `install() async -> SkillInstallResult` | `installed(output)` on status 0; `npxNotFound(command)` on status 127 (the shell couldn't find `npx`), with `SkillInstaller.command` for the Copy button; `failed(output)` otherwise: what it printed, colour codes stripped, or "exited with status N" when it printed nothing, or "couldn't start <shell>" |

The skill it installs is `skills/shipyard/SKILL.md`, where `npx skills add` looks for a repository's skills (`skills/<name>/SKILL.md`, with `name` and `description` frontmatter). It documents the configuration file for agents; `SkillDocumentTests` read its frontmatter as strict YAML (the CLI skips a skill whose frontmatter isn't valid YAML, such as a value with an unquoted `: `), decode each of its TOML examples with `Configuration.decode`, check them against the schema, and check that it names every key (each nested one beside its table), default, event and author filter the code has, and that its worked requests configure what they say. How configuration works in the code, and the checklist for adding a setting, is `docs/configuration.md`; `ConfigurationDocumentTests` keep that checklist naming every place a setting lives.

### Folder tree

```text
shipyard/
├── Package.swift                     # SwiftPM: ShipyardCore (library) + ShipyardCLI (the `shipyard` CLI, product `shipyard-cli`) + ShipyardApp (macOS app target, `Shipyard` executable, declared only on macOS) + tests; one dependency: TOMLDecoder
├── .github/workflows/ci.yml          # core build + tests on Ubuntu (Swift 6); everything built, bundled and tested on macOS
├── Makefile                          # build, test (finds the Testing framework under Command Line Tools), bundle .app (with the icon, and the CLI as Contents/Helpers/shipyard), ad-hoc sign, zip, install, redraw the icon
├── Packaging/Info.plist              # LSUIElement (no Dock icon), bundle id, version, CFBundleIconFile
├── Packaging/Icon/                   # make-icon.swift draws the app icon's variants (olive-khaki, shipyard's logo, is the app's; origami, sailboat, night and sunset are alternates); `make icon` packs AppIcon.icns from `ICON`, `make icon-alternates` packs alternates/ with previews, all committed; README.md says how to switch; the Makefile compiles it with `Sources/ShipyardApp/Brand/Sailboat.swift` and `Logo.swift` (`make icon-exploration` redraws the options the logo was chosen from)
├── schema/config.schema.json         # public contract for config.toml (ADR 0001); JSON Schema describes TOML too
├── skills/shipyard/SKILL.md          # teaches agents the config file (selectors, groups, filters, arrangement); installed by `npx skills add`
├── skills/shipyard/presets.md        # the three presets, equal to the app's (tested)
├── docs/configuration.md            # for maintainers: how configuration works in the code, the checklist for adding a setting
├── assets/images/<topic>/           # the README's logo (logo/), by relative path; the app icon's comparison sheets (app-icon/, with exploration/ from `make icon-exploration`)
├── assets/screenshots/<topic>/      # screenshots embedded in issues and pull requests, by commit-pinned raw URL (docs/agents/issue-tracker.md); the README's example screenshots (shipyard-0.0.2/), by relative path
├── Sources/ShipyardCore/             # Foundation, FoundationNetworking, Observation and TOMLDecoder only, so agents can build and test it on a Linux VPS
│   ├── Shipyard.swift                # orchestrator: phase, refresh pipeline, user actions (@Observable)
│   ├── Lifecycle.swift               # Phase (signedOut, connecting, needsProjects, ready) and its transitions
│   ├── Version.swift                 # ShipyardVersion.current: the one place the version is recorded
│   ├── RefreshScheduler.swift        # RefreshGate (one at a time, queues one more) + RefreshTimer port and its Task-based timer
│   ├── Ports.swift                   # what the app plugs in: Notifying, TokenStore, WallClock, Sleep, ActionRunning, LoginItem
│   ├── Config/
│   │   ├── Configuration.swift       # file model, defaults, per-project merge, append text
│   │   ├── ConfigurationReader.swift # decode + validation: typed reads, errors, unknown-key warnings, suggestions
│   │   ├── TOMLSourceMap.swift       # key path → line, for validation messages
│   │   ├── Selectors.swift           # AuthorSelector, AuthorFilter, RepositorySelector: parse, match, the hints (ADR 0002)
│   │   ├── WindowDuration.swift      # closed-window and finished-window: a whole number and one unit (s, m, h, d) to seconds and back, and the nearest spelling for a near miss
│   │   ├── Presets.swift             # the three presets: names, what they ask for, their file text
│   │   ├── PresetSetting.swift       # the third writer: a preset into a file whose only live key is version
│   │   ├── LayoutSetting.swift       # the layout button's edit: set [menu] layout in the text, every other line kept
│   │   ├── ConfigStore.swift         # path, reload, last-valid fallback, append projects, set the layout, write a preset
│   │   └── ConfigStatus.swift        # ConfigStatus + config-status.json: the verdict after every reload, for agents
│   ├── GitHub/
│   │   ├── HTTPTransport.swift       # the one request seam: URLSession in the app, recorded responses in tests
│   │   ├── GitHubClient.swift        # transport (GraphQL + REST), errors, viewer (login, name, avatar, profile), rate-limit headers, ETags
│   │   ├── AvatarCache.swift         # the account's avatar on disk: downloaded once (no token, s=60), again only when its URL changes
│   │   ├── RateBudget.swift          # quota per API, refresh cost, next allowed delay, indicator
│   │   ├── ProjectQuery.swift        # builds the GraphQL query and parses it into Items
│   │   ├── Repositories.swift        # the picker's calls: recent repositories (GraphQL), checking a typed one (REST); RepoSummary, RepositoryCheck; a group's or owner's repositories, paged
│   │   ├── RepositoryResolver.swift  # repository selectors → repositories, hourly; archived and forks; an error per selector
│   │   ├── WorkflowRuns.swift        # REST runs request + parse + branch filter
│   │   └── Auth/
│   │       ├── TokenProvider.swift   # TokenStore → gh → none; GhCLI finds and runs gh
│   │       └── DeviceFlow.swift      # OAuth device flow
│   ├── Items/
│   │   ├── Item.swift                # Item, StateGroup, Snapshot, RepositoryError, RateLimit, fingerprint
│   │   ├── Listing.swift             # the one filter: what a project lists (ADR 0003)
│   │   ├── Attention.swift           # needs-attention rule, seen records, counts
│   │   ├── EventDetector.swift       # known items + snapshot → events; Event, ItemChange, KnownItems
│   │   └── NotificationRules.swift   # event + project settings → notify?; what to post; NotifiedEvents
│   ├── Pings/
│   │   ├── Ping.swift                # a ping: id, title, projects, sent, seen, repository, body, sender, action, failure; as an Item; new ids; PingAction, PingIcon
│   │   ├── HerdrFocus.swift          # a Herdr action: find herdr, focus the tab (a pane's tab via pane get), over ShellRunning
│   │   ├── HerdrEvent.swift          # shipyard herdr-event: a blocked agent's ping herdr-<pane>, sent, replaced and withdrawn
│   │   ├── PingStore.swift           # one JSON file per ping, atomic writes, safe for the CLI and the app at once
│   │   ├── PingList.swift            # the remote ping list (ping list --json): versioned, newest first, capped and never cut off; DecodeError
│   │   └── PingCommand.swift         # shipyard ping: arguments → a ping filed by its repository or under a project, saved; output and exit status
│   ├── CLI/
│   │   ├── ShipyardCLI.swift         # the shipyard command line: help, version, reading config.toml and repositories.json, dispatching to ping; CommandResult, CommandEnvironment
│   │   ├── CLILink.swift             # links ~/.local/bin/shipyard to the app's CLI, or says what's in the way (LinkFileSystem port, FileManagerLinkFileSystem)
│   │   └── GitRemote.swift           # the GitRemoteLookup port, GitCLI (git remote get-url origin), a remote's URL → owner/name
│   ├── State/
│   │   ├── AppStateStore.swift       # AppState + state.json: seen, collapsed, known items and sources, notified; tolerant, versioned
│   │   └── ResolvedRepositoriesStore.swift # repositories.json: each project's repositories as last resolved, written by the app, read by the CLI; fails safe
│   ├── Menu/
│   │   ├── MenuModel.swift           # pure: sections of groups, from listings; semantic state colours, label
│   │   ├── Arrangement.swift         # pure: group, sort, cap: RowGroup
│   │   ├── PanelText+Groups.swift    # pure: group titles, date buckets, "Show 3 more", "Show less"
│   │   ├── MenuTabs.swift            # pure: the tabs layout's tabs, their counts, the selection's fallback to All, the tab beside one (←/→), a tab's rows as its arrangement groups them, All by kind
│   │   ├── RowHighlight.swift        # pure: which row, project header or subheader a layout highlights, from the pointer and the arrow keys (wrap, ←/→ fold), the rows it can rest on, what Return acts on
│   │   ├── RowScroll.swift           # pure: how far the list scrolls to keep the keys' highlight in view, clear of the pinned header; a wrap to the far end, followed until its row lands (RowWrapLanding)
│   │   ├── MeasuredHeight.swift      # pure: the height a measured scroll view takes: its content's, capped, changed only by half a point or more, so a lazy stack's estimates can't loop the panel's layout
│   │   ├── HoverHelpPlacement.swift  # pure: where the hover help card sits: under or over the hovered view, never on it, inside the panel
│   │   ├── PanelText.swift           # pure: the header's account or "Shipyard", row age and second line, a state's word and the state icon's VoiceOver label, tab titles and summary, "Last updated N min ago", config error and warnings, fetch error, refresh-delay and notifications-off banners, rate-limit lines
│   │   ├── PanelText+RowCard.swift   # pure: a row's hover card (`RowCard`): its facts, attention reasons and their words
│   │   ├── PanelText+Connect.swift   # pure: the connect screen's words
│   │   ├── PanelText+ProjectPicker.swift  # pure: the picker's words, its Add button and summary
│   │   ├── PanelText+PresetPicker.swift   # pure: the preset step's words and its button
│   │   ├── PanelText+SkillInstall.swift   # pure: the skill install card
│   │   └── PanelText+CLILink.swift   # pure: the CLI link card
│   ├── Onboarding/
│   │   ├── ProjectChoices.swift      # pure: the picker's offered and chosen repositories, names and grouping → [NewProject]
│   │   └── PresetChoice.swift        # pure: the chosen preset and what it still needs before Add
│   └── Skill/
│       ├── SkillInstaller.swift      # runs npx skills add in the login shell (ShellRunning port, cancellable), SkillInstallResult
│       └── SkillInstallation.swift   # one install as the panel shows it: running, result, timeout, cancel
├── Sources/ShipyardCLI/main.swift    # the `shipyard` executable: gathers arguments, environment and paths, prints ShipyardCLI.run's result
├── Sources/ShipyardApp/              # macOS app (module ShipyardApp, executable Shipyard): thin Apple-framework layer over ShipyardCore
│   ├── ShipyardApp.swift             # @main, MenuBarExtra wiring; AppServices builds the core with the adapters below, routes notification clicks, holds the panel's actions and closes the menu after opening something
│   ├── ConfigWatcher.swift           # watches the config directory (and file), calls Shipyard.reloadConfiguration(); watches the ping store's directory too, calling reloadPings()
│   ├── Wake.swift                    # NSWorkspace wake → refresh trigger
│   ├── Workspace.swift               # ActionRunning on NSWorkspace (open a URL, launch or bring forward an app by bundle id or name); opens config.toml in its editor (TextEdit when none)
│   ├── Keychain.swift                # TokenStore on the login keychain: the app's token store since 0.0.2 (S1)
│   ├── Notifier.swift                # Notifying on UNUserNotificationCenter; permission on first post; click → openNotification
│   ├── LaunchAtLogin.swift           # LoginItem on SMAppService.mainApp: registers or removes the running .app; a repeat, or an item the user switched off in System Settings, is left as it is
│   ├── Brand/
│   │   ├── Sailboat.swift            # shipyard's sailboat, one CGPath (CoreGraphics only): make-icon.swift compiles this file, so the app icon, the menu bar item and the badge draw one figure (#80)
│   │   ├── Logo.swift                # the logo (CoreGraphics only, compiled into make-icon.swift too): the icon's squircle, khaki green gradient, sheen, cream figure colour and the figure's size against the body
│   │   ├── LogoBadge.swift           # the logo as a SwiftUI view: the welcome screens' badge (ConnectView's heading)
│   │   └── SailboatImage.swift       # the menu bar item: a template NSImage of the path
│   └── UI/
│       ├── Panel.swift               # the shared frame: header (the account button, #49), banners, phase switch, layout switch, footer
│       ├── Design.swift              # design tokens: spacing grid, type scale, Palette (state and surface colours, light/dark), motion
│       ├── Components.swift          # shared pieces: measured scroll view (#27), banner, count badge, command box, a row's icon, dots and error row, an item row's click, hover help and highlight (itemRow), Mark seen button, button styles, the row highlight's shape (rowHighlight)
│       ├── HoverHelp.swift           # hoverHelp(_:) in place of .help: the card the panel draws (hoverHelpHost), its timing and style, VoiceOver's hint
│       ├── RowKeys.swift             # the highlight's and keys' plumbing: rows reporting their bounds and spans by tab (highlightable, rowList, RowFrames), the row keys (focus on each open, held-key repeats, scrolling the highlight into view, the list's top and bottom for a wrap or a tab switch)
│       ├── SkillInstallCard.swift    # the skill install: offer, Cancel, result, command to copy
│       ├── CLILinkCard.swift         # the CLI link: offer, linked, what's in the way with the command to copy
│       ├── Components+Groups.swift   # GroupHeader (a subsection's subheader) and ShowMoreRow, shared by both layouts
│       ├── Layouts/
│       │   ├── LayoutActions.swift   # what a layout can do to the menu: open, mark seen, dismiss a ping, mark all seen, collapse, fold a subsection, Show more or less
│       │   ├── ListLayout.swift      # [menu] layout = "list": pinned project headers, one line per item
│       │   └── TabsLayout.swift      # [menu] layout = "tabs": the pill strip, the line under it, a tab's rows as its arrangement groups them, All by kind
│       └── Onboarding/
│           ├── ConnectView.swift     # why signed out, Sign in with GitHub (the code, Cancel), the gh way (gh auth login, Connect with gh, install hint)
│           ├── PresetPicker.swift    # onboarding's first step: choose a preset
│           └── ProjectPicker.swift   # suggestions, a typed repository, names and grouping, Add
├── Tests/ShipyardCoreTests/          # end-to-end through Shipyard + focused tests per pure module
│   ├── Harness.swift                 # the main seam: a Shipyard over the doubles, temp config + app-state dirs, fixture answers, relaunch
│   ├── PullRequestsResponse.swift    # builds a GraphQL answer (PRs and, when asked, issues per repository), for scenarios that change an item between refreshes
│   ├── WorkflowRunsResponse.swift    # builds a REST runs answer (with ETag, or a 304), for scenarios that change runs between refreshes
│   ├── CLI/                          # CLILink in a temporary folder: linking, a link already there, something in the way, no permission, the command run by a shell
│   ├── Pings/                        # the ping command and the CLI as functions; filing by repository; pings end to end: CLI → store → Shipyard → menu
│   ├── Onboarding/                   # ProjectChoices: choosing, typing, naming, grouping; PresetChoice: each preset's next step
│   ├── Skill/                        # the installer against a fake shell, SkillInstallation against a hanging one; the skill document against the code and the schema
│   ├── Fixtures/                     # recorded-shape GitHub responses (GraphQL, REST runs, errors); excluded from the target, read from the source tree
│   └── Doubles/                      # in-memory ports: token store, recording notifier, manual clock, manual refresh timer, recording URL opener, recording login item; stub HTTP transport, fake gh, fake git remote (a fake working folder), fake shell, hanging shell, instant sleeper
└── Tests/ShipyardAppTests/           # macOS only: the app's pure helpers, such as CodeText (a code span monospaced on a chip), and that the menu bar item, badge and icon share the sailboat path, and the badge and the committed icon the logo's colours
```

Shipyard is a macOS app and only ships for macOS. The package has two targets so that the implementation agents, which run on a Linux VPS, can build and test everything holding a rule without a Mac; Linux is a development environment, not a platform shipyard supports. `ShipyardCore` imports only Foundation, FoundationNetworking (on Linux), Observation and TOMLDecoder, all of which exist on Linux (Observation ships with the Swift toolchain; the rule keeps Apple-only frameworks out); the rules live there: configuration, the GitHub client, attention, events, notification rules, the rate budget, the menu model, and the orchestrator itself. It reaches Apple-only services through a few small protocols in `Ports.swift`, and the `ShipyardApp` target supplies them (its module isn't called `Shipyard`, which is the core's orchestrator class): the Keychain, notifications, file watching (`DispatchSource` file-system sources are Darwin-only), wake, login item, and the SwiftUI views. Tests target `ShipyardCore`, so they run on the VPS; the app target is built and checked on macOS, where `ShipyardAppTests` (declared only on macOS, like the app) also tests the few pure helpers that need SwiftUI types, such as `CodeText`.

---

## 4. Implementation

### Shipyard.refresh() — the pipeline

```text
refresh()
  guard phase == ready else return
  guard budget.canRefresh(now) else { rebuildMenu(config); timer.arm(min(interval, until pause ends)); return }   // ⌘R, wake: nothing sent while paused; windows still pass
  guard gate.begin() else return                      // queued; runs again after this one
  config = configStore.lastValid
  configured = config.projects.map(config.settings)   // each project's settings, before its groups and wildcards resolve
  do
    resolved = await resolver.resolve(configured, force: forceResolve, now) { request { github.repositories(of: $0) } }   // 0.0.2: hourly unless forced (launch, config change, ⌘R, sign-in)
    forceResolve = false
    try? repositoriesStore.record(resolved.mapValues(\.repositories))   // 0.0.5: for the shipyard CLI to file pings by repository
    projects = configured.map { $0.resolved(by: resolved[$0.name]) }   // the repositories the known sources and events are about
    snapshot = await request { github.fetch(projects: configured, resolved: resolved, at: clock.now) }   // batches of 25 + the review search; every call goes through request (401 → signedOut)
  catch unauthorized
    phase = signedOut; gate.finish(); return
  catch rateLimited(resetAt, api) / secondaryLimit(retryAfter)
    rebuildMenu(config)   // MenuModel.build(snapshot (or nil: not loaded yet), config, …), keeping fetchError, refreshDelay, rateIndicator
    budget.record(error, now); fetchError = error; menu.fetchError = error; gate.finish(); timer.arm(budget.nextDelay(…)); return
  catch other
    rebuildMenu(config)
    fetchError = other; menu.fetchError = other; gate.finish(); return   // keep old snapshot, rows and lastUpdated
  listings = projects.map { Listing.items(for: $0, in: snapshot, viewer, now) }   // 0.0.2: what each project has
  appStateStore.update { state in                     // saves only if it changed
    events = EventDetector.events(state.known, snapshot, projects)   // first sight of a project's source: none
      + EventDetector.pingEvents(listings, projects)  // 0.0.5: a ping.sent per unseen listed ping
    for id, occurrences in events grouped by id where id ∉ state.notified   // an item in two projects: one event
      if first occurrence listed by its project (listings) and selected by its rules (NotificationRules.shouldNotify)
        toPost.append(NotificationRules.notification(for: it))
      state.notified.insert(id)                         // notified or not, never again
    state.known = state.known.updated(with: snapshot, projects); state.notified.prune(present: known items + pings, now)
    state.attention.prune(present: snapshot items, now)
  }
  self.snapshot = snapshot; fetchError = nil
  budget.record(snapshot.rateLimits, now)
  menu = MenuModel.build(listings, snapshot (errors, fetchedAt), config, appState, expandedGroups, now)   // Panel re-renders from it
  appStateStore.update { $0.collapsedGroups = menu.foldsToKeep($0.collapsedGroups) }   // 0.0.2: a fold whose group or project is gone goes too
  menu.foldedGroups = appState.collapsedGroups
  delay = budget.nextDelay(config.refreshIntervalSeconds, config.rateLimit.maxSharePercent, now)
  menu.refreshDelay = delay; menu.rateIndicator = budget.indicator(config.rateLimit.show, in: [graphql] + [rest if any project shows runs], now)
  for n in toPost: await notifier.post(n)              // after saving: a crash loses one rather than repeating it
  timer.arm(delay.seconds(from: now))
  if gate.finish() then refresh()                     // a queued trigger arrived meanwhile
```

Every fetched item stays known even when its project doesn't list it, so an item a filter change brings into view later doesn't notify as though it were new.

The windows count back from the clock at each listing, not from the fetch, so a closed item leaves on time on its own: every timer firing lists again (after a fetch, after a failed one from the last snapshot, and while paused from the last snapshot without a request), and the timer fires at least every refresh interval (stretched or backed off by the budget, and during a pause at most the configured interval). A `closed-window = "30m"` item is gone within one interval of its 30 minutes passing.

### Listing.items (0.0.2)

```text
items(for project, in snapshot, viewer, now)
  candidates = snapshot items of the project: its resolved repositories', plus the search's PRs when it uses anywhere (the fetch adds them)
  return candidates where
    project.shows(item.kind)
    and kindSettings.states contains item.state.group           // StateGroup: open | merged | closed | in-progress | failed | succeeded
    and inWindow(item, kindSettings, now)                       // closed-window / finished-window, in seconds, counted back from now
                                                                // a ping: unseen, or seen less than pings.seen-window ago (0.0.5)
    and (kind != pullRequest or drafts or not item.isDraft)
    and kindSettings.authors.includes(item.author, viewer)
    and (not reviewRequested or snapshot.reviewRequested contains item.id)
```

### Arrangement.groups (0.0.2)

```text
groups(items, project, settings, layout, folded, expanded, now, calendar)
  buckets = partition items by key(settings.groupBy, item)        // none: one bucket
  for bucket in ordered(buckets)
    rows = bucket sorted (open first, then settings.sortBy)
    id = GroupID(project, key)
    overCap = settings.showFirst > 0 and rows.count > settings.showFirst
    capped = overCap and id not in expanded
    emit RowGroup(id, title(key), rows: capped ? first showFirst : rows,
                  hiddenRows: capped ? the rest : [],             // hiddenCount = hiddenRows.count
                  isExpanded: overCap and id in expanded,          // its row reads Show less
                  showsHeader: settings.subsections ?? layout.subheadersByDefault,
                  isFolded: showsHeader and id in folded,
                  attentionCount: every row's needsAttention, hidden ones too)
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
    configStatusStore.record(accepted)  // unchanged saves too
    shipyard.follow(.changed(config))  // phase may move to/from needsProjects; rebuildMenu(config) from the last snapshot at once (paused or failing too); triggers refresh
  catch e
    error = ConfigError(e, line)       // lastValid untouched
    configStatusStore.record(rejected: each issue with its line and banner text)
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

GraphQL points are GitHub's estimate: roughly the total nodes the query could return ÷ 100, and the nested per-PR lists dominate it. To keep it low, the head commit is asked for `last: 1` and closed items for `first: 20`; 0.0.1 also read each PR's `reviewRequests` (`first: 10`), which 0.0.2's single review search (one page of 100 PRs, in the first batch) replaces. The 5-repository row is measured with `rateLimit(dryRun: true)` against the query shape above; the others scale it. The real cost comes back in `rateLimit.cost` on every response, and `RateBudget` uses the measured figure, not this table. So a user with 10 repositories gets their 2 minutes; a user with 40 gets about 7 minutes and a panel line "Refreshing every 7 min to stay within 10% of your GraphQL rate limit (a refresh costs 56 points)".

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
| 2 | directory watch → `ConfigStore` → `Configuration.decode` throws `unknownEvent("pr.openned", line 14)` | `lastValid` unchanged, `error` set; `config-status.json` says `"accepted": false` with the problem at line 14 and the file's modification time |
| 3 | `Panel` | banner: "config.toml line 14: unknown event `pr.openned` (did you mean `pr.opened`?). Using the last valid configuration." |
| 4 | refreshes keep running with `lastValid` | list unchanged |
| 5 | agent reads `config-status.json`, fixes the file, reads it again | `error = nil`, banner gone, record says `"accepted": true` for the new modification time, refresh triggered |

### Trace 4: `incoming-contributions` with `owned` (0.0.2, happy path)

| Step | State after |
|---|---|
| Onboarding: choose `incoming-contributions` with "all my repositories" | `writePreset` writes the file; the reload has "Incoming" (`owned`) and "Review requests" (`anywhere`); phase `ready` |
| `refresh()`: the resolver pages `viewer.repositories(affiliations: OWNER, isArchived: false)` | "Incoming" resolves to 14 repositories; `anywhere` to none |
| `fetch`: one batch of 14 aliases plus the review search | the snapshot has 40 items; `reviewRequested` has 3 PRs, 2 in other people's repositories |
| `Listing`: "Incoming" drops the 31 items by `me` and 2 by `dependabot[bot]`; "Review requests" takes the 3 search PRs | listings of 7 and 3 |
| `EventDetector`: first sight of every source | no events, nothing notified (bootstrap) |
| `MenuModel` + `Arrangement`: group by repository, subsections | "Incoming" shows 4 repository subheaders; the menu bar counts 10 listed items, not 40 |
| Next refresh: someone opens a PR on one of the user's repositories | `pr.opened` from `others`, listed, so it notifies |

### Trace 5: `anywhere` misused (0.0.2, rejection)

| Step | State after |
|---|---|
| An agent writes `repositories = ["anywhere"]` with `issues = { show = true }` | `ConfigurationReader` records "line 12: `anywhere` needs `pull-requests = { review-requested = true }`, and lists no issues or runs" |
| `reloadConfiguration()` | `configError` set; the last valid configuration keeps running; `config-status.json` says `accepted: false` with the line |
### Trace 6: an agent pings, from the CLI to a click (0.0.5)

Setup: projects `shop` (`repositories = ["yahyabedirhan/shop"]`) and `blog`, the default notification rules, `[herdr] terminal = "Ghostty"`. The app is running; its last refresh listed one PR in `shop`, attention count 1. An agent works in a clone of `yahyabedirhan/shop`, in Herdr pane `w1:p3`, and needs the user's answer.

| Step | Call (owner) | State after |
|---|---|---|
| 1 | agent runs `shipyard ping "Waiting for your input" --from claude --herdr --id cache-question` → `ShipyardCLI.run` (CLI/) | `config.toml` read (projects `shop`, `blog`), and `repositories.json` (the lists the app last resolved) |
| 2 | `PingCommand.Request.parse` (Pings/) | title, sender `claude`, id `cache-question`; `--id` isn't shaped like a Herdr id, so `--herdr` takes `HERDR_PANE_ID`: action `.herdr("w1:p3")` (N11) |
| 3 | `GitCLI.origin(in:)` → `GitRemote.repository(fromURL:)` → `PingCommand.watchers(of:)` | `git@github.com:yahyabedirhan/shop.git` → `yahyabedirhan/shop`; `shop` names it, so the ping is filed under `[shop]` with that repository (N6) |
| 4 | `PingStore.save` | `cache-question` isn't stored: a new ping, `sent` now, a new `instance`; `Pings/cache-question.json` written atomically; prints `cache-question`, exit 0 (N1, N12) |
| 5 | `ConfigWatcher` on the store's directory → `Shipyard.reloadPings()` → `listPings()` | `pings` has the new one; no GitHub request (N4) |
| 6 | `Listing.listings(…, pings:)` → `MenuModel.build` → `Arrangement` | `shop` lists the PR, then a "Pings" group with the ping: a terminal icon, "claude" on its second line; unseen, so it needs attention; count **2** (N3, N8) |
| 7 | `EventDetector.pingEvents` → `NotificationRules` (the default rules hold `ping.sent`) → `AppStateStore.update` → `Notifier.post` | `notified` has `ping.sent` for `shipyard://ping/cache-question` with its `instance`; banner "shop · Waiting for your input" over "from claude" (N7) |
| 8 | ten minutes on, the agent sends the same command titled "Still waiting (10 min)" → steps 1–5 again | a replace: the stored `sent` and `instance` kept, the new title; the row shows it; still count **2**, and `pingEvents`' event is already in `notified`, so no second banner (N12) |
| 9 | user clicks the banner → `Shipyard.openNotification` → `runAction(ofPing:)` → `runHerdr`: `HerdrFocus.focus("w1:p3")` (`herdr pane get w1:p3` → tab `w1:t1` → `herdr tab focus w1:t1`) → `done` → `ActionRunning.run(.app("Ghostty"))` → `done` → `markPingsSeen` | Herdr shows the agent's tab and Ghostty comes forward; `seen` set in the ping's file; count **1**, and still after a relaunch (N8, N11) |
| 10 | the user answers in the pane; the agent runs `shipyard ping withdraw cache-question` → `PingCommand.withdraw` → `PingStore.remove` | prints `cache-question`, exit 0; reads no `config.toml` (N12) |
| 11 | `reloadPings()` → `listPings()` → `forgetLeftPings` → `removeLeftBanners` → `Notifier.removeDelivered` | the row leaves `shop`; the banner leaves Notification Center; the `ping.sent` record is forgotten, so `cache-question` sent again later is a new ping that notifies again (N12) |

Had the agent not withdrawn it, the seen ping would stay listed for `shop`'s `seen-window` (24 h), then leave the listing and the store at the next refresh or store change (N9). The other ways through:

| Variant | What happens |
|---|---|
| `--open https://claude.ai/artifact/42` or `--app Claude` instead of `--herdr` | the row shows a link or app icon; a click runs `ActionRunning.run(.url(…))` or `.app("Claude")` through the action port, then `markPingsSeen` (N8) |
| the action fails: the pane closed (`failed("Herdr pane w1:p3 is gone")`) or no app named Claude | `PingStore.recordFailure`; the ping stays unseen, count **2**; its row reads the reason in red until the next click that works, ⌥-click, Mark all seen or a dismiss (N8) |
| no action | a click only marks it seen (N8) |
| ⌥-click, Mark all seen | marked seen, no action run (N3, N9) |
| the ✕ on the highlighted row, or ⌫ | `Shipyard.dismiss` → `PingStore.remove`; it leaves every project at once, banner and record as in step 11 (N9) |
| the app isn't running at step 4 | the file waits in the store; at launch the pings are listed (and notified) before GitHub answers (N4) |
| `--project shopp` | exit 1: "no project is named `shopp`; the projects are `shop`, `blog`"; nothing written (N1) |
| a folder whose `origin` no project watches, or no `origin` | exit 1, saying so, with `--repo`/`--project` as the way out and the projects listed; nothing written (N6) |
| `--herdr` alone outside Herdr, two action flags, `--repo` with `--project`, an id that isn't one | exit 2, one line on standard error; nothing written (N8, N11, N12) |
| `shipyard ping withdraw cache-question` after the user dismissed it | exit 1: "no ping has the id `cache-question`; …" (N12) |

### Trace 3: agents drain the limit (rejection by budget)

Setup: 10 repositories, one refresh measured at 14 GraphQL points. Several agents are running `gh` heavily.

| Step | Call (owner) | State after |
|---|---|---|
| 1 | refresh → `fetch` returns `graphql.remaining = 900 / 5,000` (18%) | snapshot fine |
| 2 | `RateBudget.nextDelay(120, 10%)` | below 20% → `backedOff(600 s)` |
| 3 | `Panel` | amber footer `GraphQL 900 / 5,000 · resets 16:42`, banner "Your GraphQL rate limit is low (other tools are using it). Refreshing every 10 min." |
| 4 | agents keep going; next refresh gets 403, `x-ratelimit-remaining: 0`, `x-ratelimit-reset` = 16:42 | `pausedUntil = 16:42`, `fetchError = rateLimited` |
| 5 | menu bar icon shows the paused glyph; ⌘R does nothing and says why | last snapshot still listed, "Last updated 14 min ago" |
| 6 | every 120 s meanwhile the timer lists again from the last snapshot, sending nothing; 16:42: the firing at `pausedUntil` refreshes | quota back to 5,000; next delay 120 s; banner gone |

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
| A new author group (e.g. `agents`) | `AuthorSelector` (a case and its match), the schema, the skill |
| `assigned` or `mentioned` | a field on the kind's settings, one check in `Listing`, the query field |
| Deployments waiting on approval | a `workflow-runs` field, a REST call in `WorkflowRuns`, one check in `Listing` |
| A new `group-by` (e.g. `label`) | a case in `Arrangement`'s key and title, the schema, the skill |
| Oldest first | a `sort-by` choice in `Arrangement`, the schema |
| A new preset | `Presets.swift` and `skills/shipyard/presets.md` (the test compares them) |
| Another ping action | a `PingAction` case (its coding key) and its `PingIcon`, `PingCommand.actionFlags` and its parse case, `PanelText.fact`/`stateLabel`, `Palette.symbol(PingIcon)`, and either the app's `WorkspaceActions.run` (what `NSWorkspace` does) or, like Herdr's (#101), a core runner `Shipyard.runAction(ofPing:)` calls |
| Another CLI command | a case in `ShipyardCLI.run` and its own core function |
| The picker offering more groups | `PresetChoice` and `PresetPicker` only |

Refused for now: a plugin system for item kinds (one registration seam for a change that happens rarely), a protocol over `GitHubClient` for other forges (one implementation), a CLI for the configuration (ADR 0001; the 0.0.5 CLI sends pings only, ADR 0004), multi-account support. Since 0.0.2 also: a filter expression language (independent fields with AND cover every case, and agents can write them; ADR 0003), nested grouping (a second level of folds, keys and layout), reading resolved repositories back at launch (resolving costs a few points once an hour; since 0.0.5 they're written for the CLI only), and a plugin seam for filters (each is a field and one line in `Listing`).

---

## Decisions taken in review
- **0.0.2, review requests come from one search** (`review-requested:@me`), not from each PR's review requests: it includes team requests, answers `anywhere` in the same request, and costs one search per refresh. Cost accepted: GitHub's search index can lag a PR by a short while, and it returns at most 100.
- **0.0.2, `subsections` unset keeps each layout's look**: the list's dividers and the tabs' subheaders, so no existing menu changes; a value set applies to both.

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
