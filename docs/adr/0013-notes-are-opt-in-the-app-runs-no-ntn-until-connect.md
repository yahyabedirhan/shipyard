# Notes are opt-in: the app runs no ntn until Connect with ntn

ADR 0012 has the app read notes through `ntn` from its first launch, for every user whose projects show notes, which is the default. A user who never wanted notes got an "Install ntn" banner, and the app looked for `ntn` and ran it every minute. **The notes are now opt-in.** `state.json` keeps a `notionConnected` flag, which holds no secret; ntn keeps its own login. Without it the app runs no `ntn` at all: no read at start, on the notes timer, when the menu opens or on a configuration change, no new-note icon, no notes banner, and `shipyard notes check` is refused. The settings menu's **Set up Notion…** opens the Notion view, which shows where ntn stands and, once ntn is logged in to a workspace, a **Connect with ntn** button that sets the flag and reads the notes. **Disconnect** clears it and takes the notes, the banner and the icons away.

The Notion view is the one place ntn runs before Connect with ntn: opening it, and its Check again, ask `GET /v1/users/me` for the name of ntn's default workspace and search for "Shipyard Notes", through the same route as the notes reads. The user opened the view to ask, so this doesn't break the opt-in; nothing runs `ntn` on its own.

## Considered Options

- **Keep ADR 0012's default: read notes whenever a project shows them.** No setup step for the maintainer. But every new user gets a banner about a tool they may never use, and the app spawns `ntn` every minute for them.
- **Turn notes off in `config.toml` by default (`[defaults.notes] show = false`).** A setting already exists. But connecting is a decision about this Mac's ntn login, not about which projects list notes, and an agent editing the configuration would turn it on without the user seeing which workspace ntn reads.
- **A flag in `state.json`, set by Connect with ntn in the Notion view (chosen).** The user sees ntn's workspace by name before connecting, the flag survives a restart, and it holds no secret. The cost is one click for users who already had notes.

## Consequences

- An existing user's `state.json` has no flag, so it reads as not connected: after the upgrade the notes stop until the user opens Set up Notion… and presses Connect with ntn once. The changelog says so.
- ADR 0012's consequence "installing or logging in to ntn brings them back without a restart" now holds only once connected. Before that, the Notion view's Check again shows the new status at once.
- The settings menu's Set up Notion… has a check mark while Notion is connected and the last read found ntn there and logged in.
- A demo run never runs the user's ntn: its view says that it reads no notes, and Connect with ntn does nothing there.
- `shipyard notes check` before Connect with ntn is refused with what to do, and runs no `ntn`.
