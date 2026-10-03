# Modules follow concerns: agent-side code never links the app's rules

Shipyard's code is split into modules by concern, not by platform, and each build links only the modules it uses. **ShipyardCommand** is the foundation any command needs on any machine. **ShipyardPings** is the agent side of pings. **ShipyardConfig** reads `config.toml`. **ShipyardControl** is the client side of app control. **ShipyardCore** keeps the app's rules: GitHub, items, the menu, app state and the Mac's side of pings. **ShipyardApp** is the macOS app. The `shipyard` command on Linux links Command and Pings only. On macOS it links Config and Control too, but never Core. The app links everything. **Agent-side code never links the app's rules.**

Where a ping is filed is the one thing the two `shipyard` builds do differently, and it sits behind one interface, **PingFiling**. On a machine without the app, **Unfiled** keeps a ping as the agent sent it, and the Mac files it when it reads the machine's list (ADR 0005). On the Mac, **ProjectFiling** files it against the configuration. The executable picks one when it starts, so no ping code checks the platform at run time. The command table adds `app`, `panel` and `screenshot` only where Control is linked.

ADR 0004 made `shipyard` a general command line with room for more commands, and ADR 0005 put it on machines without the app. Until 0.1.0 it was a wrapper over the whole core. Its Linux build carried the GitHub client, the menu model and the configuration reader without using them, and the ping command asked the platform at run time whether to read `config.toml`. Agent-facing features would keep arriving (app control in 0.1.0, notes perhaps later), and none had a clean place to go.

## Considered Options

- **One core with a command table.** Keep one library and register commands by platform. It's the smallest change, but the Linux binary would still link everything, and nothing would stop agent-side code from reaching into the app's rules.
- **Two executables, `shipyard` and `shipyardctl`.** App control would get a binary of its own. That adds a second name for agents to learn and a second thing to install and link, with no more isolation than modules give: the ping side would still link the core.
- **The app files every ping.** The CLI would always save pings unfiled and leave filing to the app, so the Mac `shipyard` wouldn't need Config either. But a ping no project takes, or one every project hides, could no longer be refused while the agent waits. And with the app quit, an agent would get exit 0 for a ping the maintainer will never see.
- **Modules by concern ("A+", chosen).** Command, Pings, Config and Control are the agent's side. Core and App are the app's side. A build links only the modules it uses, and filing is an interface with one implementation per kind of machine. Refusals keep working on the Mac with the app quit. A new agent feature, such as notes, is one new module beside Pings plus one line in the command table.

## Consequences

- Dependencies run one way: Command ← Pings, Config, Control. Pings ← Config, so ProjectFiling can implement PingFiling. Core depends on Command, Pings and Config (not Control: only the app's side of control uses its types); App depends on all of them. A module on the agent's side importing Core is a design change, not a shortcut.
- `Package.swift` makes Config and Control dependencies of the `shipyard` executable on macOS only. The executable's `main.swift` picks the filing and assembles the command table at compile time.
- CI fails if the Linux `shipyard` links Config, Control or Core, and if the Mac `shipyard` links Core.
- A type that both sides use moves down to the lowest module that needs it. Code that matches an item or reads the menu stays in Core, as an extension, even when the type it extends lives lower down: the item kinds and state groups belong to Config, while matching an `Item` against them belongs to Core.
- `docs/low-level-design.md` keeps the module table and each build's links. A change that moves a module boundary updates both in the same change.

## Amendment, 2026-10-03: the command's own settings

ADR 0008 gives the `shipyard` command a settings file of its own, `cli.toml`, read by a new agent-side module, **ShipyardCLISettings** (Command and TOMLDecoder). Both builds link it, so the Linux `shipyard` now links TOMLDecoder, and CI's link checks no longer refuse it. They still refuse Config, Control and Core: the Linux build never reads `config.toml`.
