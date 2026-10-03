# App control is leased, enforced by the app

App control needs a **lease**: one agent at a time holds it. Every `shipyard app`, `panel` and `screenshot` command needs the lease. The first one takes it, and each one after renews it. It ends by itself a minute after the holder's last command, and five minutes after it was taken at most, so a crashed agent can't keep it. Asking for the app's status needs no lease, and reports who holds it.

The app enforces it. Every control request carries its **holder**, and the app's control server asks the lease before it does anything. A command from another holder is refused with exit 1, naming the holder, their place and when the lease ends. The rules are a pure value in ShipyardControl (`ControlLease`), given the time on each call, so they build and test on Linux; the app owns the one instance and drives it (ADR 0006).

The `shipyard` command works out the holder on every call, so agents pass nothing. The key is the agent's session id when the agent exports one (Claude Code's `CLAUDE_CODE_SESSION_ID`), otherwise the nearest ancestor of the command that isn't a shell, as its pid plus its start time. For a setup where neither stays the same across an agent's commands, `SHIPYARD_CONTROL_KEY` in the environment names the key for every command, over both (#178). Herdr's pane id is the holder's place, never part of its key: another pane could later reuse it.

App control arrived in 0.1.0 with nothing to stop two agents using it at once: one folded a project while the other took a screenshot, and each got a result the other spoiled. The maintainer couldn't tell that an agent was in the app at all.

## Considered Options

- **A plain lock** that an agent takes and releases. A crashed agent, or one that forgets, would hold the app until someone noticed. A lease ends by itself.
- **Enforced by the `shipyard` command**, through a lock file it checks before sending. Any older or other build of the command would ignore it, and the app would have no say. The app answering every request is the one place every command passes through.
- **An explicit holder**, a name each agent passes. Agents would get it wrong, or pass a different one from each subshell. The session id, or the agent's own process, is the same across its commands without the agent doing anything.
- **Herdr's pane id as the key.** It's stable for a pane's life, but it's a positional name another pane can reuse, and agents outside Herdr have none.

## Consequences

- The control protocol is at version 2: every request carries `holder`, and a request of version 1 is refused naming both versions, so a `shipyard` from another build than the app is told to reinstall.
- `app status` stays free, and its lines and JSON report the lease (`"lease": null` when it's free).
- It's as strong as one user account allows: an agent writing its own socket client could leave the lease out. That's out of scope.
- `control take`, `release` and `--wait` (holding the lease for a longer run, and queueing for it), a relaunch handing the lease over, the maintainer seeing and stopping the holder, and the lease's notifications build on the same arbiter and wire.
