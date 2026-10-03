# Handoff: the agent lease (next effort, ships as 0.2.0)

A grilling session on 2026-10-03 (during effort `clean-slate`) agreed the design below with the maintainer. Nothing is built. Next step: start the effort (descriptive name, e.g. `agent-lease`) after `clean-slate`'s pull request merges and 0.1.0 is released, then `/to-spec` and `/to-tickets` from this handoff.

## Why

App control (0.1.0) lets agents open, steer and capture shipyard. Two agents can steer it at once, and the maintainer can't see that an agent is in the app. Like macOS's recording dot or Claude in Chrome's cursor, agent use should be visible, and one agent at a time should hold the app.

## The agreed design

- **A lease, not a plain lock:** it expires by itself, so a crashed agent can't hold the app.
- **What needs it:** every `shipyard app`, `panel` and `screenshot` command. `app status` stays free and reports the lease (holder name and where, time left, number waiting; `--json` has `"lease": null` when free).
- **Enforced at the socket:** the app refuses a command without the lease, exit 1, naming the holder and when it ends. It's as strong as one user account allows; an agent writing its own socket client could ignore it.
- **Taking and holding:** the first app-control command takes it implicitly and each command renews it; `shipyard control take` and `shipyard control release` for longer runs.
- **Duration:** renewed by each command for 1 minute, hard cap 5 minutes.
- **The holder key is automatic,** worked out by the CLI on every call, with nothing for the agent to pass:
  1. the agent's session id when it exports one (Claude Code's `CLAUDE_CODE_SESSION_ID`; Codex's or another agent's equivalent);
  2. otherwise the agent's own process: the nearest non-shell parent of the CLI, as pid plus start time.
  Herdr's pane id is not part of the key: it is written into a pane's environment at spawn, so it's stable, but it's a positional name another pane could later reuse. `take --key <k>` is an escape hatch for unusual setups.
- **Another agent:** refused at once by default; `--wait <seconds>` queues it, first come first served.
- **Relaunches:** `app quit`, `app open` and `app open --demo` hand the holder's lease to the app they launch, so a restart doesn't free it.
- **What the maintainer sees:**
  - a yellow dot on the menu bar icon while the lease is held;
  - a banner at the top of the panel: "<Agent> in <folder or Herdr pane> is using shipyard · 48s · Stop", plus "1 waiting" when others queue. The agent's name and logo come from what pings already know about agents;
  - macOS notifications posted by the app itself (not ping rows) when a lease starts and ends, as new notification-rule events `control.started` and `control.ended`, notified by default and switched off like any other event. The maintainer's own `config.toml` lists its rules, so the events must be added there to reach them (say so in QA). Clicking the notification opens the panel with the banner showing.
- **The maintainer acts:** Stop in the banner ends the lease. That agent's next command is refused ("the user took shipyard back; ask them before using it again") and it can't take the lease again for 5 minutes, unless the maintainer allows it. The maintainer's own clicks never end or fight a lease.
- **Captures:** `shipyard screenshot` hides the dot and banner by default; `--with-indicator` keeps them.
- **Taught:** the shipyard skill gains a "Taking turns" part (`take`, `release`, `--wait`, the refusals, what to do after Stop). `AGENTS.md`'s Testing section says to hold the lease for a run of real-app steps and release it at the end, and the lease's own notifications replace the hand-sent "Starting/Done" `osascript` notifications.
- **Version:** a `feat`, so the release is 0.2.0 (the Releases rule), not 0.1.1.

## Out of scope

Leasing apps on other machines; protecting against a process that bypasses the CLI.
