# Handoff: setup-views

Build the effort `setup-views` and deliver a working pull request against `main`.

## Where

- Worktree: `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/2/shipyard`, leased with treehouse (holder `setup-views`, lease id `2dc930088a886d11eb13f654202cab6b`). Keep the lease; the maintainer's session settles it after the merge.
- Branch: `feat/setup-views`, cut from `origin/main` at `57ca54b`.
- Spec: [Spec: setup-views, a status view for GitHub, Notion, the skill and the CLI (#237)](https://github.com/yahyabedirhan/shipyard/issues/237).
- Tickets, with their blockers:
  1. [Feature: The status view and the Shipyard CLI view (#238)](https://github.com/yahyabedirhan/shipyard/issues/238): no blockers.
  2. [Feature: The Shipyard Skill view, with skill detection (#239)](https://github.com/yahyabedirhan/shipyard/issues/239): blocked by #238.
  3. [Feature: The GitHub view (#240)](https://github.com/yahyabedirhan/shipyard/issues/240): blocked by #238.
  4. [Feature: Notion opt-in and the Notion view (#241)](https://github.com/yahyabedirhan/shipyard/issues/241): blocked by #238.
  5. [Feature: Open… on the notes and GitHub banners (#242)](https://github.com/yahyabedirhan/shipyard/issues/242): blocked by #240 and #241.
  6. [Feature: Show a header count's attention in blue, without the capsule (#243)](https://github.com/yahyabedirhan/shipyard/issues/243): no blockers.

## Notes

- The spec and #238 say to build on the branch of #235 (notes through `ntn`). #235 is merged, and `main` at `57ca54b` holds it, so this branch already builds on it.
- #243 is independent of the views and can run in parallel with #238.

## Reaching the maintainer's session

The session that wrote this runs in Herdr pane `w2V:p5`, on `main` in the main checkout; don't touch that checkout. It won't follow up. Decide open questions yourself and list them in the PR's reviewer notes. Ping the maintainer with `shipyard ping` when the PR is ready.

## Delivery

- Follow `AGENTS.md`: commit message style, `make test`, the testing gate, `docs/low-level-design.md` in the same change, `/to-pr` for the PR.
- This is a visual change: take screenshots of the installed build with `shipyard screenshot` (take the lease first, as AGENTS.md's Testing says; `shipyard panel` opens each status view per the spec), put them in the PR, and open the QA ticket when the tickets close. Leave hover and click checks to the maintainer.
- Don't merge: ask the maintainer.

## Suggested skills

- `orchestrate-effort` and `orchestrating` to run the tickets through delegates.
- `implement` and `tdd` for each delegate's ticket.
- `write-swift` for the Swift code.
- `shipyard` for app control, screenshots and the ping.
- `to-pr` for the pull request.
