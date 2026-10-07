# The app reads notes through ntn, and keeps no Notion secret

ADR 0013 makes the notes opt-in: the app runs no `ntn` until the user presses Connect with ntn, so the consequence below that installing or logging in to ntn brings the notes back without a restart holds only once Notion is connected. The route stands.

This supersedes ADR 0011's reading route: the internal connection, its token pasted into the Connect Notion card and kept in the Keychain. ADR 0011's layout (Shipyard Notes, Projects, Agent guide) stands. **The app now reads and writes notes through `ntn`, Notion's CLI, with ntn's own login, and keeps no Notion secret of its own.** Each request `NotionClient` sends runs `ntn api <path>` once: ntn is the notes' HTTP transport (`NtnCLI`). This is the route for good, not a fallback, and the Connect Notion card, Connect Notion… and Disconnect Notion are gone.

The token in the Keychain made macOS ask for the login password again after every build (#234). Local builds are signed with a self-signed identity that has no Team ID, so macOS gives the "Shipyard Notion token" item a `cdhash:` partition, not a `teamid:` one. "Always Allow" adds the current build's `cdhash` to the partition list, and the next `make install` brings a new one: measured on 2026-10-07, the item's partition list held four `cdhash` entries, and the trusted-application entry still matched the stable designated requirement. While the prompt waited, the app didn't answer (#231). An app signed with an Apple Developer ID would get a stable partition, but a local build can't. With ntn, Keychain access is checked against ntn's process and ntn's own item, so a rebuild of shipyard changes nothing there.

The costs ADR 0011 named are accepted. ntn's login is tied to its default workspace, which can change without the app knowing: the notes banner says so when that workspace has no Shipyard Notes page, and `ntn doctor` shows which one it is. ntn's integration shares one rate budget with every agent using ntn. And ntn is in beta, so its exit codes and error lines are a contract the app depends on (`docs/references/notion-api.md`).

## Considered Options

- **The internal connection's token in the Keychain (ADR 0011).** Its own rate budget and a static token, but a Keychain prompt after every local build, and a card to set up.
- **Read `ntn auth token`, then call the API as now.** One process per refresh, not per request. But the app holds ntn's OAuth token in memory, must read it again when ntn refreshes it, and still depends on ntn's login and workspace. It saves little and keeps a secret in the app.
- **Run `ntn api` for each request (chosen).** The app never holds a token, even in memory; ntn refreshes its own login; and a request's shape stays the API's, so `NotionClient` and its recorded answers are unchanged. The cost is one short process per request, about a dozen a minute for a few projects, well under ntn's rate budget.

## Consequences

- `NtnCLI` finds `ntn` where its installer puts it (`~/.local/bin`), then Homebrew's paths, then `PATH`, since a menu bar app doesn't get the login shell's `PATH`. It gives `ntn` an empty standard input, since `ntn api` reads a request body from any standard input it's given and would wait for it.
- ntn's exit codes stand for Notion's statuses: exit 4 (logged out, no workspace, a token Notion stopped taking) is a 401, and exit 5 carries the API's status and code in its error line, "(404 Not Found object_not_found)".
- No `ntn`, ntn logged out, and no Shipyard Notes page in ntn's workspace each list no notes, with no error rows, and the notes banner says what to do. The new-note icons hide while ntn is missing or logged out. The notes are read again every minute, so installing or logging in to ntn brings them back without a restart.
- `shipyard notes check` reads the workspace through ntn, as the menu does.
- The first launch of this build deletes the old "Shipyard Notion token" item once. It looks for the item by its attributes alone, which reads no secret, and doesn't look again on later launches.
- A demo run reads no notes and never runs the user's ntn.
- The "Shipyard app" internal connection stays in Notion until the user removes it; nothing uses it.
- Sign in with GitHub still keeps its token in the Keychain, and a local build brings the same prompt back for it. `gh auth token` doesn't.
