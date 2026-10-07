# The app reads notes with an internal connection, under a Projects page

The reading route below, the internal connection and its token in the Keychain, is superseded by ADR 0012: the app reads notes through `ntn` and keeps no Notion secret. The layout stands.

ADR 0009 put one database per project directly under the "Shipyard Notes" entry page, and kept the agents' rules on that page. Two things changed. **The layout gains a level.** Shipyard Notes is now the user's home page, with two child pages: "Projects", which holds one database per project, titled exactly the project's name, and "Agent guide", which holds the rules for agents: the layout, the properties, the label and prefix conventions, and how to start a project's notes. The home page keeps a Projects index table (Project | Prefix | Notes) that agents keep current. Each project's database has the icon 🗂️ and two views, Open (`Status` isn't Archived, newest `No.` first, a quick filter on `Labels`) and Archived; the Projects page has the icon 📂. The app finds the entry page by search, then its child page titled exactly "Projects", then that page's child databases, and it never looks for a database anywhere else. **The app's route into Notion is decided.** It keeps a Notion internal connection's token, pasted once into the Connect Notion card and kept in the Keychain, and reads with nothing else.

With every database directly under it, the entry page was three things at once: the place the user opens, the agents' rule book and the parent of the databases. Notion's sidebar showed the databases mixed with the rules. Under the new layout the sidebar shows Projects and Agent guide, the home page is the user's, the rules have a page of their own, and the Projects page says by its name that more databases will come under it. Measured on 2026-10-06: moving a database to a new parent page keeps its notes and their unique-ID numbers, so a workspace from 0.3.0 moves over with nothing renumbered.

The route was settled once the maintainer's workspace showed the cost of a silent failure. The maintainer pasted a token from another workspace, and then didn't share the page with the connection. Both looked like "no notes", with no message. The app now says so in a panel banner, and `shipyard notes check` reads the workspace with the app's own token, so it reports what the menu sees.

## Considered Options

- **Databases directly under Shipyard Notes (ADR 0009's layout).** One level less to find. But the user's home, the agents' rules and every project's database share one page and one sidebar entry, and the page has nowhere to grow.
- **A Projects page under Shipyard Notes (chosen).** One more children listing per read when the app's memory of the page is gone, and a one-time move for a workspace from 0.3.0.
- **Reading `ntn auth token`, as the app reads `gh auth token`.** No token to paste. But ntn's token is an OAuth token that ntn refreshes, tied to ntn's login and to its *default* workspace, which can change without the app knowing; it shares one rate budget with every agent using ntn; and it makes the app depend on a CLI in beta. It works against the public API as a bot user, so it would have read the notes.
- **A personal access token.** It acts as the user and sees everything the user sees, not only the pages shared with it.
- **An internal connection (chosen).** It sees only the pages shared with it, its token is static, and it has its own rate budget, about three requests a second per connection. The cost is the setup the Connect Notion card walks through: create the connection in the notes workspace, add the Shipyard Notes page on its Access tab, paste its Internal Integration Secret.

## Consequences

- A workspace from 0.3.0 lists no notes until its databases are moved under a new page titled "Projects". `shipyard notes check` reports each database left directly under Shipyard Notes as an error.
- The new-note icon creates the Projects page (📂) under the entry page the first time it needs one, then the project's database (🗂️) under Projects. It still never writes the entry page, the Agent guide or the Projects index.
- The app can't create views: Notion's public API has no view endpoints. Claude's Notion connector can (`notion-create-view`, `notion-update-view`), so the Open and Archived views are the agents' to make, as the Agent guide says.
- A token that sees no Shipyard Notes page is not an empty list: the panel shows a banner that says to check the token's workspace and to share the page with the connection. With no token kept and a project that shows notes, the banner says to connect Notion.
- Agents still write notes with their own tools (Claude's Notion connector, Notion's hosted MCP or `ntn`). Only the app's reading route is decided here.
- Notion's facts this depends on are in `docs/references/notion-api.md`.
