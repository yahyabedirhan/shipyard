# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply / remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically when run inside a clone.

## Efforts

An **effort** is one spec issue and the tickets that build it.

- **Tickets under the spec**: each ticket is a GitHub sub-issue of its spec (`gh api --method POST repos/<owner>/<repo>/issues/<spec>/sub_issues -F sub_issue_id=<ticket-db-id>`), with `## Parent` naming the spec in its body. Moving a ticket to another effort means removing it from the old spec's sub-issues and adding it to the new one's.
- **Order**: GitHub's native "blocked by" dependencies, as described under Wayfinding operations below. A blocking edge may cross efforts.
- **Name**: every effort has a kebab-case name, carried as the label `effort:<name>` on the spec and on every one of its tickets (for example `effort:shipyard-0-0-1` on #1 and its tickets, `effort:sign-in-without-gh` on #22 and its tickets). When publishing a new spec, create its label (`gh label create effort:<name> --color f9d0c4`; every effort label shares this pale brick, since the name tells them apart) and apply it to the spec and each ticket; a ticket moved to another effort swaps its label too. Refer to an effort by this name, and list it with `gh issue list --state all --label effort:<name>`.

## Bugs and screenshots

- A bug found while building or checking the app gets a ticket, labelled `bug`, in the effort it belongs to, and blocks that effort's verification ticket. If an open ticket already owns the behaviour, update that ticket instead.
- Attach a screenshot when it shows the bug. `gh` can't upload images to an issue, so screenshots live on the orphan branch `issue-assets` and the issue embeds their raw URL: `![what it shows](https://raw.githubusercontent.com/yahyabedirhan/shipyard/issue-assets/<name>.png)`. Add a file to that branch without touching the working tree: `git hash-object -w`, then `git mktree` over the branch's current tree plus the new entry, then `git commit-tree` with the branch's head as parent, then `git push origin <commit>:refs/heads/issue-assets`. Run it under `bash -euo pipefail` and check the commit is non-empty first: pushing an empty source (`:refs/heads/issue-assets`) deletes the branch. Embed the commit-pinned URL (`…/shipyard/<commit>/<name>.png`): the branch-name URL can return a cached 404 for a few minutes after a push.
- Agents don't open or click the real menu (see Testing in `AGENTS.md`); screenshots of it come from the maintainer.

## Pull requests as a triage surface

**PRs as a request surface: no.** _(Set to `yes` if this repo treats external PRs as feature requests; `/triage` reads this flag.)_

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments` then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` (drop `OWNER`/`MEMBER`/`COLLABORATOR`).
- **Comment / label / close**: `gh pr comment`, `gh pr edit --add-label`/`--remove-label`, `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either: resolve with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes / Decisions-so-far / Fog body. `gh issue create --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue (`gh api` on the sub-issues endpoint). Where sub-issues aren't enabled, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels: `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed, the ticket is assigned to the driving dev.
- **Blocking**: GitHub's **native issue dependencies**, the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric **database id** (`gh api repos/<owner>/<repo>/issues/<n> --jq .id`, _not_ the `#number` or `node_id`). GitHub reports `issue_dependencies_summary.blocked_by` (open blockers only, the live gate). Where dependencies aren't available, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children (`gh issue list --state open`, scoped to the map's sub-issues / task list), drop any with an open blocker (`issue_dependencies_summary.blocked_by > 0`, or an open issue in the `Blocked by` line) or an assignee; first in map order wins.
- **Claim**: `gh issue edit <n> --add-assignee @me`, the session's first write.
- **Resolve**: `gh issue comment <n> --body "<answer>"`, then `gh issue close <n>`, then append a context pointer (gist + link) to the map's Decisions-so-far.
