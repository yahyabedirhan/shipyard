# Handoff: resume building shipyard 0.0.5, pings (effort `shipyard-0-0-5`)

You are the orchestrator for this effort, taking over from an orchestrator that ran on the maintainer's Mac and stopped so the laptop could close. Build the effort end to end and deliver one pull request.

**Read `.handoff/2026-10-02-pings.md` first.** It still holds everything about the effort: spec #96, tickets #97–#105 with their blockers, how the maintainer wants it run (fully autonomous, no questions, QA non-blocking, don't merge) and the decisions settled in the grilling. This file only adds what changed since.

## Where

- Branch: `effort/shipyard-0-0-5`, pushed to `origin`. Work in whatever worktree you were started in, as long as it is on that branch. The Mac worktree path in the first handoff no longer applies.
- The branch holds the glossary and ADR 0004 commit and the two handoffs. No ticket is built yet: every ticket from #97 to #105 is open, with no boxes ticked.

## Progress so far

- The previous orchestrator read the spec and every ticket, and started one delegate on #97 in a local worktree on the Mac. Its work was never committed or pushed, so it doesn't carry over. **Start #97 from scratch.**
- No decisions were made alone yet, so the pull request's decisions list starts empty.

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

- `make test` there is `swift test`, which builds and tests `ShipyardCore` only. `ShipyardApp` and `ShipyardAppTests` are declared only on macOS (`Package.swift`; `docs/low-level-design.md`, Platforms). Keep every rule in the core behind ports, as the design already requires.
- The app target's code (row icons, the hover ✕, the onboarding and panel link offer, the Herdr focus and app activation implementation, removing a delivered notification) and the CLI's bundling into `Shipyard.app` (`make bundle`) are checked only by CI's `macos` job (`.github/workflows/ci.yml`, on every push). After each batch's push, wait for both CI jobs with `gh run watch` / `gh run list --branch effort/shipyard-0-0-5`, and treat a red macOS job as a failed batch. Tell delegates that app-target code can't be compiled locally, so it must be small and must mirror existing app code closely.
- Put this in the pull request under skipped checks: `make test` and `make bundle` were run only in CI's macOS job, never on a local Mac.
- If the new `shipyard` CLI target only needs the core, declare it outside the `#if os(macOS)` block so it builds on Linux too; it is still bundled only on macOS.

## Suggested skills

- `orchestrate-with-handoff` (you were likely started with it), then `orchestrate-effort` and `orchestrating`
- `implement`, `tdd`, `low-level-design`, `code-review`: for each delegate, as the first handoff says
- `shipyard` and `writing-for-agents`: for #105
- `to-pr`: to open the pull request
- `settle-session`: when done
