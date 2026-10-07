# Handoff: setup-view-logos

Investigate how to show the GitHub and Notion logos in their status views, report the options and results to the maintainer, then build the one they pick and deliver a working pull request against `main`.

## Where

- Worktree: `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/4/shipyard`, leased with treehouse (holder `setup-view-logos`, lease id `946c926630eefe7a6db5274bf065b290`). Keep the lease; the effort's settle frees it after the merge.
- Branch: `feat/setup-view-logos`, cut from `origin/main` at `8a32dd9`.
- Spec: none. The one ticket holds the change.
- Ticket: [Feature: GitHub and Notion logos in their status views (#249)](https://github.com/yahyabedirhan/shipyard/issues/249): no blockers. Label `effort:setup-view-logos`.

## Why

In the live QA of the setup views (#246), the maintainer asked for the GitHub view and the Notion view to show the GitHub and Notion logos instead of the shipyard sailboat. The Shipyard Skill and Shipyard CLI views keep the sailboat. All four logos must have the same outer size. The ticket gives one proposed route; treat it as a starting point, not as decided.

## Phase 1: investigate and report (the maintainer asked for this first)

Investigate, then report to the maintainer before you build. Delegate the research and the prototypes to sub-agents.

1. **Sources and terms.** For each logo, find the maker's own file (GitHub: primer/octicons `mark-github`, github.com/logos; Notion: its brand page or media kit, else simple-icons) and its licence and brand terms. Follow `docs/references/agent-icons.md` and how #137 decided the agents' logos.
2. **Looks.** Prototype two or three looks on the installed build, each with the four views side by side at the same outer size (32 × 32 pt, `LogoBadge`'s rounded square). For example:
   - A: the mark on a tile in the maker's colours (GitHub `#24292F` with a white mark; white with Notion's black mark), as the ticket proposes.
   - B: the bare mark fitted to the square, tinted like text in light and dark mode, as `AgentMarkView` draws Copilot.
   - C: anything better you find, such as an official app-icon file.
3. **Report** with `shipyard ping`, and in the chat of this pane: the sources and terms, the screenshots of each look in light and dark mode (`shipyard screenshot --appearance light|dark`), and your pick with its reason. Wait for the maintainer's answer before Phase 2. They can be reached in this pane.

Prototype on throwaway code: don't commit it to the effort branch. Keep screenshots under `.scratch/` until one look is chosen.

## Phase 2: build the chosen look

Build #249 with the look the maintainer picks, as the ticket's "How to do it" says, adjusted for that look. Record the sources and terms in `docs/references/` and `THIRD-PARTY-NOTICES.md`, add the load test, update `docs/low-level-design.md` and `CHANGELOG.md`, and put the four views side by side in the pull request.

## Notes

- Testing the real app follows `AGENTS.md` Testing: take the lease (`shipyard control take --wait <seconds>`) before `make install`, take it again after the reinstall, end with plain `shipyard app open`, and release it.
- `make test` is the only way to run the tests on this Mac; plain `swift test` can't find the Testing module.
- The installed app is the maintainer's daily app. The GitHub and Notion views show only the login and the workspace name; a demo run shows the GitHub view and a "this run doesn't read notes" Notion view, enough to compare logos.
- The ticket's QA rule: a visual change gets a QA ticket when it closes (`AGENTS.md`, QA).

## Reaching the maintainer's session

The session that wrote this runs in Herdr pane `w3B:p1`, in the setup-views worktree (slot 2); don't touch that worktree. It won't follow up. The maintainer reads this pane and answers the Phase 1 report here. Other open questions: decide them yourself and list them in the PR's reviewer notes. Ping the maintainer with `shipyard ping` when the Phase 1 report and when the PR are ready.

## Delivery

- Follow `AGENTS.md`: commit message style, `make test`, the testing gate, `docs/low-level-design.md` in the same change, `/to-pr` for the PR.
- Don't merge: ask the maintainer.

## Suggested skills

- `orchestrate-effort` and `orchestrating` to run the work through delegates.
- `research` for the sources and terms, `logo-design` for the fit and the optical size, `swift-lab` if a quick SwiftUI sketch helps compare looks.
- `implement` and `write-swift` for the build; `shipyard` for app control, screenshots and pings; `to-pr` for the pull request.
