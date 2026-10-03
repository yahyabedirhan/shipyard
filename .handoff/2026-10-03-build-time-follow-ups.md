# Handoff: the build-time follow-ups (effort build-time-follow-ups)

You pick up the four follow-ups the build-time effort (#124 "Cut CI and build time", PR #142) left open, decide what to do with each, build what's worth building, and deliver one pull request.

## The tickets

All four are labelled `effort:build-time` and `needs-triage`. Each one's body holds the problem, the evidence and its acceptance criteria. Read them first.

- #131 "Fold and cache the linux cli workflow's build". It was waiting on 0.0.6, which has merged (PR #143), so `linux-cli.yml` is on main.
- #132 "Name the expected type in test expectations to cut type-checking time".
- #133 "Share the SDK module cache across local builds on Command Line Tools".
- #135 "Run ci once per push to a branch with an open pull request". The body lists options to weigh.

#130 "Audit the ping, cli and herdr tests after 0.0.6" isn't part of this effort.

On 2026-10-03, a read-only audit of main (`06b818e`) found none of the four done:

- `linux-cli.yml` has no `actions/cache`.
- `ConfigurationTests.swift` still has 23 `== .init(` comparisons.
- There's no `module-cache-path` in the `Makefile` or the README.
- `ci.yml` triggers on `push` and `pull_request` and has no `concurrency` group.

## What to do

1. **Decide each ticket:** build it in this effort, close it as not worth doing, or leave it for later. The maintainer delegated these decisions, so make them yourself. Weigh cost against the time saved, using the measurements in the tickets and in the compile-time report comment on #124. Record each decision and its reason on the ticket, and swap `needs-triage` for the matching triage label (`docs/agents/triage-labels.md`).
2. **Build the ones you chose**, one commit per ticket, test-first where there's behaviour to pin. `make test` must pass. CI changes can only be proven on GitHub, so check the runs on your pushes and compare their timings with recent `main` runs. Read `docs/references/` before changing a workflow, since only `push` runs save the `.build` cache, which #135 has to respect. Update a reference when you learn something new.
3. **Open one pull request** with `/to-pr`. In its description, give each ticket's decision, the before and after timings, and a "Decided alone" list. Use `Closes #n` for each ticket it finishes.
4. **Close tickets you decided against** with a comment giving the reason. Leave deferred ones open with their new label and a comment.
5. **Notify the maintainer** when the pull request is ready, using the global `notification-method`. Don't merge: the maintainer approves merges, and settling happens afterwards with `/settle-effort`.

These changes touch only build, CI and tests, so per AGENTS.md's QA section no QA ticket is needed.

## Where

- **Worktree:** `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/1/shipyard`, a treehouse lease (holder `build-time-follow-ups`, lease id `8a96adc0d9d3e7e6b0ca2645e8c03179`).
- **Branch:** `effort/build-time-follow-ups`, cut from `main` at `06b818e`.

## Working autonomously

The session that wrote this handoff has settled and won't answer. Decide open questions yourself, in the spirit of the tickets, and list each one in the pull request. Agents can't drive the app or the menu (AGENTS.md, Testing). Nothing here should need that.

## Suggested skills

- `orchestrating` and `implement`: delegate and build the tickets.
- `tdd`: where a change has behaviour a test can pin.
- `diagnosing-bugs`: if a timing or cache result surprises you.
- `code-review`: before opening the pull request.
- `to-pr`: the pull request.
- `settle-session`: when done, keeping this worktree leased while the pull request is open.
