# Handoff: resume building shipyard 0.0.5, pings (effort `shipyard-0-0-5`)

You are the orchestrator for this effort, taking over from an orchestrator that ran on the maintainer's Mac and stopped so the laptop could close. Build the effort end to end and deliver one pull request.

**Read `.handoff/2026-10-02-pings.md` first.** It still holds everything about the effort: spec #96, tickets #97–#105 with their blockers, how the maintainer wants it run (fully autonomous, no questions, QA non-blocking, don't merge) and the decisions settled in the grilling. This file only adds what changed since.

## Where

- Branch: `effort/shipyard-0-0-5`, pushed to `origin`. The Mac worktree path in the first handoff no longer applies.
- Worktree on the VPS: `/home/yabepa/.treehouse/shipyard-1e47e3/1/shipyard` (treehouse lease, holder `shipyard-0-0-5`, lease id `621993f5719b60f081c56448bfba0647`), open in Herdr as workspace `shipyard-0-0-5`, tab `CC · orchestrator · shipyard-0-0-5`. Pull before starting: the branch may have moved since the lease.
- Delegates' worktrees: use the harness's own sub-agent worktrees (`.claude/worktrees/`), as on the Mac.
## Progress so far

- **#97 is built and landed** as `feat: send a ping with the shipyard cli and see it under its project (#97)` on the branch. `make test` passed on the Mac (686 tests, app target included), its boxes are ticked and the issue is closed. Its delegate took about 17 minutes, with no review findings left open. **Start at batch 2.**
- Read #97's commit and `docs/low-level-design.md` (requirements N1–N5, the ping store, the ping command, `ShipyardCLI`, Trace 6, and the extensibility rows for #98, #100, #102 and #103) before briefing batch 2.

## Decisions so far (for the pull request's decisions section)

Made by the #97 delegate:

- **CLI location:** the CLI is bundled at `Shipyard.app/Contents/Helpers/shipyard` (SwiftPM product `shipyard-cli`), not next to the app executable. On case-insensitive APFS, `shipyard` and `Shipyard` collide in `.build/release` and `Contents/MacOS`. **#104 links `~/.local/bin/shipyard` to `Contents/Helpers/shipyard`.**
- **Ping store:** `~/Library/Application Support/Shipyard/Pings/<id>.json`, one file per ping, written atomically.
  - A record has `id`, `title`, `projects`, `sent` and an optional `seen`. Later fields (body, sender, action, repository) are added as optionals so old records still read.
  - Files that don't read are skipped.
  - Seen state lives on the ping, not in `state.json`.
- **Attention:** a ping needs attention while it's unseen, whatever the `[attention]` toggles say.
- **Ids:** six characters from `abcdefghjkmnpqrstuvwxyz23456789`, drawn again on a collision.
- **Exit codes:** 0 for success; 1 when refused (unknown project, a store write failing, a config that doesn't read); 2 for usage errors.
- **Missing `--project`:** for now it is an exit-2 error that lists the projects. #98 replaces it with filing by the git remote.
- **CLI with a broken `config.toml`:** the ping fails with the first problem; a missing file means no projects.
- **A ping as an item:**
  - URL `shipyard://ping/<id>`, with no repository, number or author.
  - Under `group-by` set to `repository` or `author`, pings go into a "Pings" group placed last. #100 changes `author` to group by sender.
  - The row's second line reads "ping" until #100 adds the sender.
  - The icon is `bell.fill` in the accent colour.
- **Watching:** the app reuses `ConfigWatcher` on the store's directory and rebuilds the menu only when the pings actually changed.
- **Early listing:** pings list before GitHub answers, because `MenuModel.build` arranges listings without a snapshot.
- **`--project`:** matches project names exactly, case-sensitive.

Open questions it raised, now yours to decide:

- Does the `[attention] unseen` toggle apply to pings? The delegate said no.
- For #102: a title that is literally `withdraw` or starts with `--` can't be sent. Consider `--` as an end-of-options marker.
- The README doesn't mention pings yet; give it to #104 or #105.

## The plan (shown to the maintainer; keep it)

```text
Batch 1  #97 Send a ping with the CLI and see it under its project   tracer · own /code-review
Batch 2  #98 File a ping by the agent's repository                   no review
(parallel) #99 A new ping posts a notification                       no review
         #100 A ping's action takes you there                        own /code-review
         #103 Pings leave on their own or when dismissed             no review
         #104 Link the shipyard CLI onto the PATH                    no review
Batch 3  #101 Focus a Herdr tab from a ping   (after #100)           no review
(parallel) #102 Replace and withdraw a ping by id (after #99)         own /code-review
Batch 4  #105 Teach agents to ping in the shipyard skill (after all) no review
Deliver  branch /code-review → fixes → /to-pr · QA ticket (non-blocking)
```

#97 is the tracer bullet. Its delegate brief asked it to build the ping store record and the ping command's parsing so the later tickets extend them cleanly (room for body, sender, action, id and seen time; subcommand parsing so `withdraw` fits), without building those tickets.

## Verifying on Linux (new)

If you run on the Linux VPS rather than a Mac:

- The VPS has no `make`; run `swift test` (Swift 6.4 through swiftly, on the login shell's PATH), which is all `make test` does on Linux. It builds and tests `ShipyardCore` only. `ShipyardApp` and `ShipyardAppTests` are declared only on macOS (`Package.swift`; `docs/low-level-design.md`, Platforms). Keep every rule in the core behind ports, as the design already requires.
- The app target's code (row icons, the hover ✕, the onboarding and panel link offer, the Herdr focus and app activation implementation, removing a delivered notification) and the CLI's bundling into `Shipyard.app` (`make bundle`) are checked only by CI's `macos` job (`.github/workflows/ci.yml`, on every push). After each batch's push, wait for both CI jobs with `gh run watch` / `gh run list --branch effort/shipyard-0-0-5`, and treat a red macOS job as a failed batch. Tell delegates that app-target code can't be compiled locally, so it must be small and must mirror existing app code closely.
- Put this in the pull request under skipped checks: `make test` and `make bundle` were run only in CI's macOS job, never on a local Mac.
- If the new `shipyard` CLI target only needs the core, declare it outside the `#if os(macOS)` block so it builds on Linux too; it is still bundled only on macOS.

## Notifying the maintainer

The global notification method (`osascript`) is macOS-only and doesn't exist on the VPS. Send the Done and Blocked notifications with `herdr notification show "<message>" --sound done` (or `--sound request` for Blocked) instead.

## Suggested skills

- `orchestrate-with-handoff` (you were likely started with it), then `orchestrate-effort` and `orchestrating`
- `implement`, `tdd`, `low-level-design`, `code-review`: for each delegate, as the first handoff says
- `shipyard` and `writing-for-agents`: for #105
- `to-pr`: to open the pull request
- `settle-session`: when done
