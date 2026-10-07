# Handoff: drop-token-banner-open

Build the effort `drop-token-banner-open` and deliver a working pull request against `main`.

## Where

- Worktree: `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/3/shipyard`, leased with treehouse (holder `drop-token-banner-open`, lease id `cfa048a5a372cdc919c57f5b5f51fa46`). Keep the lease; the effort's settle frees it after the merge.
- Branch: `chore/drop-token-banner-open`, cut from `origin/main` at `d35686e` (the merge of #245).
- Spec: none. The one ticket holds the whole change.
- Ticket: [Chore: Drop Open… from the rejected-token banner (#247)](https://github.com/yahyabedirhan/shipyard/issues/247): no blockers. Label `effort:drop-token-banner-open`.

## Why

The setup-views effort (#237, merged in #245) gave the notes banner and the rejected-token banner an **Open…** action (#242). A 401 signs shipyard out at once, so the rejected-token banner almost never shows, and its **Open…** would open the signed-out content the user already sees. The maintainer decided to drop that half and keep the notes banner's **Open…** (decision D1 of the setup-views session).

## Notes

- The change is small and low-risk: no own `/code-review`; the one branch review at delivery covers it.
- No visual QA ticket: the banner it changes almost never shows. The ticket says so.
- `make test` is the only way to run the tests on this Mac; plain `swift test` can't find the Testing module.
- Don't edit the closed issues #237 and #242.

## Reaching the maintainer's session

The session that wrote this runs in Herdr pane `w3B:p1`, in the setup-views worktree (slot 2); don't touch that worktree. It won't follow up. Decide open questions yourself and list them in the PR's reviewer notes. Ping the maintainer with `shipyard ping` when the PR is ready.

## Delivery

- Follow `AGENTS.md`: commit message style, `make test`, the testing gate, `docs/low-level-design.md` in the same change, `/to-pr` for the PR.
- Close #247 when its commit is pushed and its criteria are ticked; the PR says `Closes #247`.
- Don't merge: ask the maintainer.

## Suggested skills

- `orchestrate-effort` and `orchestrating` to run the ticket through a delegate.
- `implement` for the delegate's ticket.
- `to-pr` for the pull request, and `shipyard` for the ping.
