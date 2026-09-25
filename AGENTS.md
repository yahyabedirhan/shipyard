# shipyard

A macOS menu bar app for seeing and reviewing the pull requests your agents open on your behalf.

## Git, Commits, And Pull Requests

- Opening a pull request, or changing an existing one's description, goes through the **to-pr** skill, which owns the description's shape and where it is saved. Invoke it as part of the work, without waiting to be asked.

Use lowercase multi-line commit messages with a Conventional Commits type on the subject line:

```text
type(scope): what changed

- explanation 1
- explanation 2
- explanation 3
```

- Types: `feat` (new capability, MINOR bump) and `fix` (a patched bug, PATCH bump); `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, and `chore` for maintenance. Nothing else, and no bare subjects.
- Scope is optional and names the area (`jobs`, `prep`, `dashboard`, `vault`, `migration`); moves and path rewrites are `refactor`, tickets and ledgers are `chore`, handoffs and reports are `docs`.
- Keep the whole message lowercase, including company and product names. The `Co-Authored-By` trailer keeps its standard spelling.
- Never add a `Claude-Session:` trailer or any other session link to a commit message. The `Co-Authored-By` line from the session's attribution rule is the only trailer.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues in `yahyabedirhan/shipyard`, handled with the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named after its role (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Design

`docs/low-level-design.md` is the agreed module design: requirements, modules and their state, the folder tree, the refresh pipeline and traced flows. Read it before adding or moving a module, and update it in the same change when the design moves.

## References

Facts from GitHub's documentation that shipyard depends on (rate limits, workflow runs, device flow) live in `docs/references/`. Read the one for an area before changing it, and update it when you learn something new from the source.
