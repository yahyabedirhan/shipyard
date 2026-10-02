# Handoff: audit and prune shipyard's tests (mini-effort `test-audit`)

You run the test audit in issue #122 "Prune tests that don't earn their keep, with a test audit", and deliver one pull request. #122 is the whole effort: it holds the method, the evidence each deletion needs, the scope and the acceptance criteria. Read it in full first, then the method it cites (OpenClaw's test-audit skill, linked at a pinned commit).

## Where

- **Machine:** the maintainer's Mac. You run in Herdr there.
- **Worktree:** `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/2/shipyard`, a treehouse lease with holder `test-audit`.
- **Branch:** `effort/test-audit`, cut from `effort/shipyard-0-0-5` at `8da9f63`. The 0.0.5 pull request "feat: pings, sent by agents through the shipyard cli (0.0.5)" isn't merged yet.
- **The pull request's base:** `effort/shipyard-0-0-5`. Say in its description that it retargets to `main` when 0.0.5 merges.
- **Delegates, if you use any:** the harness's own sub-agent worktrees (`.claude/worktrees/`).

## Decisions settled with the maintainer

- **Start now, alongside 0.0.6.** The maintainer asked for it now rather than after 0.0.6.
  - The `shipyard-0-0-6` orchestrator runs on netcup-vps on `effort/shipyard-0-0-6`, also cut from 0.0.5. It extends the ping, CLI and Herdr tests and the `Harness` and `FakeHerdr` doubles.
  - So leave those alone: nothing under the ping and CLI test folders, nothing in `FakeHerdr`, and nothing in the ping parts of `Harness`. Everything else is in scope.
- **Discovery report first.** Post it as a comment on #122 before deleting anything. List every candidate with every evidence field, and the false positives you keep.
  - Then prune in coherent batches by area, one commit per batch.
  - Don't stop to ask the maintainer between discovery and pruning. Decide yourself, and list your judgement calls in the pull request under a heading of their own.
- **Measure before and after.** Record test count and suite time, with build time split from test run time (`swift build --build-tests` timed separately from `swift test --skip-build`). Report whether pruning or build time is the real lever.
- **Verify** with `make test` on this Mac, which covers the app target, and with CI's two jobs after each push.
- **Notify the maintainer** (Done or Blocked) with the global notification method (`osascript`).

## Reaching the session that started this

The session that wrote this handoff runs in the same Herdr on this Mac, in workspace `shipyard-0-0-5`, tab "CC #3". The maintainer can relay, but treat open questions as yours to decide, as above.

## Suggested skills

- `tdd` and `codebase-design`: for judging seams and owner boundaries
- `code-review`: once all batches land, on the whole branch, then fix what it finds
- `to-pr`: to open the pull request (the description's shape and where it's saved)
- `settle-session`: when done
