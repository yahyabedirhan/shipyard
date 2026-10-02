# Remote pings go through Herdr

Agents on the user's other machines (VPSes) ping with the same `shipyard ping` as on the Mac, and the Mac's shipyard reads those **remote pings** through Herdr: a Herdr plugin, herdr-shipyard, installed on each machine declares a `list` action that prints `shipyard ping list --json`, and the Mac runs that action with `herdr --machine <label>` over the connection its Herdr already keeps to the saved machine, then reads the action's output from Herdr's command log. The Mac polls each machine named in `[remote] machines` on a timer of its own.

We considered the other ways a ping could cross machines and turned them down:

- **A server or relay** (a hosted service, ntfy, a gist, webhooks): a third party in the path of every ping, an account to keep, and a place where the user's pings would live outside their machines.
- **An open port on the Mac** (the machines push to the app): a listener on the user's laptop, reachable from wherever the machines are, which shipyard would have to secure.
- **SSH run by shipyard**: shipyard would hold hosts, users and keys, and grow its own way into the user's servers. The Mac's Herdr already reaches them over SSH, with the user's own setup.

Herdr is already the user's one connection to these machines, its saved machines are named by labels rather than addresses, and its plugins can run a command on the machine and hand back its output. So shipyard needs no transport of its own.

**Trust runs one way: the Mac reaches out, a machine never reaches in.** The Mac asks; a machine only answers an action the Mac invoked, and can't open a connection to the Mac or start anything there. What a machine lists is data the Mac reads (a version-checked JSON document, `PingList`), never a command it runs.

This supersedes the 0.0.5 out-of-scope line "pings from other machines".

## Consequences

- The configuration names machines by their Herdr labels only, never a host or an address; a label starting with `-` is rejected so it can't read as a flag of `herdr`.
- `shipyard ping list --json` is part of the CLI's public contract (ADR 0004), with a major version the Mac refuses to read across.
- Plugin actions take no arguments, so nothing flows back to a machine: seeing and dismissing a remote ping stay on the Mac.
- A remote ping arrives up to one poll (30 seconds) late, and a machine Herdr can't reach keeps its last pings listed until it answers again.
