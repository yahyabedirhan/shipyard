# Agents send pings through a shipyard CLI

Agents send **pings** with a `shipyard` command-line tool that ships inside `Shipyard.app` and that the app offers to link onto the user's `PATH`: `shipyard ping "<title>" …` sends or replaces a ping, and `shipyard ping withdraw <id>` withdraws one. The CLI writes into shipyard's own storage, so a ping sent while the app isn't running shows up when it starts, and an agent never needs to know where or how pings are kept.

ADR 0001 ruled out a CLI for the configuration, and that still holds: the configuration stays a file that agents edit. Pings are different. They're data the app owns, not the user's choices, so a file format would turn shipyard's storage into a public contract, and a URL scheme makes long text awkward and needs the app to launch. A CLI keeps the storage private and leaves room for other commands later.

## Consequences

- The CLI's commands and flags are a public contract that agents depend on, like the configuration's schema.
- `ping` is one subcommand of a general `shipyard` CLI, not a separate tool.
- The shipyard skill teaches agents the CLI, just as it teaches them the configuration.
