# Remote pings follow-ups from the Mac

An agent on netcup-vps left two follow-ups it couldn't run from there. This session ran on the maintainer's Mac and did what it could.

## Done

- Added `[remote] machines = ["netcup-vps", "hetzner-vps"]` to the maintainer's `~/.config/shipyard/config.toml`, below `[herdr]` with a comment. Both labels are machines saved in the Mac's Herdr (`herdr machine list`). `taplo check` against `schema/config.schema.json` passes.
- `config-status.json` says `"accepted": true`, with one warning: `unknown setting remote (ignored)`. The installed app is **0.0.3** (`/Applications/Shipyard.app`), and `[remote]` arrived in 0.0.6 (PR #143, issue #108). The warning goes away once a release built from current main is installed. Don't remove the table.

## Waiting on the maintainer

- **Cutting the release.** The latest GitHub release is v0.0.3. #147 holds the checklist: `Sources/ShipyardCore/Version.swift` must match the tag, and the release must list the `shipyard-linux-*` binaries and their `.sha256` files.

## Next steps, once the release exists

1. Install the new app on the Mac. Then read `~/Library/Application Support/Shipyard/config-status.json` again and confirm the `remote` warning is gone.
2. Run the rest of #147. On `netcup-vps` and `hetzner-vps`, run `herdr plugin install yahyabedirhan/herdr-shipyard`, going through each saved Herdr machine in a new workspace, never plain SSH (see the global CLAUDE.md). Then check from the Mac that `herdr --machine <label> plugin action invoke list --plugin yahyabedirhan.herdr-shipyard` and `plugin log list` work for both machines. Post the results as a comment on #147.
3. Agents can't drive the real menu, so checking that the remote sections show up is the maintainer's job.

## Side note

The shipyard skill installed at `~/.claude/skills/shipyard` is older than `skills/shipyard/SKILL.md` in this repository: it has nothing about `[remote]`, pings or `[defaults.pings]`. Read the repo copy when editing the config. You can also offer to update the installed skill (through maintain-environment).

## Suggested skills

- `shipyard`: any further `config.toml` edit. Read the repo's `skills/shipyard/SKILL.md` until the installed copy is updated.
- `herdr`: reaching the VPSes for the plugin install and checks.
- `maintain-environment`: updating the installed shipyard skill from the repo.
- `settle-session`: when done.
