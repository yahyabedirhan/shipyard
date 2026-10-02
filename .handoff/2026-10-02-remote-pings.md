# Handoff: build shipyard 0.0.6, remote pings (effort `shipyard-0-0-6`)

You are the orchestrator for this effort. Build it end to end and deliver one pull request to the maintainer.

## Where

- **Machine:** `netcup-vps` (Debian 13, x86_64, 4 cores, 7 GB). You run in Herdr there.
- **Worktree:** `/home/yabepa/.treehouse/shipyard-1e47e3/1/shipyard`, a treehouse lease with holder `shipyard-0-0-6` and lease id `c809229960728051b460c4e696208e9a`.
- **Branch:** `effort/shipyard-0-0-6`, cut from `effort/shipyard-0-0-5` at `8da9f63`, the 0.0.5 pings effort, whose PR "feat: pings, sent by agents through the shipyard cli (0.0.5)" is open and not merged yet. The maintainer merges that one first.
- **Delegates' worktrees:** the harness's own sub-agent worktrees (`.claude/worktrees/`).
- **Spec:** #108 "Spec: shipyard 0.0.6, pings from agents on my other machines, through herdr". It is the source of truth for behaviour, decisions and verified Herdr facts. Read it in full first.
- **Tickets:** sub-issues of #108, label `effort:shipyard-0-0-6`, with native blocked-by edges.

  | Wave | Tickets |
  |---|---|
  | 0 | #109 The remote ping list contract |
  | 1 | #110 Send and list pings on a machine without the app (after #109) · #111 A machine's pings show in the Mac's menu (after #109) · #112 A blocked agent pings by itself · #113 Linux builds of the shipyard command on every release · #114 The herdr-shipyard plugin |
  | 2 | after #111: #115 File remote pings under the projects that watch them · #116 Notify for remote pings · #117 Click a remote ping · #118 Seen, dismiss and expiry for remote pings · #119 Machines that don't answer. And #120 Check remote pings on both VPSes, after #110, #112 and #114. **Read its comment: you do the netcup half only.** |
  | 3 | #121 Teach agents remote pings in the shipyard skill (after #112, #114, #115, #117) |

The maintainer asked for maximum parallelism. Run each wave's tickets in parallel and start a ticket as soon as its blockers close; don't wait for the whole wave. Wave 2's tickets all touch the orchestrator and the listing, so expect merge conflicts and resolve them as each one lands.

## How the maintainer wants it run

- **Fully autonomous.** The session that wrote this ran on the maintainer's Mac and can't be prompted from netcup. Decide open questions yourself: pick the simplest thing that's easy to explain to shipyard's users, and list every such decision in the pull request under a heading of its own.
- **Deliver to the end:** every ticket built and closed, tests green, a branch-wide `/code-review` and its fixes, then the pull request opened with `/to-pr`. Don't merge.
- **The pull request's base** is `effort/shipyard-0-0-5`, so its diff shows only 0.0.6. When the 0.0.5 pull request merges, the maintainer (or settle) retargets it to `main`. Say so in the pull request.
- **QA is non-blocking.** Once the visual work is built, open the QA ticket per AGENTS.md: `ready-for-qa`, assigned to the maintainer, linked both ways. Don't wait on it. Name the real-menu and real-machine checks in the pull request too: the spec's Testing Decisions list them, and the Hetzner and cross-machine checks from #120's comment.
- **The maintainer wants to see netcup's performance.** In the pull request, give each delegate's wall time and the total time from start to the pull request, as the 0.0.5 run did.

## Decisions settled with the maintainer (beyond the spec)

- **Parallel breakdown:** the waves above. #109 is a deliberate prefactor so the CLI side (#110) and the app side (#111) build at once.
- **Stacked:** on 0.0.5, as above.
- **herdr-shipyard repo:** `yahyabedirhan/herdr-shipyard`, **public**, MIT, topic `herdr-plugin`. Plugin id `yahyabedirhan.herdr-shipyard`, name `herdr-shipyard`; not just "shipyard", which is the app's name. #114 creates it with `gh repo create`. `gh` on netcup is signed in as the maintainer. It has its own commits and needs no pull request into shipyard; list its commits in shipyard's pull request.
- **Linux CLI:** comes from release assets that #113 adds to the release workflow. Nobody cuts a release in this effort: the maintainer cuts it after merging.
- **Transport:** shipyard reaches machines only through `herdr --machine <label>`, never `ssh`, and stores labels only (spec).

## Verifying on netcup

- **Toolchain:** Swift 6.4.0 through swiftly (`~/.local/share/swiftly`, loaded by `~/.profile`), and treehouse v3.1.1. The maintainer installed Swift's system libraries with apt, after this handoff was written. If `swift --version` fails with a missing shared library, stop and send a Blocked notification naming it.
- **Tests:** there's no `make test` here. `swift test` builds and tests `ShipyardCore` and the CLI; the app target is declared only on macOS. App-target code (rows, the unreachable line) is compiled only by CI's `macos` job on every push. After each batch's push, wait for both CI jobs (`gh run list --branch effort/shipyard-0-0-6`, `gh run watch`) and treat a red macOS job as a failed batch. Tell delegates that app-target code can't be compiled locally, so it must be small and mirror existing app code.
- **In the pull request under skipped checks:** `make test` and `make bundle` ran only in CI's macOS job.
- **Herdr here:** Herdr 0.9.3, with no saved machines, so `--machine` isn't available on netcup. Plugin actions and logs work locally without the prefix, which is enough for #120's netcup half.

## Notifying the maintainer

`osascript` doesn't exist here. Send Done and Blocked notifications with `herdr notification show "<message>" --sound done` (or `--sound request` for Blocked). They reach the maintainer's Mac through Herdr's machine connection.

## Suggested skills

- `orchestrate-with-handoff` (you were started with it), then `orchestrate-effort` and `orchestrating`
- `implement`, `tdd`, `low-level-design`, `code-review`: per delegate, as in 0.0.5
- `domain-modeling`: for the glossary entries and the ADR in #111
- `shipyard` and `writing-for-agents`: for #121 (the skill stays user-facing)
- `to-pr`: for the pull request
- `settle-session`: when done, without returning this worktree while it's occupied
