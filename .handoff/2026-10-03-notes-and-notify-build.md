# Handoff: build effort notes-and-notify

You are the orchestrator for effort `notes-and-notify`. The thinking session grilled both features with the maintainer, ran a Notion spike, and published the spec and tickets. Your job is to build them and deliver one pull request for the effort.

## Where things are

- **Worktree:** this checkout, leased with treehouse (holder `notes-and-notify`), on branch `effort/notes-and-notify`. It is rebased onto `main` at `e1914a5`, which includes the merged agent lease (0.2.0 work). Pull and rebase onto `origin/main` again before you start, and whenever `main` moves.
- **Spec:** #187 Spec: notes-and-notify, the user's notes in Notion and agents' notices. Every design decision is settled there. Read it in full, including "Linked work outside this repository".
- **Tickets** (sub-issues of #187, label `effort:notes-and-notify`, native blocked-by links):
  - **Wave 1, unblocked:** #188 Tailscale serve spike (`ready-for-human`, the maintainer's), #189 cli.toml, #190 Notices on the Mac, #191 The notes structure in the skill, #192 Notes in the menu.
  - **Wave 2:** #193 The rest of a notice's options (after #190); #194 Notices over the tailnet (after #190, #189); #195 Notices on the poll route (after #190, #189, and yahyabedirhan/herdr-shipyard#1); #196 The new-note icon (after #192).
  - **Outside this repository, also yours to build:**
    - yahyabedirhan/herdr-shipyard#1 Hold shipyard notices for the Mac's poll, and a settings copy. It is public, unblocked, and has its own repo and PR.
    - The maintainer's machine setup (Tailscale, and the Notion routes for every harness), tracked privately. The global instructions say where. Keep its details out of this public repo.
- **The previous handoff,** `.handoff/2026-10-03-notes-and-notify.md`, is the thinking session's brief, now done.

## How the maintainer wants this run

- **Fully autonomous. Never ask the maintainer a question.** Decide anything open yourself, in the spec's spirit, and list each such decision in the pull request.
- **Anything only the maintainer can do** becomes a ticket assigned to them (`--assignee yahyabedirhan`), label `ready-for-human`. Each one has numbered steps, the exact commands, what to report back, and which ticket it unblocks. Add a blocked-by link from the gated ticket. Then tell them through `shipyard ping` (the shipyard skill), and keep working on everything else. Expected ones:
  - **#188, the Tailscale spike:** they run it. The listener build in #194 doesn't wait on it; only its QA does.
  - **Tailscale on each VPS** (the private machine setup): logging in and turning off key expiry in the admin console need them.
  - **The app's Notion token** (the private machine setup): they create the "Shipyard" internal connection, share it with the entry page, and paste the token into the app. Never ask for it in chat and never write it to a file.
  - **OAuth logins** for Codex and opencode's Notion MCP on each machine, if they need a browser.
  - **QA tickets** for the visual features, per AGENTS.md's QA section.
- Ask before merging any pull request (global rule). Delivering the effort's PR via `/to-pr` is the end of the build.
- Before every step that changes what the running app shows, follow AGENTS.md's Testing section: the agent lease and the Starting/Done notifications.

## Facts from the thinking session not in the spec

- **The Notion workspace** for notes is dedicated and already exists. Its name includes the maintainer's name, so keep it out of public files and call it "the notes workspace".
  - On the Mac, `ntn` is logged in to it as the default workspace (`ntn doctor` shows which one).
  - The claude.ai Notion connector is connected to it. It shows up in Claude Code sessions started after the connection; this session's own tools don't include it, so a headless `claude -p --allowedTools "mcp__claude_ai_Notion"` run reached it.
  - The entry page "Shipyard Notes" doesn't exist yet. #191 creates and seeds it.
- **What the spike found** is recorded in the spec's Notes decisions:
  - `ntn api` with a body: use `-d "$(cat file)" < /dev/null`. `-d @file` with stdin attached hangs.
  - `ntn pages trash` needs `--yes`.
  - The scratch spike page is in the notes workspace's trash.
- **Tailscale on the Mac:** installed, with its CLI at `/usr/local/bin/tailscale`. The private machine setup records the rest.
- **Privacy:** no machine labels, home paths, workspace names, or private repo names in public issues, PRs or docs. Public shipyard tickets say only that the maintainer's machine setup "is tracked privately".

## Can you reach the thinking session?

It runs in Herdr and could be prompted, but you don't need it: everything is in the spec and the tickets. Decide for yourself rather than asking it.

## Suggested skills

- `orchestrate-effort` and `orchestrating`: run the effort and delegate the tickets, as many in parallel as the blocking edges allow.
- `implement` and `tdd`, for each ticket's builder.
- `shipyard`: the ping commands to reach the maintainer, and the app-control rules.
- `herdr`: herdr-shipyard work and the remote machines.
- `writing-for-agents` and `maintain-environment`: the skill references and the private machine setup's instructions.
- `domain-modeling`: the glossary entries and the three ADRs.
- `low-level-design`: the module design updates.
- `code-review` before the PR, then `to-pr`.
- `settle-effort` only after the maintainer approves the merge.
