---
name: shipyard
description: Edit shipyard's config.toml, the macOS menu bar app listing pull requests, issues and workflow runs. Use when asked to watch or group repositories in shipyard, show or hide issues, runs, drafts or someone's items, switch the menu between a list and tabs, change when it notifies, or fix its configuration file.
---

# shipyard configuration

Shipyard lists the pull requests (and, when turned on, issues and workflow runs) of the **projects** in one TOML file, and sends macOS notifications for the **events** its **notification rules** select. That file is the whole interface: there is no CLI and no settings window. The app applies every save live.

## The file

- Path: `$XDG_CONFIG_HOME/shipyard/config.toml` when `XDG_CONFIG_HOME` is set to an absolute path, else `~/.config/shipyard/config.toml`.
- Every key is optional. A missing or empty file means the defaults with no projects (the app then shows its project picker).
- Keys are kebab-case. The schema is `https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json`, named by the file's first line, `#:schema <url>`.
- A broken save doesn't blank the app: it keeps the last valid configuration and shows the error, with its line, in its panel. Unknown keys are ignored without a banner, so a misspelled key silently does nothing; the schema catches it.
- A file the app created starts with a commented header that shows settings as commented-out TOML (`# [menu]`, `# layout = "list"`). To set one of those, uncomment its lines and change the value rather than adding a second copy, as long as no top-level key sits below them (see Editing it).

## Editing it

1. Read the whole file first. The user writes comments in it and edits it by hand.
2. Make the **smallest edit** that does the job: change or add only the lines the request needs, and keep every comment, blank line and the order of what's there. Shipyard itself never rewrites the file; its project picker only **appends** `[[projects]]` blocks at the end. Hold edits to the same standard.
3. Put what you add where TOML reads it:
   - A top-level key (`refresh-interval-seconds`, `hide-authors`, …) goes **above the first `[table]` header**: below one, TOML reads it as a key of that table.
   - A table (`[menu]`, `[menu-bar]`, `[rate-limit]`, `[attention]`, `[defaults.issues]`, …) goes **above the first `[[projects]]` block**, once: when the table already exists, add the key to it. A table header written twice is invalid TOML.
   - A new project is a `[[projects]]` block **appended at the end** of the file.
   - A project's overrides (`pull-requests`, `issues`, `workflow-runs`, `notifications`) go **inside its own block** as inline tables, so each block stays self-contained.
   - An inline table `{ … }` stays on one line; an array `[ … ]` may span lines.
4. When the file doesn't exist, create it (and its directory) starting with:

   ```toml
   #:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json
   version = 1
   ```

5. **Check the edit** before you report done (see Checking an edit). The edit is done when `taplo check` passes, the rules it can't check hold, and, when the app is running, its panel shows no configuration error.

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

A rule is `{ event = "…", authors = "…" }`; `authors` defaults to `"any"`. An event is notified when a rule in the project's list names it and its author filter matches the item's author. Each event is notified once, and a project's existing items never notify when it's added.

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

**The schema.** Run [Taplo](https://taplo.tamasfe.dev) on the file; it finds the schema through the `#:schema` line:

```sh
taplo check ~/.config/shipyard/config.toml
```

Without Taplo installed, `npx -y @taplo/cli check <file>` or `brew install taplo`. When the file has no `#:schema` line, pass `--schema <url>` with the schema URL above. The schema is stricter than the app about unknown keys: it rejects what the app would silently ignore, so fix those too.

The schema can't check three rules; check them by reading the file:

- Every project `name` is used once.
- A project lists each repository once, ignoring case (`owner/name` and `Owner/Name` are the same repository).
- Top-level keys sit above the first `[table]` header.

**The app.** Shipyard rereads the file within a moment of each save. When it rejects the file, the top of its panel shows a banner listing each problem with its line, ending in "Using the last valid configuration.", for example:

```text
config.toml line 14: unknown event `pr.openned` (did you mean `pr.opened`?)
Using the last valid configuration.
```

The panel is on the user's screen, not yours: when the user reports that banner, fix the line it names. No banner after a save means the app took the edit.

## Worked requests

**"Watch this repo in shipyard."** Take the slug from the repository's remote (`git remote get-url origin`: `git@github.com:owner/name.git` and `https://github.com/owner/name` are both `owner/name`). If a project already lists it, say so and stop. Otherwise append a block named after the repository, unless the user names it:

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

**"Notify me when others open PRs here."** Give that project its own list. It replaces the defaults for this project, so any other default rule it should keep goes in the list too:

```toml
[[projects]]
name = "shipyard"
repositories = ["yahyabedirhan/shipyard"]
notifications = [
  { event = "pr.opened", authors = "others" },
]
```

To add a rule for every project instead, write `[[defaults.notifications]]` blocks, and keep the default `pr.opened` rule among them (see Overrides).

**"Hide dependabot."** A top-level key, above the first table; add to the list when it exists. Use the login as GitHub shows it, `[bot]` suffix included:

```toml
hide-authors = ["dependabot[bot]"]
```

**"Switch the menu to tabs."** One key in the `[menu]` table. If the file has the header's commented `# [menu]` and `# layout = "list"` lines and no top-level key follows them, uncomment both and set the value. Otherwise add the table below the last top-level key and above the first `[[projects]]` block: uncommenting `# [menu]` above a top-level key would make that key part of `[menu]`.

```toml
[menu]
layout = "tabs"
```

`"list"`, the default, switches it back.

**"Show issues for this project."** Add an `issues` override inside the project's block; its other keys keep their defaults:

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

**"Show CI runs for this project and tell me when they fail."** A `workflow-runs` override turns runs on for this project alone, and its own notification list adds `run.failed` while keeping the default `pr.opened`:

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
