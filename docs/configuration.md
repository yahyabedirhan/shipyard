# Configuration, for maintainers

How shipyard's configuration works inside the code, and what to touch when you add or change a setting. It's for the people who build shipyard. Users (and their agents) learn the file from the agent skill, [`skills/shipyard/SKILL.md`](../skills/shipyard/SKILL.md), which is the complete user-facing reference: every key, default, event and worked example lives there, not here.

The module design (state, operations, the refresh pipeline, the broken-edit trace) is in [the low-level design](low-level-design.md): see its sections *Configuration*, *ConfigStore*, *ConfigStore on change* and *Trace 2: a broken edit*. This document links to it rather than repeating it. Why the configuration is a TOML file agents edit is [ADR 0001](adr/0001-configuration-is-a-toml-file-agents-edit.md).

## The file

- It lives at `$XDG_CONFIG_HOME/shipyard/config.toml` when `XDG_CONFIG_HOME` is an absolute path, else `~/.config/shipyard/config.toml`. `ConfigStore.defaultURL` is the one place that decides; tests pass their own URL.
- A missing or empty file is `Configuration()`: every default and no projects, which puts the app in its project picker.
- Its first line is `#:schema <url>`, pointing at the published schema. Taplo and editors with TOML support use that line for completion and `taplo check`. The URL is `Configuration.schemaURL`.
- A file the app creates (the gear menu's **Open configuration file**, or the picker's first append) starts with `Configuration.header`: the `#:schema` line, a comment saying the file is edited by hand and by agents, `version = 1`, and settings shown as commented-out TOML (`# [menu]`, `# layout = "list"`). A test reads the header as a configuration, and again with those lines uncommented, so it can't teach a key that doesn't parse.
- The app never rewrites the file, because TOMLDecoder only decodes and a rewrite would lose the user's comments. The one writer is `ConfigStore.append(projects:)`, which adds `[[projects]]` blocks at the end: always valid TOML, nothing above it touched.

## Reading and validating

`Configuration.decode` (in `ConfigurationReader.swift`) turns the text into a `Configuration` plus warnings, or throws a `ConfigError`:

1. TOMLDecoder parses the text into a `TOMLTable`. A syntax error becomes one issue whose line comes from TOMLDecoder's own "(Line N)" description.
2. `ConfigurationReader` walks the table key by key, known table by known table. Each value is read with a typed accessor (`int`, `bool`, `string`, `choice`, …) that records an error at its key path when the type or value is wrong. Every problem is collected, so one save reports all of them, not the first.
3. `TOMLSourceMap`, a light second pass over the raw text, maps each key path (and, for a bad array element, the value) back to its line. That is where "line 14" in the banner comes from.
4. An unknown choice (an event, an author filter, a count style) suggests the nearest valid one (`Suggestion.nearest`): "unknown event `pr.openned` (did you mean `pr.opened`?)".
5. Unknown keys are **warnings**, not errors, so a file written for a newer shipyard still loads in an older one. `ConfigStore.warnings` holds them; the panel doesn't show them yet, so to a user a misspelled key silently does nothing. The schema is the check that catches it, which is why the skill tells agents to run `taplo check`.
6. Cross-key rules the reader enforces and the schema can't express: project names unique, a repository listed once per project ignoring case.

`ConfigStore.reload()` is the only caller in the running app. A rejected file sets `error` and leaves `lastValid` alone: **the last valid configuration keeps running**, so a broken edit never blanks the menu (ADR 0001's first consequence). A valid file clears `error`, and reports `.changed` only when it means something different, so saving a comment edit doesn't refresh.

## How a change reaches the app

1. **The watcher.** `ConfigWatcher` (in `Sources/ShipyardApp/`, since `DispatchSource` file-system sources are Darwin-only and the core builds on Linux) watches the file's **directory**, plus the file itself.
   - Editors and agents usually save by writing a new file and renaming it over the old one. A watch on the old file's descriptor would then be looking at a file that's gone, so the directory watch is what sees a **rename-replacement**.
   - An in-place write (`>>`) doesn't touch the directory, so the file watch sees that one.
   - Both watches are reopened after every change, since the file may be a new inode now. When the directory doesn't exist yet, its nearest existing ancestor is watched, so creating it is noticed.
2. **The debounce.** A save makes a burst of events; the watcher waits until they've been quiet for 200 ms and then calls back once.
3. **Live reload through the orchestrator.** The callback is `Shipyard.reloadConfiguration()`, which reloads the store and follows the result: it sets `configError` (which the panel's banner shows, ending in "Using the last valid configuration."), and on `.changed` it re-applies `launch-at-login`, moves the phase (projects or the picker), rebuilds the menu at once from the last snapshot, and refreshes. There is no restart and no separate apply step. The order and the corner cases (a paused budget, a failing fetch) are in the design's `reloadConfiguration()` row.

The core has no file watcher of its own: tests drive the same path by writing the file (`Harness.writeConfig`) and calling `reloadConfiguration()`.

## Configuration and app state

Two stores, kept apart on purpose (ADR 0001; the terms are in `CONTEXT.md`):

- **Configuration** is what the user chose: projects, what they show, windows, notification rules, the refresh interval, the layout. It's in `config.toml`, written by the user and their agents, and read-only to the app except for appending projects.
- **App state** is what shipyard remembers from use: seen items, collapsed sections, the items it knew last refresh, what it already notified. It's in `~/Library/Application Support/Shipyard/state.json`, owned by `AppStateStore`, and never written to the configuration.

The test when a new value arrives: if the user would want to set it on purpose, or an agent would want to change it for them, it's configuration; if it only records what happened while the app ran, it's app state. Keeping them apart is what lets the app treat the file as read-only: it never has to save its own memory into a file full of the user's comments, and an agent editing the file never races the app writing to it.

## How the schema is published

`schema/config.schema.json` is the public contract (JSON Schema draft-07; Taplo applies it to TOML). It's published by being on `main`: its `$id`, `Configuration.schemaURL` and every file's `#:schema` line are all the raw GitHub URL on the `main` branch, and a test keeps those three equal. There is no build or upload step.

Two consequences:

- A schema change reaches every user's editor and `taplo check` when it's merged to `main`, before any release ships the code that reads it. Merge it together with that code, and keep it accepting every file the released app accepts: a key added early only lets through a setting the installed app ignores, but a key removed or narrowed early fails files that still work.
- Changing what a key means, renaming one or removing one is a breaking change: it needs the `version` key and a migration in `Configuration.decode` (the design's *Extensibility* table).

The schema is stricter than the reader on purpose: `additionalProperties: false` everywhere, so `taplo check` rejects the unknown keys the app only warns about.

## Adding or changing a setting

Do every step in the same change; the tests fail on most of the ones you miss.

1. **The model and its default.** Add the field, with its default, to `Configuration.swift` (a top-level field, a table's struct, or an override type with its `applied(to:)` when a project can override it). A new choice is a `CaseIterable` string enum.
2. **The reader.** In `ConfigurationReader.swift`, read the key with the typed accessor, record errors for out-of-range values at the key's path, and add the key to its table's `warnUnknownKeys` known list (otherwise it's reported as unknown).
3. **The schema.** Add the key to `schema/config.schema.json` with its `description`, `type`, `default` and any `enum`, `minimum` or `maximum`, under the right table or definition (a project-overridable key goes in the shared definition both `defaults` and `project` reference).
4. **The new-file header.** When users should discover the setting from a fresh file, show it commented out in `Configuration.header`, in the `# [table]` / `# key = value` form the header already uses.
5. **The skill.** Add the key to `skills/shipyard/SKILL.md`: its row in the right keys table (`| key | default | allowed |`), any new choice or event, and a worked request when it answers something users will ask for. Tests fail until every schema key is named beside its table, every default matches the code, and every TOML example decodes cleanly and validates.
6. **The README.** When the setting is something a user meets before reading the skill, give it a line in `README.md`'s Configuration section. The README stays short; the skill is the reference.
7. **Tests at the configuration seam.** In `ConfigurationTests`, set the key in `everyKey` (away from its default) and add decode and rejection cases with their lines and messages. `ConfigSchemaTests` then checks the schema declares exactly the keys `everyKey` sets, and `choicesMatch` needs a line for a new enum.
8. **Tests at the orchestrator seam.** When the setting changes behaviour, test it through the `Harness`: write the file, `reloadConfiguration()`, and assert on what the user sees (the menu model, notifications, the timer), including that an edit applies live without a restart.
9. **The design doc.** Update `docs/low-level-design.md` in the same change: the example file under *Configuration*, and the module whose behaviour the setting changes.
