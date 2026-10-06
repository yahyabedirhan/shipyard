# Notes structure: where to pick up

Branch `feat/notes-structure`, pull request #230 "Notes under a Projects page, a notes banner and shipyard notes check". It waits for the maintainer's approval; don't merge before it. The branch build is installed on the Mac.

## Done

- **Notion, restructured** in the maintainer's notes workspace: Shipyard Notes (the user's home: start here, a Projects index, a diagram) → Projects (📂, every database) and Agent guide (🤖, the rules). `workstation` (WORK) and `havooch` (HAVO, was Review Video, RVID-1 is now HAVO-1) sit under Projects with Open and Archived views and the 🗂️ icon. ADR 0011 records the layout and the internal-connection-only decision.
- **The app:** reads databases only under Projects; a notes banner (connect Notion, or the token sees no Shipyard Notes page); the Connect Notion card's three steps; the notes count opens the database in Notion; the new-note icon is compact and centred; created pages and databases get their icons; the Notion token is read once per launch.
- **`shipyard notes check`:** the app checks the workspace with its own token. Run with `ntn`'s token through a throwaway test, the check read the new layout as in order (workstation 2 open, havooch 1 open).
- **Keychain prompts:** `make signing-identity` made "Shipyard Local Signing" in `~/Library/Keychains/shipyard-signing.keychain-db`, added to the user's keychain search list. `make bundle` signs with it; `make release` stays ad-hoc.

## Waiting on the maintainer

1. Answer the last Keychain prompt for "Shipyard Notion token" with **Always Allow**. The app doesn't answer until then (#231 "Bug: The app stops answering while macOS asks for Keychain access").
2. Share Shipyard Notes with the "Shipyard app" connection (••• → Connections). Until then `shipyard notes check` says the token sees no Shipyard Notes page, and the banner says so.
3. QA #229 "QA: Notes under a Projects page, the notes banner and shipyard notes check" together with #202 "QA: Notes in the menu and the new-note icon".
4. Approve #230; then merge, release (CLAUDE.md's Releases), and carry it to the machines.

## Not done

- Views on a database the new-note icon creates: the public API has none, so agents add them (the Agent guide says how). `notes check` doesn't check views or icons.
- The real menu's notes rows and the count's click are unchecked in the real app: the connection can't see the page yet, and clicks are the maintainer's.
