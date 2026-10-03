# Configuration has two files, each with one owner

Shipyard's settings live in two files. **`config.toml`** is the app's: it exists on the Mac only, and `ShipyardConfig` reads it. **`cli.toml`** is the `shipyard` command's, on every machine: agent-side code reads it, through `ShipyardCLISettings`. On a machine without the app it's `$XDG_CONFIG_HOME/shipyard/cli.toml` (`~/.config/shipyard/cli.toml` by default). On the Mac it sits beside the `config.toml` the app reads. Each `shipyard` build picks the place once, when it assembles its commands, as it picks its ping filing (ADR 0006).

**No setting appears in both files.** A setting belongs to the side that acts on it: what the app shows, listens for or notifies about goes in `config.toml`, and what the command does on the machine it runs on goes in `cli.toml`. A table's name may appear in both when each file's table holds only its own side's settings. `[notify]` is the first: `config.toml`'s says whether the app listens for notices, and `cli.toml`'s which Mac this machine sends them to.

The Mac's `shipyard ping` keeps reading `config.toml` to file pings against the projects, as ADR 0006 allows: only the Mac build links `ShipyardConfig`, and filing reads the app's projects rather than a setting of the command's own.

Notices (`shipyard notify`) are the first agent-side feature with a setting of its own, the Mac another machine sends notices to. A machine without the app has no `config.toml`, and giving it one would mean a file the app's reader doesn't know, read by a build that must never link that reader.

## Considered Options

- **One file, `config.toml`, on every machine.** A machine without the app would hold a file most of whose settings mean nothing there. The Linux command would need `config.toml`'s reader, which ADR 0006 keeps out of it, or a second reader of the same file that could drift from the first.
- **Command-line flags or environment variables only.** An agent would have to pass the target Mac on every notice, and a forgotten flag would send it the slow way without a word.
- **Two files, each with one owner (chosen).** Each file is read by one side only, so it's always clear where a setting goes and who acts on it.

## Consequences

- `ShipyardCLISettings` is an agent-side module beside Pings, depending on Command and TOMLDecoder. Both `shipyard` builds link it, so the Linux build now links TOMLDecoder; it still never links `ShipyardConfig`, `ShipyardControl` or `ShipyardCore`, and CI's link checks say so.
- A missing `cli.toml` is the defaults. A file that doesn't read, including an unknown key, fails the command that reads it with exit 1, naming the file and what's wrong. Unlike `config.toml`, an unknown key isn't a warning: a mistyped setting would otherwise quietly fall back to its default.
- The command reads `cli.toml` only when a command that needs a setting runs, so a broken file never stops `shipyard ping`.
- The app never reads `cli.toml`, and the command never writes either file.
