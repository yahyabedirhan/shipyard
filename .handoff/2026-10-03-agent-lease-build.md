# Handoff: specify and build effort agent-lease, from a VPS

You are the orchestrator for effort `agent-lease`, running on one of the maintainer's Linux VPSes. Turn the agreed design into a spec and tickets, then build every ticket and deliver the effort through one pull request from `effort/agent-lease`. It ships as **0.2.0**. The maintainer asked for this effort to start now and to run here; treat this handoff as their go-ahead.

## Where things are

- **Worktree:** this checkout, leased with treehouse (holder `agent-lease`), on branch `effort/agent-lease`, cut from `main` after effort clean-slate merged (#172) and 0.1.0 was released.
- **The design:** [`.handoff/2026-10-03-agent-lease.md`](2026-10-03-agent-lease.md). Every decision there was agreed with the maintainer in a grilling session; the grilling is done.
- **The tracking issue:** #173 "The agent lease: one agent at a time holds shipyard, and the maintainer sees it (0.2.0)". It closes when your spec exists.
- **The session that wrote this** is the clean-slate orchestrator on the maintainer's Mac, in Herdr; it can't be reached from here. Anything the design leaves open is yours to decide; list such decisions in the pull request's "Decided alone".

## What to do

1. `/to-spec` from the design handoff (no interview: the decisions are made). Publish it as a GitHub issue, and close #173 linking it.
2. `/to-tickets`: tracer-bullet tickets with blocked-by edges, as sub-issues of the spec, labelled `effort:agent-lease` (the label exists).
3. `/orchestrate-effort` on the spec and tickets, following `AGENTS.md`.
4. Once the pull request is green and its branch review is clean, ask the maintainer to merge it (a ping, see below, and the pull request). Releasing 0.2.0 follows the Releases section after the merge, but some of its steps need the Mac (below).

## Facts this machine changes

- **The app doesn't build here.** `ShipyardApp` (SwiftUI and AppKit) compiles only on macOS. On Linux you can build and test Command, Pings, Config (if its sources are platform-neutral), Control and the core's Linux-buildable tests with `swift test`, or in Docker (`swift:6.2-noble`, as `ci.yml`'s Linux job does). The macOS build, the app's tests and `make test` run in CI's macOS job on every push: use it as the gate for app code, and push integration batches often so it runs.
- **Swift isn't on `PATH` in a fresh shell here:** run `. ~/.local/share/swiftly/env.sh` first.
- **No real-app checks from here.** App control steers only the app on the Mac. The lease's visible parts (the dot, the banner, Stop, the notifications) can't be checked here: put each such check in the effort's QA ticket (`AGENTS.md`'s QA rule) with its steps, and say in the pull request that no real-app check ran.
- **Reaching the maintainer:** `shipyard ping` from this machine reaches the Mac's menu (the shipyard skill's remote section). Ping when the pull request is ready and when a question blocks you. Don't run `shipyard app`, `panel` or `screenshot` here: they exit 2 on Linux.
- **Releasing 0.2.0** (after the merge): `make release` and reinstalling the Mac's app need the Mac. Do the version bump in the pull request; after the merge, ping the maintainer that the release needs a Mac session, unless they tell you otherwise.
- `make test` doesn't exist as a Linux gate; don't set `TEST_FLAGS` anywhere. Commit rules, QA, the design doc and the test gate are in `AGENTS.md` (`CLAUDE.md` is a symlink to it).
- Personal details stay out of public files: no machine labels, home paths or the maintainer's private project names.
