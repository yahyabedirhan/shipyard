# Handoff: build effort clean-slate

You are the orchestrator for effort `clean-slate`. Build every ticket and deliver the effort through one pull request from `effort/clean-slate`, or several stacked ones if a ticket's size calls for it. The maintainer agreed the whole plan in a grilling session on 2026-10-03 and said "all good to go". Treat this handoff as their go-ahead.

## Where things are

- **Worktree:** `~/.treehouse/shipyard-1e47e3/1/shipyard`, leased with treehouse (holder `clean-slate`, lease id `2c74ebe6e6d2d8e3bd4db1faedd77ffe`), on branch `effort/clean-slate`, cut from `main` at `66679d8`.
- **Spec:** #160 "Spec: clean-slate, every open issue finished, app control, modules by concern and the 0.1.0 release". Every decision is recorded there. Read it first.
- **Tickets:** the spec's sub-issues, all labelled `effort:clean-slate`, with GitHub's native blocked-by edges. Work the frontier: `gh api repos/yahyabedirhan/shipyard/issues/160/sub_issues`, then each issue's `issue_dependencies_summary`.
  - **New:** #161–#171.
  - **Moved in from older efforts:** #77, #83, #84, #107, #126, #127, #128, #129, #130, #134, #146, #147, #150, #152, #154. The grilling's decisions are posted on each as a comment.
- **The session that wrote this** runs in Herdr pane `wF:p7` on the Mac and can answer questions (`herdr agent prompt` to that pane). Anything not settled there is yours to decide; list such decisions in the pull request's "Decided alone".

## The design in one view (agreed as "A+")

The spec states the module design in prose, and ticket #161 writes it into `docs/low-level-design.md` with ADR 0006. This is the target it was agreed on:

```text
ShipyardCommand   foundation: CommandResult/Environment, ShipyardVersion, GitRemote, HerdrCommand, RecordStore
ShipyardPings     agent side: Ping, PingStore, PingCommand, PingList, HerdrEvent, PingFiling + Unfiled
ShipyardConfig    Configuration, reader, TOMLSourceMap, Selectors, WindowDuration, LayoutSetting, ConfigStore,
                  ResolvedRepositoriesStore, ProjectFiling (implements PingFiling)
ShipyardControl   ControlRequest/Reply, ControlCommand (argument parsing), ControlClient (socket)
ShipyardCore      the app's rules only; Presets, ConfigStatus, AppStateStore, CLILink, Skill/ stay;
                  Mac side of pings stays: RemotePingReader, RemoteMachines, RemotePingMarks, PingNumbers,
                  KnownAgent, HerdrFocus
ShipyardApp       + Control/: ControlServer, PanelControl, Screenshotter, DemoLaunch

shipyard on Linux  → Command + Pings
shipyard on macOS  → Command + Pings + Config + Control    (never Core)
Shipyard.app       → everything
```

Weighed and rejected:
- **One core with a command table:** the Linux binary would still carry everything.
- **Two executables (`shipyard` + `shipyardctl`):** a second name with no extra isolation.
- **The app files every ping:** it loses refusals while the app is quit.

The design's test of extensibility is a future "Notes" feature: one new `ShipyardNotes` module beside Pings, plus one line in the command table. Notes is out of scope.

## Facts the repository doesn't show

- **Tests can't build on the maintainer's Mac.** It has only the Command Line Tools, no Xcode, and `swift test` / `make test` fail there with "no such module 'Testing'". CI (`ci.yml`, Ubuntu and macOS) runs the full suite on every push, so use it as the test gate, or build in an environment that has the module. Say in the pull request which checks ran where.
- **The VPSes don't install herdr-shipyard from GitHub.** `hetzner-vps` and `netcup-vps` (the maintainer's `[remote] machines`) run it as a local link (`source: local`) to a clone at `~/Developer/yahyabedirhan/herdr-shipyard`, with a locally built `shipyard` that reports 0.0.3. Switching them to `herdr plugin install yahyabedirhan/herdr-shipyard` is part of #147. Check whether `herdr plugin unlink` is needed first.
- **The shipyard skill copies match `main`** (`npx skills`, global, Claude Code and Codex) on the Mac and both VPSes as of 2026-10-03, after PR #158. The PromptScript failure during install is expected and harmless.
- **The Hetzner Herdr server was restarted on 2026-10-03.** It had been running an older 0.9.3 build than its installed binary, which made `herdr machine status` report it incompatible. If that error comes back, it needs the same `herdr server stop` on that machine, which only the maintainer can run (no SSH without asking).
- **Reach remote machines through their saved Herdr machine:** open a new workspace there (`herdr --machine <label> workspace create --no-focus`), run commands in its first pane, and close the workspace afterwards. Never use plain SSH.
- **The installed app was rebuilt from `main` on 2026-10-03** with `make install`, so it runs the ping code while reporting 0.0.3.
- **Releasing:**
  - The version, `VersionTests`' pinned `"0.0.3"` and README line 7 ("describes 0.0.3") must change together.
  - The next release is **0.1.0**, and the maintainer chose that number.
  - Tags `v0.0.5`–`v0.0.7` are history only (#163): plain tags, no GitHub release.
- **Effort names are descriptive from now on.** The old `effort:shipyard-0-0-*` labels stay on closed issues only.

## Permissions to expect

- Merging needs the maintainer's yes (global rule). Ask once the effort's pull request is green, through a ping and in the pull request.
- **App control:** agents may use `shipyard app`, `panel` and `screenshot` once built; clicking and Accessibility stay off limits. If a permission rule blocks launching the app, say so and leave the launch to the maintainer rather than working around it.
- **Notify the maintainer** with `shipyard ping` when the pull request is ready and when a question blocks you (see the shipyard skill).

## Suggested skills

- `orchestrate-effort` and `orchestrating`: you are the orchestrator.
- `implement` and `tdd`: for each ticket's builder.
- `low-level-design`: for #161.
- `domain-modeling`: for ADR 0006 and any glossary terms (`Control`, `PingFiling`).
- `writing-for-agents`: for the `AGENTS.md`/`CLAUDE.md` sections and the shipyard skill.
- `shipyard`: to send pings.
- `herdr`: for the VPS steps.
- `maintain-environment`: for carrying the skill to the machines.
- `treehouse`: for worktrees.
- `to-pr`: for every pull request.
- `code-review`: before asking to merge.
- `settle-effort`: once merged.
