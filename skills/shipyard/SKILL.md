---
name: shipyard
description: "Edit shipyard's config.toml, the macOS menu bar app listing pull requests, issues and workflow runs. Use when asked to change my shipyard or the shipyard app (its layout, projects, notifications, what it shows): watch or group repositories, show or hide issues, runs, drafts or someone's items, switch the menu between a list and tabs, change when it notifies, or fix its configuration file."
---

# shipyard configuration

Shipyard lists the pull requests (and, when turned on, issues and workflow runs) of the **projects** in one TOML file, and sends macOS notifications for the **events** its **notification rules** select. That file is the whole interface: there is no CLI and no settings window. The app applies every save live.

A request to change the user's shipyard is a change to this file. When no key below does what's asked, say that shipyard has no such setting.

## The file

- Path: `$XDG_CONFIG_HOME/shipyard/config.toml` when `XDG_CONFIG_HOME` is set to an absolute path, else `~/.config/shipyard/config.toml`.
- Every key is optional. A missing or empty file means the defaults with no projects (the app then shows its project picker).
- The app writes to the file itself in two ways only: its project picker appends `[[projects]]` blocks, and the layout button in the menu's header sets `layout` under `[menu]` to the next layout in turn (list, then tabs, then list again), keeping every other line. So read the file afresh before each edit.
- Keys are kebab-case. The schema is `https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json`, named by the file's first line, `#:schema <url>`.

## Starting from a preset

Shipyard has three **presets**, ready-made files for its main uses; the app offers them when it's set up, and [presets.md](presets.md) has each one's whole file:

- `my-agents`: the pull requests and issues the user and their agents open, one project per repository.
- `incoming-contributions`: what other people open on the user's repositories, bots hidden, plus the pull requests waiting on their review anywhere.
- `review-queue`: only the pull requests waiting on the user's review, in any repository.

Start from a preset when the user names one, or asks to set shipyard up (or start over) for one of these uses, and the file is missing or holds nothing live but `version`: write the preset's file with the user's repositories, as presets.md says. When the file already has settings or projects, don't replace it: make the change the request needs with the keys below.

## Editing it

1. Read the whole file: the user writes comments in it and edits it by hand. Change or add only the lines the request needs, keeping every comment, blank line and the existing order.
2. Put what you add where TOML reads it:
   - A top-level key (`refresh-interval-seconds`, `launch-at-login`, …) goes **above the first `[table]` header**: below one, TOML reads it as a key of that table.
   - A table (`[menu]`, `[menu-bar]`, `[rate-limit]`, `[attention]`, `[defaults.issues]`, …) goes **above the first `[[projects]]` block**, once: when the table already exists, add the key to it. A table header written twice is invalid TOML.
   - A new project is a `[[projects]]` block **appended at the end** of the file.
   - A project's overrides (`pull-requests`, `issues`, `workflow-runs`, `notifications`) go **inside its own block** as inline tables, so each block stays self-contained.
   - An inline table `{ … }` stays on one line; an array `[ … ]` may span lines.
   - A file the app created starts with a header showing the common settings as commented-out TOML at their defaults: `[defaults.pull-requests] authors`, `[menu] layout`, `[menu-bar] count`, `[defaults.issues]` `show` and `states`, `[defaults.workflow-runs]` `show`, a `[[defaults.notifications]]` rule and `[rate-limit] max-share-percent`. To set one, uncomment its lines (the table line with its keys) and change the value rather than adding a second copy. The header puts top-level keys above its tables, so any of them can be uncommented; in a file edited since, check that no top-level key sits below the table line you uncomment, which would pull that key into the table.
3. The app creates the file with that header whenever it starts, or its Refresh button is clicked, without one. When it still doesn't exist, create it (and its directory) starting with:

   ```toml
   #:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json
   version = 1
   ```

4. Check the edit (see Checking an edit). It is done when `taplo check` exits 0, the rules it can't check hold, and the app's record says `"accepted": true` for your save.

## Keys and defaults

Top level:

| Key | Default | Allowed |
|---|---|---|
| `version` | `1` | only `1` |
| `refresh-interval-seconds` | `120` | whole number, at least `30`; a floor the app stretches to stay within its rate-limit share |
| `launch-at-login` | `true` | boolean |

`hide-authors` (a top-level list of logins) is the old way to hide authors. The app still reads it, as a `hide` in each kind's defaults, with a warning; replace it with `authors` (see Whose items).

Tables:

| Key | Default | Allowed |
|---|---|---|
| `[menu-bar] count` | `"total"` | `"total"`, `"per-kind"` (PRs, issues, runs apart), `"none"` |
| `[menu] layout` | `"list"` | `"list"` (every project in one scrolling list, one line per item), `"tabs"` (one project at a time) |
| `[rate-limit] show` | `"always"` | `"always"`, `"when-low"` (below 25%), `"never"` |
| `[rate-limit] max-share-percent` | `10` | `1`–`50`: the share of each hourly GitHub limit shipyard may spend (it's shared with the user's agents) |
| `[attention] unseen` | `true` | an item not clicked yet needs attention |
| `[attention] changed` | `true` | an item that changed since it was clicked needs attention |
| `[attention] review-requested` | `true` | a PR requesting the user's review (or a team's they're in) needs attention |
| `[attention] checks-failed` | `true` | a PR (or run) whose checks failed needs attention |

What every project shows, set in `[defaults.pull-requests]`, `[defaults.issues]` and `[defaults.workflow-runs]` (and `[[defaults.notifications]]`), and what a project may override in its own block:

| Key | Default | Allowed |
|---|---|---|
| `pull-requests.show` | `true` | boolean |
| `pull-requests.states` | `["open", "merged", "closed"]` | which PRs are listed: any of `"open"` (drafts too), `"merged"`, `"closed"` (closed without merging) |
| `pull-requests.closed-window-days` | `7` | `0` or more; days closed and merged PRs stay listed; `0` hides them |
| `pull-requests.drafts` | `true` | boolean; list draft PRs |
| `pull-requests.authors` | `{ show = [], hide = [] }` | whose PRs are listed: `authors.show` minus `authors.hide`, each a list of author selectors (see Whose items) |
| `pull-requests.review-requested` | `false` | boolean; `true` lists only open PRs waiting on the user's review, requested from them or from one of their teams |
| `issues.show` | `false` | boolean |
| `issues.states` | `["open", "closed"]` | which issues are listed: any of `"open"`, `"closed"` |
| `issues.closed-window-days` | `7` | `0` or more |
| `issues.authors` | `{ show = [], hide = [] }` | whose issues are listed, as for pull requests |
| `workflow-runs.show` | `false` | boolean |
| `workflow-runs.states` | `["in-progress", "failed", "succeeded"]` | which runs are listed: any of `"in-progress"` (queued or running), `"failed"` (timed out and failed to start too), `"succeeded"` |
| `workflow-runs.finished-window-hours` | `3` | `0` or more; hours finished runs stay listed (running ones always are) |
| `workflow-runs.branches` | `"default-and-pull-requests"` | or `"all"` |
| `workflow-runs.authors` | `{ show = [], hide = [] }` | whose runs are listed (a run's author is the account that started it) |
| `notifications` | one rule: `pr.opened`, `authors = []` | a list of rules (below) |

How every project's items are grouped and sorted in the menu, set straight under `[defaults]` (not in a sub-table), and what a project may override in its own block:

| Key | Default | Allowed |
|---|---|---|
| `[defaults] group-by` | `"kind"` | `"kind"` (pull requests, then issues, then runs), `"repository"` (A to Z), `"date"` (Today, Yesterday, This week, This month, Older), `"author"` (A to Z), `"none"` (one list); one level only |
| `[defaults] subsections` | unset | boolean: `true` draws each group under a subheader (its name and count), `false` after a divider line; unset keeps each layout's own look (dividers in the list, subheaders in tabs) |
| `[defaults] sort-by` | `"updated"` | `"updated"` (newest first), `"created"` (newest first), `"title"` (A to Z); open or running items always come first. `"date"` groups by this date (`"updated"` when sorting by title) |
| `[defaults] show-first` | `0` | a whole number, 0 or more: each group shows its first N rows and a "Show N more" row, which reveals the rest and then reads "Show less"; `0` shows every row. With `group-by = "none"` it caps the whole project. A group's count includes the rows it hides, and every cap comes back when the menu closes |

The All tab of the tabs layout always groups by kind, newest first.

What repository groups and `owner/*` bring in (see Which repositories), set in `[defaults]` and in a project's block:

| Key | Default | Allowed |
|---|---|---|
| `[defaults] archived` | `false` | boolean; `true` brings in archived repositories too |
| `[defaults] forks` | `true` | boolean; `false` leaves forks out |

A project, one `[[projects]]` block each, shown as sections in file order:

| Key | Required | Allowed |
|---|---|---|
| `name` | yes | non-empty, unique across projects; the section's title |
| `repositories` | yes | at least one repository selector: `owner/name`, `owner/*`, `owned`, `organizations`, `collaborator` or `anywhere` (see Which repositories); no URLs |
| `pull-requests`, `issues`, `workflow-runs` | no | inline tables with the keys above |
| `group-by`, `subsections`, `sort-by`, `show-first` | no | as under `[defaults]` above |
| `archived`, `forks` | no | booleans, overriding `[defaults]` for this project |
| `notifications` | no | a list of rules |

## Overrides

- A project's `pull-requests`, `issues` and `workflow-runs` tables merge **key by key** onto `[defaults.*]`: `issues = { show = true }` shows issues and keeps the default `closed-window-days`. A list such as `states` is one key: the project's list replaces the default's. `authors` merges key by key too: a project's `authors = { hide = [...] }` replaces the default `hide` and keeps the default `show`.
- A project's `notifications` **replaces** the default list for that project; it doesn't add to it. Repeat any default rule the project should keep. `notifications = []` means no notifications for that project.
- `[[defaults.notifications]]` blocks likewise replace the built-in default (`pr.opened`, from everyone): once the file has one, write the `pr.opened` rule too if it should stay.

## Which repositories: repository selectors

A project's `repositories` lists **repository selectors**, in any mix. The syntax is the author selectors' (below): a bare word is a group, and `/` marks a repository.

| Selector | Watches |
|---|---|
| `owner/name` | one repository: the owner is letters, digits and `-`; the name adds `_` and `.` |
| `owner/*` | every repository a user or organization owns, e.g. `my-org/*` |
| `owned` | every repository the signed-in account owns |
| `organizations` | every repository the account reaches through an organization it's a member of, directly or through a team |
| `collaborator` | someone else's repositories that added the account as a collaborator |
| `anywhere` | open pull requests waiting on the user's review in any repository, even one the user has never committed to |

- `owned`, `organizations` and `collaborator` are GitHub's own affiliations: they don't overlap, and together they are every repository the account can reach. There's no `me/*`: write `owned`.
- Groups and wildcards are looked up when the app starts, after each edit, on ⌘R and otherwise about once an hour, so a repository created later shows up without editing the file. Its existing items are listed quietly; only what happens after notifies.
- They leave out archived repositories and keep forks, unless `archived = true` or `forks = false` says otherwise. A repository named as `owner/name` is always listed, archived or not.
- A repository that two selectors bring in is listed once.
- An `owner/*` whose owner doesn't exist, or that the account can't see, shows an error row in the project; a group with no repositories shows "Nothing open".
- An author group (`me`, `others`, `bots`) or an `@login` in `repositories` is rejected with a hint: to watch someone's repositories, write `owner/*`.
- `anywhere` comes from one GitHub search, not from repositories, so it works only in a project that lists pull requests with `review-requested = true` and shows no issues or runs (in its block or its defaults). Anything else is rejected: "`anywhere` needs `pull-requests = { review-requested = true }`, and lists no issues or runs". The project's other filters (`authors`, `states`, `drafts`) apply as usual. The search returns at most 100 pull requests; when more are waiting, the project says so.

## Which items: states

Each kind's `states` picks its items by where they stand; what it leaves out isn't shown, counted or notified. The closed windows still apply: `states` says which items, `closed-window-days` (or `finished-window-hours`) how long a closed, merged or finished one stays. So `pull-requests = { states = ["open"] }` lists no merged or closed PRs at all, and `states = ["merged"]` lists PRs merged in the last `closed-window-days`. A state the kind doesn't take is rejected with the nearest one it does: "unknown pull request state `merge` (did you mean `merged`?)". `states = []` lists none of the kind's items; to hide a kind, `show = false` says so more plainly.

## Whose items: author selectors

Each kind's `authors = { show = [...], hide = [...] }` decides whose items a project lists. An item is listed when its author matches `show` (an empty `show` is everyone) and doesn't match `hide`; `hide` wins when both match. Set it for every project in `[defaults.pull-requests]`, `[defaults.issues]` or `[defaults.workflow-runs]`, or for one project inside its block. Pull requests, issues and runs each have their own; hiding someone everywhere means hiding them in each kind the projects show.

What a project's filters leave out is gone from shipyard: it isn't shown, counted in the menu bar, the project's header or a tab, nor notified. Every fetched item is still remembered, so when a later edit brings an item into view it isn't notified as new.

The entries of `show` and `hide`, and of a notification rule's `authors`, are **author selectors**. The syntax is small: **a bare word is a group, `@` marks a person, `/` marks a repository.**

| Selector | Covers |
|---|---|
| `me` | the signed-in user, which includes agents working as them |
| `others` | anyone but the user and bots |
| `bots` | a GitHub Bot account or a login ending in `[bot]` |
| `@login` | one account, e.g. `@octocat` or `@dependabot[bot]` (keep the `[bot]` suffix); matched ignoring case |

`me`, `others` and `bots` together cover every author once. Always write a login with `@`: a bare word that isn't a group is rejected with a hint: "unknown author `bots2` (did you mean `bots` or `@bots2`?)". A repository (`owner/name`) or a repository group is rejected in `authors` too: repositories belong in a project's `repositories`.

## Notification rules

A rule, one element of a `notifications` list, is `{ event = "…", authors = [...] }`; `authors` is a list of author selectors and defaults to `[]`, everyone. An event is notified when a rule in the project's list names it and one of its `authors` matches the item's author. A rule only narrows what the project lists: an item the project's filters leave out (its `states`, `authors`, `drafts`, or a closed window of `0`) is never notified, whatever the rule says; so `pr.merged` needs `merged` in `states` and `closed-window-days` above `0`, and `run.failed` needs `failed` in `states` and `finished-window-hours` above `0`. Each event is notified once, and a project's existing items never notify when it's added.

| Event | When |
|---|---|
| `pr.opened` | a new pull request is listed open (drafts too) |
| `pr.merged` | an open pull request was merged |
| `pr.closed` | an open pull request was closed without merging |
| `pr.reopened` | a closed pull request was reopened |
| `pr.review_requested` | an open pull request newly requests the user's review, or a team's they're in |
| `pr.checks_failed` | an open pull request's checks newly failed |
| `pr.commented` | a pull request got comments or reviews |
| `issue.opened` | a new issue is listed open |
| `issue.closed` | an open issue was closed |
| `issue.commented` | an issue got comments |
| `run.failed` | a workflow run finished failed (also timed out or failed to start) |
| `run.succeeded` | a workflow run finished successfully |

Issue events need the project to show issues, and run events to show workflow runs.

Older files write a rule's `authors` as one string: `"any"`, `"me"`, `"others"` or `"bots"`. The app still reads them, with a warning; when you touch such a rule, write the list instead (`authors = ["others"]`; `"any"` is `[]`, or leave `authors` out).

## Checking an edit

**The schema.** Run [Taplo](https://taplo.tamasfe.dev) on the file and print its exit status; it finds the schema through the `#:schema` line:

```sh
taplo check ~/.config/shipyard/config.toml; echo "taplo exit status: $?"
```

Exit status 0 is a pass; anything else is a fail, and the lines above it say why. Don't pipe the output through `tail`, `grep` or `head`: on success Taplo prints only an INFO line, and a pipe hides the exit status. Without Taplo installed, run `npx -y @taplo/cli check <file>` the same way, or `brew install taplo`. When the file has no `#:schema` line, or its schema URL can't be fetched, pass `--schema <url>` with the schema URL above (a local copy works as `file://<absolute path>`). The schema is stricter than the app about unknown keys: it rejects what the app would only warn about and ignore, so fix those too.

The schema can't check three rules; check them by reading the file:

- Every project `name` is used once.
- A project lists each repository, wildcard and group once, ignoring case (`owner/name` and `Owner/Name` are the same repository).
- Top-level keys sit above the first `[table]` header.

**The app.** Shipyard rereads the file within a moment of each save and writes its verdict to `~/Library/Application Support/Shipyard/config-status.json`. After saving, wait a second, then read the record and the modification time of the file you edited (under `$XDG_CONFIG_HOME` when it is set):

```sh
cat ~/Library/Application\ Support/Shipyard/config-status.json
date -u -r ~/.config/shipyard/config.toml +%Y-%m-%dT%H:%M:%SZ
```

```json
{
  "accepted" : false,
  "checked" : "2026-09-25T12:05:01Z",
  "config" : "/Users/me/.config/shipyard/config.toml",
  "configModified" : "2026-09-25T12:05:00Z",
  "problems" : [
    {
      "banner" : "config.toml line 14: unknown event `pr.openned` (did you mean `pr.opened`?)",
      "line" : 14,
      "message" : "unknown event `pr.openned` (did you mean `pr.opened`?)"
    }
  ],
  "version" : 1,
  "warnings" : []
}
```

- **Is it about your save?** Only when `configModified` equals the `date` output (both UTC, whole seconds) and `config` is the file you edited. When it's older, the app hasn't reread yet: wait a moment and read it again. When it never catches up, shipyard isn't running; say so rather than claiming the app took the edit.
- **`"accepted": true`**: the app took the edit. `warnings` lists settings it ignored, each with its `line`: usually a misspelled key, so fix it.
- **`"accepted": false`**: the app rejected the file and keeps running on the last valid configuration. Fix every entry in `problems` at its `line` (`null` when it can't be placed), save, and read the record again. `banner` is the same line the user sees in the panel's banner, which ends in "Using the last valid configuration.".

The record also catches what only the app checks, including the three rules above.

## Worked requests

**"Watch this repo in shipyard."** Take the `owner/name` slug from the repository's `origin` remote. If a project already lists it, say so and stop. Otherwise append a block named after the repository, unless the user names it:

```toml
[[projects]]
name = "shipyard"
repositories = ["yahyabedirhan/shipyard"]
```

**"Group these repos into one project."** One block lists them all. When some of them are already projects, move their repositories (and any overrides that should apply to the group) into one block and delete the blocks they leave empty; keep the comments that still apply.

```toml
[[projects]]
name = "e-commerce"
repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]
```

**"Watch all my repositories."** One project with the `owned` group; add `organizations` when the user means their organizations' repositories too:

```toml
[[projects]]
name = "mine"
repositories = ["owned"]
```

**"Watch everything in my-org, and my own shipyard."** A wildcard beside a single repository; `archived = true` would bring in the organization's archived repositories as well:

```toml
[[projects]]
name = "my-org"
repositories = ["my-org/*", "yahyabedirhan/shipyard"]
```

**"Notify me when others open PRs here."** Give that project its own list (it replaces the defaults; see Overrides):

```toml
[[projects]]
name = "shipyard"
repositories = ["yahyabedirhan/shipyard"]
notifications = [
  { event = "pr.opened", authors = ["others"] },
]
```

For every project instead, write `[[defaults.notifications]]` blocks.

**"Hide dependabot."** A `hide` in the pull requests' defaults (add to the list when it exists; add the same to `[defaults.issues]` when projects show issues). Write the login with `@`, as GitHub shows it, `[bot]` suffix included. To hide every bot, write `bots` instead.

```toml
[defaults.pull-requests]
authors = { hide = ["@dependabot[bot]"] }
```

When the file still has an old `hide-authors` list, move its logins into these `hide` lists (each with `@`) and delete the `hide-authors` line.

**"Only show what other people open in this project."** Hide `me` and `bots` in each kind the project shows, inside its block:

```toml
[[projects]]
name = "shipyard"
repositories = ["yahyabedirhan/shipyard"]
pull-requests = { authors = { hide = ["me", "bots"] } }
issues = { show = true, authors = { hide = ["me", "bots"] } }
```

For only one account's items (say a project for dependency updates), use `show` instead: `pull-requests = { authors = { show = ["@dependabot[bot]"] } }`.

**"Only show the PRs waiting on my review in this project."** Set `review-requested` in the project's pull requests. A request to one of the user's teams counts too. It leaves the project's issues and runs as they are; turn them off too for a pure review queue:

```toml
[[projects]]
name = "shipyard reviews"
repositories = ["yahyabedirhan/shipyard"]
pull-requests = { review-requested = true }
```

**"Show every PR waiting on my review, wherever it is."** A project with the `anywhere` group; it must list only PRs waiting on the user's review. Grouping by repository keeps many repositories readable, and `pr.review_requested` notifies each new request:

```toml
[[projects]]
name = "review queue"
repositories = ["anywhere"]
pull-requests = { review-requested = true }
group-by = "repository"
subsections = true
notifications = [
  { event = "pr.review_requested" },
]
```

**"Group this project by repository, with a header for each."** Set `group-by` and `subsections` in the project's block (in `[defaults]` for every project):

```toml
[[projects]]
name = "contributions"
repositories = ["yahyabedirhan/shipyard", "yahyabedirhan/skills"]
group-by = "repository"
subsections = true
```

For the most recently opened first, add `sort-by = "created"`; for what changed today at the top, `group-by = "date"`.

**"Keep this project short: show a few of each and let me expand."** Set `show-first` in the project's block (in `[defaults]` for every project). Each group shows that many rows and a "Show N more" row that reveals the rest until the menu closes:

```toml
[[projects]]
name = "contributions"
repositories = ["yahyabedirhan/shipyard", "yahyabedirhan/skills"]
show-first = 5
```

**"Only show open PRs and issues here."** `states` in each kind, inside the project's block:

```toml
[[projects]]
name = "shipyard"
repositories = ["yahyabedirhan/shipyard"]
pull-requests = { states = ["open"] }
issues = { show = true, states = ["open"] }
```

Runs work the same way: `workflow-runs = { show = true, states = ["failed", "in-progress"] }` leaves out the ones that succeeded. For every project, set `states` in `[defaults.pull-requests]` (or `[defaults.issues]`, `[defaults.workflow-runs]`) instead.

**"Switch the menu to tabs."** One key in the `[menu]` table; uncomment the header's `# [menu]` lines where the placement rule allows it. The layout button in the menu's header makes the same edit with one click.

```toml
[menu]
layout = "tabs"
```

**"Show issues for this project."** Add an `issues` override inside the project's block:

```toml
[[projects]]
name = "e-commerce"
repositories = ["yahyabedirhan/e-commerce-frontend", "yahyabedirhan/e-commerce-backend"]
issues = { show = true }
```

To show issues in every project instead, set it once in the defaults:

```toml
[defaults.issues]
show = true
```

**"Show CI runs for this project and tell me when they fail."** A `workflow-runs` override, and a notification list that keeps the default `pr.opened` beside `run.failed`:

```toml
[[projects]]
name = "shipyard"
repositories = ["yahyabedirhan/shipyard"]
workflow-runs = { show = true }
notifications = [
  { event = "pr.opened" },
  { event = "run.failed" },
]
```
