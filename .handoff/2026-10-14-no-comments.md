# Handoff: no-comments follow-up on PR #273

PR: https://github.com/yahyabedirhan/shipyard/pull/273 (branch `chore/no-comments`). Read the PR description first; it holds what was removed, what was kept and why, and the open `MUST KILL` items. This doc does not repeat it.

## State

- The PR deletes comments only. Linux `swift build` and `swift test` pass. The `ShipyardApp` target and its tests have not been built, because they only build on macOS.
- The skill's code-reshaping steps (fixes for `MUST KILL` comments) were not done. The previous session had no `/how`, `/why`, `/architect` runs.
- Skill source, pinned to commit `1e5c90a4b6f249917bd21fe361b3a2a7deb741b8` of `cursor/plugins`. Read it straight from GitHub; do not install it:
  - https://github.com/cursor/plugins/blob/1e5c90a4b6f249917bd21fe361b3a2a7deb741b8/pstack/skills/no-comments/SKILL.md
  - https://github.com/cursor/plugins/blob/1e5c90a4b6f249917bd21fe361b3a2a7deb741b8/pstack/agents/comment-sicko.md
  - The `how`, `why` and `architect` skills under `pstack/skills/` at the same commit.

## What this session does

1. In this worktree, on `chore/no-comments`, run `make test` and `make bundle`. Report results. If either fails, find whether the failure comes from this PR (comments only, so it should not) or already happens on `main`.
2. Review the 51 kept foreign-gotcha comments (see the PR's "Kept" note). Delete any that don't meet the comment-sicko keep list.
3. Work the `MUST KILL` items listed in the PR with the skill's fix steps (use the how/why/architect procedures as the skill describes, run in this session):
   - `nonisolated(unsafe)` sources in `ConfigurationWatcher`
   - `state.json` forward-compatibility rules in `AppStateStore`: make them decode tests or types
   - `make-icon` usage text: make it a `--help`
   - timing of the starting-app look in `ControlCommand.open`
   One commit per step, pushed to `chore/no-comments`. Run `make test` before each push.
4. Update the PR description with the `/to-pr` skill so it covers the new commits and lists decisions made alone.
5. Do not merge. Ask the maintainer. Bring costly-to-reverse choices as one plan.

## Constraints

- Do not use Cursor cloud agents or launch remote sessions.
- The repo is public: no private links, personal details or secrets in commits, PR text or this doc.
- Commit this handoff doc with your first commit only if the project keeps handoffs; otherwise leave it out of the PR.

## Suggested skills

- `no-comments` (read from the pinned GitHub URL above)
- `how`, `why`, `architect` (same commit, for the `MUST KILL` reshapes)
- `to-pr` (for the PR description update)
