# Handoff: build Mac-assigned ping numbers (effort ping-numbers)

You orchestrate one ticket to a pull request: #153 "The Mac numbers pings per project, in the order they arrive". The ticket holds what to build, every decision and the acceptance criteria. Read it first, then its parent spec #125 for context. #125's other tickets (#126–#129) aren't part of this effort.

## Where

- **Worktree:** `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/1/shipyard`, a treehouse lease (holder `ping-numbers`, lease id `51dc4f139fedf304f24aac28a6993f1a`).
- **Branch:** `effort/ping-numbers`, cut from `main` at `edba8e1`, with no upstream until its first `git push -u`.
- **Tracker labels:** `effort:shipyard-0-0-7`, and the ticket is `ready-for-agent`.

## How it came about

- In QA of remote pings (#134), the maintainer saw netcup-vps's pings with no number in the menu.
- The cause: `PingList.ListedPing` in `Sources/ShipyardCore/Pings/PingList.swift` reads a fixed set of fields that predates #136, so it drops `number`.
- Rather than fix that drop, the maintainer chose to replace #136's per-machine numbers with numbers the Mac gives out, one sequence per project. A number reads like an issue's: smaller means earlier. Every decision is in #153.

## Working autonomously

- The maintainer said: work autonomously and don't ask further questions. Decide any open question yourself, in the spirit of #153, and list each decision under the pull request's "Decided alone".
- The session that wrote this handoff runs in the maintainer's Mac Herdr. Don't rely on it; it may be gone.
- Open the pull request with `/to-pr`, and notify the maintainer (global `notification-method`) when it's ready. Don't merge it; the maintainer approves merges.
- `make test` is the check. Agents can't click or script the menu (AGENTS.md, Testing). Name the checks the maintainer has to make in the real menu in the pull request.
- Per AGENTS.md's QA section, this changes what the maintainer sees, so once it's built, open a `ready-for-qa` ticket linked both ways with #153.

## Things to know

- **Remote QA is still going (#134):**
  - Both VPSes (netcup-vps, hetzner-vps) run a `shipyard-cli` built from `edba8e1`, put in place by the herdr-shipyard plugin, which is linked from a local clone at `~/Developer/yahyabedirhan/herdr-shipyard`. They still number their own pings.
  - The Mac must ignore a `number` they list, which #153 requires.
  - After the merge, the VPSes need a rebuild so `shipyard ping` prints only the id. The build and install steps are in #134's body.
- **Ping state on the Mac:** `~/Library/Application Support/Shipyard/state.json` keeps the remote pings' seen and dismiss marks under `remotePings`, keyed by the ping's URL. The new counters probably belong beside them. Settle that against `docs/low-level-design.md` and update the design in the same change.
- **Constraint tracked elsewhere:** #152, "A remote ping's click can't switch the Mac's Herdr window to its machine". It isn't part of this effort.

## Suggested skills

- `orchestrate-effort` and `orchestrating`: run the effort and delegate the ticket.
- `implement` and `tdd`: build #153 test-first through `Harness` and `ShipyardCLI.run`.
- `low-level-design`: where the counter lives, and the design doc update.
- `domain-modeling`: if `GLOSSARY.md` defines a ping number.
- `code-review`: before opening the pull request.
- `to-pr`: the pull request.
- `settle-session`: when done.
