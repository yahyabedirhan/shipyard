# Handoff: cut CI and build time (mini-effort `build-time`)

You orchestrate issue #124 "Cut CI and build time" and deliver one pull request to `main`. #124 is the whole effort: the measurements, the four steps in order, the scope and the acceptance criteria. Read it in full first.

## Where

- **Machine:** the maintainer's Mac. You run in Herdr there.
- **Worktree:** `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/3/shipyard`, a treehouse lease with holder `build-time`.
- **Branch:** `effort/build-time`, cut from `main` at `c072069`, which already holds 0.0.5 (#106) and the test audit (#123).
- **The pull request's base:** `main`.
- **Delegates, if you use any:** the harness's own sub-agent worktrees (`.claude/worktrees/`).

## Where the numbers come from

The test audit (#122 "Prune tests that don't earn their keep, with a test audit") measured the build:
- Running the tests takes about 3 s.
- A clean `swift build --build-tests` takes about 50 s on this Mac.
- CI's macOS job compiles three times: `swift build`, then `make bundle`, then `make test`.

Its timing method:
- A clean build used a fresh `--scratch-path`, timed separately from `swift test --skip-build`.
- On this Mac the Command Line Tools need the Testing framework flags from the `Makefile`'s `TEST_FLAGS`.
- Time on a quiet machine: an earlier run taken while agents were busy came out 10 s slow.

## Decisions settled with the maintainer

- **Do all four steps in #124.** The maintainer agreed to all of them, including running the release bundle only on `main` and tags. Say in the pull request what that gives up (a broken bundle shows up at merge, not on the branch).
- **Don't block 0.0.6.** The `shipyard-0-0-6` orchestrator runs on netcup-vps on `effort/shipyard-0-0-6`. It changes tests and adds `.github/workflows/linux-cli.yml`. So:
  - edit only `.github/workflows/ci.yml` and docs;
  - leave `Makefile`, `Package.swift`, `Sources/`, `Tests/` and `linux-cli.yml` alone;
  - file the follow-up for `linux-cli.yml`, the same caching and folded steps once 0.0.6 merges, as a ticket.
- **Step 4 is read-only.** Post the slow-to-compile report as a comment on #124, and file fixes as their own tickets in the `build-time` effort, labelled `needs-triage`, for after 0.0.6 merges.
- **Prove with real CI runs.** Take before and after step times from GitHub Actions runs, comparing a cold cache with a warm one, and put them in the pull request. Prove the cache can't give a false green: after a source change, the changed file still recompiles.
- **Decide open questions yourself** and list them in the pull request under a heading of their own. Don't stop to ask the maintainer.
- **Notify the maintainer** with Done or Blocked, using the global notification method (`osascript`).

## Reaching the session that started this

The session that wrote this handoff runs in the same Herdr on this Mac, in workspace `test-audit`, tab "CC · dev · test-audit". It may be settled by the time you need it, so treat open questions as yours to decide, as above.

## Suggested skills

- `orchestrating`: delegate the CI edits and the compile-time measurement
- `code-review`: on the whole branch once it is done, then fix what it finds
- `to-pr`: to open the pull request (the description's shape and where it's saved)
- `settle-session`: when done
