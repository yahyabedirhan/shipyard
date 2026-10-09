# Handoff: fix the spinner frames in the skill install output

- **Worktree:** the treehouse pool worktree this session starts in, on branch `fix/spinner-frames`, pushed to `origin`. Work and push on this branch only.
- **Issue:** #250 "Bug: Spinner frames pile up in the skill install output". Read it first with `gh issue view 250`. Its "What to do" steps and acceptance criteria are the brief.
- **Spec and tickets:** none. This is a single bug, not an effort.
- **Reaching the handing-over session:** you can't. Decide open questions yourself and list them in the pull request.
- **Harness:** you run in OpenCode. This is also a live QA of handing work to OpenCode, so note anything in this handoff you couldn't follow.

## What to do

1. Read `AGENTS.md` for the repo's rules and commands.
2. Follow #250 test-first: write the failing test for `SkillInstaller.clean`, then fix it, then run `make test`.
3. Delete this handoff file in your last commit, since its work is then done.
4. Commit in small steps. End each commit message with `Co-Authored-By: <your model> <noreply@...>` as your harness gives it. Don't add session links.
5. Open a pull request against `main` with `gh pr create`. Title: `Apply carriage returns in the skill install output`. Put `Fixes #250` in the body, the one-sentence why, the decisions you made, and a line saying an OpenCode agent made it from a handover. Don't merge it.

## Constraints

- Keep personal information out: no usernames, home paths, emails or IPs.
- Don't use the em dash character.
