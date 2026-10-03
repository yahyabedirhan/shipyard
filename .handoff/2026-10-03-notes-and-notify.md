# Handoff: think through effort notes-and-notify

You are the thinking session for effort `notes-and-notify`. The maintainer has two ideas, a **Note** feature and a **Notify** feature, and wants to grill them with you. They ship together as one effort, after 0.2.0.

## Where things are

- **Worktree:** this checkout, leased with treehouse (holder `notes-and-notify`), on branch `effort/notes-and-notify`, cut from `main` at `66679d8`.
- **Order of efforts:**
  1. `clean-slate` (spec #160) is about to merge and ships as **0.1.0**. It adds app control (`shipyard app`, `panel`, `screenshot`, demo launch) and splits the code into modules by concern. Its branch is `origin/effort/clean-slate`; until it merges, `main` doesn't have that code, so read the design there: `git show origin/effort/clean-slate:docs/low-level-design.md`, `…:docs/adr/0006-modules-follow-concerns-agent-side-code-never-links-the-apps-rules.md`, `…:skills/shipyard/SKILL.md`. Once it merges, rebase this branch onto `main`.
  2. The **agent lease** ships as **0.2.0**: one agent at a time holds shipyard through an expiring lease, with a dot on the icon, a banner with Stop, and `control.started`/`control.ended` notifications. Its agreed design is in `origin/effort/clean-slate:.handoff/2026-10-03-agent-lease.md`.
  3. **This effort**, after 0.2.0. By the Releases rule in `AGENTS.md` (on the clean-slate branch), a `feat` raises the middle number, so it would ship as 0.3.0.
- **What the design already says about notes:** spec #160 used "a future Notes feature" as the test of the module design: one new `ShipyardNotes` module beside `ShipyardPings`, plus one line in the command table. That was a test of extensibility, not a decision about what notes are. The maintainer hasn't described either idea yet: start by asking.

## What to do

Run in this order, in one unbroken session, naming each skill as you reach it:

1. `/grilling`: sharpen both ideas with the maintainer, one round of questions at a time, until the frontier is empty. Settle early whether they are one feature or two that touch, and how each relates to pings (agent-sent items in the menu) and to the app's notification rules.
2. `/prototype`: only when a question needs a runnable answer; the maintainer reviews it.
3. `/to-spec`: publish the spec as a GitHub issue in `yahyabedirhan/shipyard`.
4. `/to-tickets`: tracer-bullet tickets with blocked-by edges, labelled `effort:notes-and-notify`.
5. `/handover`: hand over to an orchestrator when the maintainer says to build. Building waits until 0.2.0 has shipped.

## Facts

- Read `AGENTS.md`/`CLAUDE.md` (the clean-slate branch's version is the newest) for commit rules, QA, testing and releases.
- Personal details stay out of public files: no machine labels, home paths or the maintainer's private project names in issues or docs.
- The maintainer is at the Mac and wants to be told before any step that changes what the running app shows (see `AGENTS.md`'s Testing section on the clean-slate branch). Grilling doesn't need the app.
