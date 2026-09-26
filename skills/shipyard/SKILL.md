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

## Editing it

1. Read the whole file: the user writes comments in it and edits it by hand. Change or add only the lines the request needs, keeping every comment, blank line and the existing order.
2. Put what you add where TOML reads it:
   - A top-level key (`refresh-interval-seconds`, `hide-authors`, …) goes **above the first `[table]` header**: below one, TOML reads it as a key of that table.
   - A table (`[menu]`, `[menu-bar]`, `[rate-limit]`, `[attention]`, `[defaults.issues]`, …) goes **above the first `[[projects]]` block**, once: when the table already exists, add the key to it. A table header written twice is invalid TOML.
   - A new project is a `[[projects]]` block **appended at the end** of the file.
   - A project's overrides (`pull-requests`, `issues`, `workflow-runs`, `notifications`) go **inside its own block** as inline tables, so each block stays self-contained.
   - An inline table `{ … }` stays on one line; an array `[ … ]` may span lines.
   - A file the app created starts with a header showing the common settings as commented-out TOML at their defaults: `hide-authors`, `[menu] layout`, `[menu-bar] count`, `[defaults.issues]` and `[defaults.workflow-runs]` `show`, a `[[defaults.notifications]]` rule and `[rate-limit] max-share-percent`. To set one, uncomment its lines (the table line with its keys) and change the value rather than adding a second copy. The header puts top-level keys above its tables, so any of them can be uncommented; in a file edited since, check that no top-level key sits below the table line you uncomment, which would pull that key into the table.
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
| `hide-authors` | `[]` | logins, e.g. `"dependabot[bot]"`; matched ignoring case; their items are never listed or notified |

Tables:

| Key | Default | Allowed |
|---|---|---|
| `[menu-bar] count` | `"total"` | `"total"`, `"per-kind"` (PRs, issues, runs apart), `"none"` |
| `[menu] layout` | `"list"` | `"list"` (every project in one scrolling list, one line per item), `"tabs"` (one project at a time) |
| `[rate-limit] show` | `"always"` | `"always"`, `"when-low"` (below 25%), `"never"` |
| `[rate-limit] max-share-percent` | `10` | `1`–`50`: the share of each hourly GitHub limit shipyard may spend (it's shared with the user's agents) |
| `[attention] unseen` | `true` | an item not clicked yet needs attention |
| `[attention] changed` | `true` | an item that changed since it was clicked needs attention |
| `[attention] review-requested` | `true` | a PR requesting the user's review needs attention |
| `[attention] checks-failed` | `true` | a PR (or run) whose checks failed needs attention |

What every project shows, set in `[defaults.pull-requests]`, `[defaults.issues]` and `[defaults.workflow-runs]` (and `[[defaults.notifications]]`), and what a project may override in its own block:

| Key | Default | Allowed |
|---|---|---|
| `pull-requests.show` | `true` | boolean |
| `pull-requests.closed-window-days` | `7` | `0` or more; days closed and merged PRs stay listed; `0` hides them |
| `pull-requests.drafts` | `true` | boolean; list draft PRs |
| `issues.show` | `false` | boolean |
| `issues.closed-window-days` | `7` | `0` or more |
| `workflow-runs.show` | `false` | boolean |
| `workflow-runs.finished-window-hours` | `3` | `0` or more; hours finished runs stay listed (running ones always are) |
| `workflow-runs.branches` | `"default-and-pull-requests"` | or `"all"` |
| `notifications` | one rule: `pr.opened`, `any` | a list of rules (below) |

A project, one `[[projects]]` block each, shown as sections in file order:

| Key | Required | Allowed |
|---|---|---|
| `name` | yes | non-empty, unique across projects; the section's title |
| `repositories` | yes | at least one `owner/name` slug: the owner is letters, digits and `-`; the name adds `_` and `.`; no URLs |
| `pull-requests`, `issues`, `workflow-runs` | no | inline tables with the keys above |
| `notifications` | no | a list of rules |

## Overrides

- A project's `pull-requests`, `issues` and `workflow-runs` tables merge **key by key** onto `[defaults.*]`: `issues = { show = true }` shows issues and keeps the default `closed-window-days`.
- A project's `notifications` **replaces** the default list for that project; it doesn't add to it. Repeat any default rule the project should keep. `notifications = []` means no notifications for that project.
- `[[defaults.notifications]]` blocks likewise replace the built-in default (`pr.opened`, `any`): once the file has one, write the `pr.opened` rule too if it should stay.

## Notification rules

A rule, one element of a `notifications` list, is `{ event = "…", authors = "…" }`; `authors` defaults to `"any"`. An event is notified when a rule in the project's list names it and its author filter matches the item's author. Each event is notified once, and a project's existing items never notify when it's added.

| Event | When |
|---|---|
| `pr.opened` | a new pull request is listed open (drafts too) |
| `pr.merged` | an open pull request was merged |
| `pr.closed` | an open pull request was closed without merging |
| `pr.reopened` | a closed pull request was reopened |
| `pr.review_requested` | an open pull request newly requests the user's review |
| `pr.checks_failed` | an open pull request's checks newly failed |
| `pr.commented` | a pull request got comments or reviews |
| `issue.opened` | a new issue is listed open |
| `issue.closed` | an open issue was closed |
| `issue.commented` | an issue got comments |
| `run.failed` | a workflow run finished failed (also timed out or failed to start) |
| `run.succeeded` | a workflow run finished successfully |

Issue events need the project to show issues, and run events to show workflow runs.

| Authors | Covers |
|---|---|
| `any` | everyone |
| `me` | the signed-in user, which includes agents working as them |
| `others` | anyone but the user and bots |
| `bots` | a GitHub Bot account or a login ending in `[bot]` |

## Checking an edit

**The schema.** Run [Taplo](https://taplo.tamasfe.dev) on the file and print its exit status; it finds the schema through the `#:schema` line:

```sh
taplo check ~/.config/shipyard/config.toml; echo "taplo exit status: $?"
```

Exit status 0 is a pass; anything else is a fail, and the lines above it say why. Don't pipe the output through `tail`, `grep` or `head`: on success Taplo prints only an INFO line, and a pipe hides the exit status. Without Taplo installed, run `npx -y @taplo/cli check <file>` the same way, or `brew install taplo`. When the file has no `#:schema` line, or its schema URL can't be fetched, pass `--schema <url>` with the schema URL above (a local copy works as `file://<absolute path>`). The schema is stricter than the app about unknown keys: it rejects what the app would only warn about and ignore, so fix those too.

The schema can't check three rules; check them by reading the file:

- Every project `name` is used once.
- A project lists each repository once, ignoring case (`owner/name` and `Owner/Name` are the same repository).
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

**"Notify me when others open PRs here."** Give that project its own list (it replaces the defaults; see Overrides):

```toml
[[projects]]
name = "shipyard"
repositories = ["yahyabedirhan/shipyard"]
notifications = [
  { event = "pr.opened", authors = "others" },
]
```

For every project instead, write `[[defaults.notifications]]` blocks.

**"Hide dependabot."** A top-level key; add to the list when it exists. Use the login as GitHub shows it, `[bot]` suffix included:

```toml
hide-authors = ["dependabot[bot]"]
```

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
