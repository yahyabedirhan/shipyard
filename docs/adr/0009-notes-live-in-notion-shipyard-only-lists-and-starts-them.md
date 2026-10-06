# Notes live in Notion: shipyard only lists them and starts new ones

The user's **notes** live in Notion, in a workspace of their own: an entry page, "Shipyard Notes", with one database per shipyard project under it, titled exactly the project's name. Notion is the notes' store, their editor and what keeps every device in sync. Agents write notes into Notion through whatever their harness has (Claude's Notion connector, Notion's hosted MCP, or the `ntn` CLI), following the shipyard skill's notes reference. Shipyard's app does two things with them: it lists each project's open notes in the menu, and its new-note icon creates a project's database when there's none, then an empty note in it. It never edits a note. ADR 0011 moved the databases under a "Projects" page beneath the entry page, and the agents' rules to an "Agent guide" page beside it.

The user wants to dictate a thought to any agent, on the Mac, on another machine or in Claude on their phone, and find it later by project and number. A note has to be written from places shipyard doesn't run, read and edited on every device, and numbered once for all of them. Notion already does each of these, and every harness the user has can already reach it.

## Considered Options

- **A shipyard notes module beside pings** (ADR 0006's example of where a new agent feature would land): a `shipyard note` command, notes kept as files by `RecordStore`, remote machines' notes read through Herdr as pings are. Shipyard would own an editor, sync between machines and a phone route it doesn't have, and a note written in Claude on the phone could never reach it.
- **GitHub issues.** Already listed in the menu and numbered per repository. But the user's ideas would mix with the issues agents open all day, which is the problem notes solve.
- **Notion, read and started by the app (chosen).** The app holds one internal connection token in the Keychain, shared with the entry page only, and asks Notion's API for each project's open notes. The fixed core (the database's title and its `Name`, `No.`, `Labels` and `Status` properties) is written in the skill, so a change to it is reviewed before the menu depends on it.

## Consequences

- No `shipyard note` command and no notes module on the agent side. ADR 0006's example of notes as "one new module beside Pings" no longer describes a planned feature; its module rules still hold for the next agent-side feature.
- A project matches its notes database by title alone, and no Notion ids go into `config.toml`. Renaming a project or its database loses the match until the other is renamed too.
- A note's number is Notion's unique ID: it counts up per database, can't be written and is never reused, even after a trash. So notes are archived by their `Status`, never trashed.
- The structure beyond the fixed core (label conventions, views, sub-page kinds, each project's prefix) lives on the entry page, which agents update before they grow it. ADR 0011 moved it to the Agent guide page.
- The app depends on Notion's API: an outage or a revoked token shows as an error on the project, never as an empty list. Its facts are in `docs/references/notion-api.md`.
