# shipyard

A macOS menu bar app for seeing and reviewing the pull requests your agents open on your behalf.

## Changing The Maintainer's Shipyard

A request to change the maintainer's shipyard (its layout, projects, notifications, what it shows) means their `config.toml`: edit it through the **shipyard** skill, even from this repository. Change the app's code only when the request asks for code (a new setting, a bug fix, a feature). When no setting does what's asked, say so; the code change waits for the maintainer to ask for it.

The shipyard skill (`skills/shipyard/SKILL.md`), its description included, is for shipyard's users editing their `config.toml`. It never mentions this repository, its code, or how to maintain the project: guidance for agents working here goes in this file. Check skill diffs for maintainer-facing wording before committing.

## Git, Commits, And Pull Requests

- Opening a pull request, or changing an existing one's description, goes through the **to-pr** skill, which owns the description's shape and where it is saved. Invoke it as part of the work, without waiting to be asked.
- Issue and pull request numbers belong in commit messages, pull requests and docs. Code, comments and test names say what they mean in words, so they read without the tracker.

Use lowercase multi-line commit messages with a Conventional Commits type on the subject line:

```text
type(scope): what changed

- explanation 1
- explanation 2
- explanation 3
```

- Types: `feat` (new capability, MINOR bump) and `fix` (a patched bug, PATCH bump); `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, and `chore` for maintenance. Nothing else, and no bare subjects.
- Scope is optional and names the area: the app's (`menu`, `panel`, `sign-in`, `onboarding`, `config`, `arrangement`, `runs`, `icon`) or the repo's (`release`, `skill`, `agents`, `handoff`, `readme`, `design`, `adr`, `references`, `assets`). Moves and path rewrites are `refactor`, tickets and ledgers are `chore`, handoffs and reports are `docs`.
- Keep the whole message lowercase, including company and product names. The `Co-Authored-By` trailer keeps its standard spelling.
- Never add a `Claude-Session:` trailer or any other session link to a commit message. The `Co-Authored-By` line from the session's attribution rule is the only trailer.

## Where Agent Records Go

```text
.handoff/<date>-<topic>.md     tracked   handoffs between sessions
docs/assets/<topic>/           tracked   screenshots worth keeping, linked from issues, pull requests and docs
.scratch/                      ignored   notes, logs, temp files, raw captures and pull request description sources
.claude/worktrees/             ignored   sub-agent worktrees
```

`.scratch/` is throwaway: anything that must outlive the session moves to a tracked home, or into the issue or pull request it belongs to.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues in `yahyabedirhan/shipyard`, handled with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named after its role (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## QA

When a ticket that changes what the maintainer sees or does is built, close it and open a separate QA ticket, linked to it both ways. Label it `ready-for-qa` and assign it to the maintainer. It holds the installed build, how to use the feature, numbered try-this steps with known risks marked, what to do when done, and screenshots when there are any. QA doesn't hold the pull request. Only visual, interactive changes get a QA ticket; configuration, agent and skill changes close when built.

## Design

`docs/low-level-design.md` is the agreed module design: requirements, modules and their state, the folder tree, the refresh pipeline and traced flows. Read it before adding or moving a module, and update it in the same change when the design moves.

## Testing

Verify changes with automated tests (`make test`) that exercise the code and the menu model without driving the Mac. Accessibility access is blocked for agents on purpose, so clicking, scripting or opening the installed app always fails; don't retry it or look for a way around it. When a change needs a check in the real menu, name the check in the handoff or pull request and leave it to the maintainer.

## References

Facts from GitHub's documentation that shipyard depends on (rate limits, workflow runs, device flow) live in `docs/references/`. Read the one for an area before changing it, and update it when you learn something new from the source.
