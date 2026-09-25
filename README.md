# shipyard

A macOS menu bar app for seeing and reviewing the pull requests your agents open on your behalf.

Shipyard shows the pull requests (and, if you turn them on, issues and workflow runs) on the projects you choose, from anyone, you and your agents included. The menu bar shows one number: how many items still need your attention. Clicking an item opens it on GitHub and marks it seen. Everything it shows, and when it notifies you, lives in one commented TOML file under `~/.config/shipyard/` that you or your agents edit.

**Status:** under construction, version 0.0.1. Versions stay below 0.1.0 until the public launch.

## Platforms

Shipyard ships for **macOS only** (macOS 14 or later).

The package has two targets:

- `ShipyardCore`: every rule (configuration, the GitHub client, attention, events, notification rules, the rate budget, the menu model). It depends only on Foundation and TOMLDecoder, so it also **builds and tests on Linux, for development**. Linux isn't a supported platform for running shipyard.
- `ShipyardApp`: the macOS app (the `Shipyard` executable), a thin layer of Apple frameworks over the core. It's only part of the package on macOS.

## Development

```sh
swift build --target ShipyardCore   # the core, on macOS or Linux
swift test                           # the core's tests, on macOS or Linux
```

CI runs the core's tests on Ubuntu for every push and pull request.

The design is in `docs/low-level-design.md`, and the glossary in `CONTEXT.md`.
