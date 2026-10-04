# Handoff: effort header-counts

Build the effort `header-counts` as its orchestrator, and deliver one pull request.

## Where

- Worktree: `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/3/shipyard` (treehouse lease holder `header-counts`, lease id `8ebd5d43c70b4d4514444bffb37d11b2`).
- Branch: `effort/header-counts`, cut from `main` at `14b39a2`.

## What

- Spec: #209 "Spec: Item counts per kind in the list layout's project headers" (label `effort:header-counts`).
- Tickets, all sub-issues of the spec, labelled `ready-for-agent`:
  - #210 "Feature: Item count chips in the list layout's project headers": no blockers.
  - #211 "Feature: Choose header count kinds with [menu] header-counts": blocked by #210.
  - #212 "Feature: Check icon in a fixed slot for Mark all seen": blocked by #210.

The spec holds every design decision, including the header sketch. Read it first. The design was settled with the maintainer in a grilling session. Don't reopen it.

## Decisions settled in the grilling session (already in the spec)

- A count includes every row of that kind the project lists, including hidden rows and closed rows still in their window.
- The highlight is the accent colour on a faint accent capsule. Other chips are grey. When in doubt, choose the simpler option.
- The chips sit right-aligned in fixed slots, so columns line up across projects. A kind with 0 rows leaves its slot empty.
- The check icon (Mark all seen, hover only) has a fixed slot just left of the chips.
- This changes the list layout only. The tabs layout and the menu bar count don't change.

## How to work

- The maintainer asked for **no more questions**. This session can't take messages back from you, so decide any open question yourself. Pick the simplest option, and list each decision in the pull request.
- Follow `AGENTS.md`/`CLAUDE.md` for commits, tests (`make test`, owner-test gate), screenshots with app control and the lease, and the QA ticket. This is a visual change, so it gets a QA ticket.
- Keep the shipyard skill (`skills/shipyard/SKILL.md`) user-facing when #211 adds the key.
- Update `docs/low-level-design.md` when the section model changes.

## Suggested skills

- `orchestrate-effort` / `orchestrating`: run the effort.
- `implement`, `tdd`: for each ticket.
- `shipyard`: app control, demo runs and screenshots.
- `to-pr`: the pull request description.
- `code-review`: before you open the pull request.
