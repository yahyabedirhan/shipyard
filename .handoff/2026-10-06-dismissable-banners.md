# Handoff: dismissable banners

Build the effort `dismissable-banners` and deliver a working pull request against `main`.

## Where

- Worktree: `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/1/shipyard`, leased with treehouse (holder `dismissable-banners`, lease id `e2d6989657634e0eb57e2e3134d63325`). Keep the lease; the maintainer's session settles it after the merge.
- Branch: `feat/dismissable-banners`, cut from `origin/main` at `74b9695`.
- Spec: [Spec: Dismissable panel banners (#219)](https://github.com/yahyabedirhan/shipyard/issues/219).
- Tickets, in order:
  1. [Feature: Dismiss a panel banner for one hour (#220)](https://github.com/yahyabedirhan/shipyard/issues/220): no blockers.
  2. [Feature: Keep banner snoozes across restarts (#221)](https://github.com/yahyabedirhan/shipyard/issues/221): blocked by #220.

## What the maintainer asked

From a screenshot of the panel with four banners (refresh delay, "Can't reach GitHub", two remote machines' "Couldn't reach … through Herdr" lines): make the banners dismissable; a dismissed banner stays away for one hour and comes back if the issue persists. Small effort, built on its own branch, delivered as a working PR.

## Decisions taken by default

The maintainer may still change these; build with the defaults and list them in the PR's reviewer notes.

- A condition that clears during the hour clears its snooze, so a new occurrence shows at once.
- The configuration error banner and the lease's banners (and the "You took shipyard back" line) stay without a dismiss button.
- Snooze is keyed by banner id (`delay`, `paused`, `fetch`, `machine-<id>`, `config-warnings`, `notifications`), not by its words.

## Where the code is today

- The banner list is built in the app's panel view (`BannerItem` and `bannerItems` in `Sources/ShipyardApp/UI/Panel.swift`) and drawn by `Banner` in `Sources/ShipyardApp/UI/Components.swift`. Ticket #220 moves the list into ShipyardCore so a `Harness` scenario can own it.
- App state lives in `AppState` / `AppStateStore` (`Sources/ShipyardCore/State/AppStateStore.swift`); `RemotePingMarks` is prior art for a dismiss mark kept there.

## Reaching the maintainer's session

The session that wrote this runs in Herdr pane `w2V:p1`, on `main` in the main checkout; don't touch that checkout. Decide open questions yourself and list them in the PR. Ping the maintainer with `shipyard ping` when the PR is ready.

## Delivery

- Follow `AGENTS.md`: commit message style, `make test`, the testing gate, `docs/low-level-design.md` in the same change, `/to-pr` for the PR.
- This is a visual change: take screenshots of the installed build with `shipyard screenshot` (lease first, as AGENTS.md's Testing says), put them in the PR, and open the QA ticket when the tickets close. Leave hover and click checks to the maintainer.
- Don't merge: ask the maintainer.

## Suggested skills

- `orchestrate-effort` / `orchestrating`: run the tickets through delegates.
- `implement`, `tdd`, `write-swift`: for the delegates building each ticket.
- `shipyard`: driving the app (`shipyard control take`, `app`, `panel`, `screenshot`) and `shipyard ping`.
- `code-review`: before opening the PR.
- `to-pr`: the PR description.
