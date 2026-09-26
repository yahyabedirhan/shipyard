# Configuration, for maintainers

How shipyard's configuration works inside the code, and what to touch when you add or change a setting. It's for the people who build shipyard. Users (and their agents) learn the file from the agent skill, [`skills/shipyard/SKILL.md`](../skills/shipyard/SKILL.md), which is the complete user-facing reference: every key, default, event and worked example lives there, not here.

The module design (state, operations, the refresh pipeline, the broken-edit trace) is in [the low-level design](low-level-design.md): see its sections *Configuration*, *ConfigStore*, *ConfigStore on change* and *Trace 2: a broken edit*. This document links to it rather than repeating it. Why the configuration is a TOML file agents edit is [ADR 0001](adr/0001-configuration-is-a-toml-file-agents-edit.md).

## The file

- It lives at `$XDG_CONFIG_HOME/shipyard/config.toml` when `XDG_CONFIG_HOME` is an absolute path, else `~/.config/shipyard/config.toml`. `ConfigStore.defaultURL` is the one place that decides; tests pass their own URL.
- A missing or empty file is `Configuration()`: every default and no projects, which puts the app in its project picker.
- Its first line is `#:schema <url>`, pointing at the published schema. Taplo and editors with TOML support use that line for completion and `taplo check`. The URL is `Configuration.schemaURL`.
- The app creates the file whenever it's missing: at every start (`Shipyard.start()`), when the Refresh button is clicked (`Shipyard.refreshNow()`), from the gear menu's **Open configuration file**, and on the picker's first append. It never touches a file that exists. A created file starts with `Configuration.header`: the `#:schema` line, a comment saying the file is edited by hand and by agents, `version = 1`, and the settings people reach for first as commented-out TOML at their defaults, each under a one-line comment: `[defaults.pull-requests] authors`, `[menu] layout`, `[menu-bar] count`, `[defaults] group-by` and `sort-by`, `[defaults.issues]` and `[defaults.workflow-runs]` `show`, a `[[defaults.notifications]]` rule and `[rate-limit] max-share-percent`. Top-level keys come above every table, and the tables above the projects the picker appends. A test reads the header as a configuration, again with each example uncommented alone, and again with all of them uncommented, so it can't teach a key that doesn't parse or a placement that breaks the file.
- The app never rewrites the file as a whole, because TOMLDecoder only decodes and a rewrite would lose the user's comments. It has two writers, each touching only its own lines:
  - `ConfigStore.append(projects:)`, the project picker's, adds `[[projects]]` blocks at the end: always valid TOML, nothing above it touched.
  - `ConfigStore.setLayout(_:)`, the header's layout button's (`Shipyard.switchToNextLayout()`), sets `[menu] layout` to `MenuLayout.next` of the current layout (the enum's case order is the cycle, wrapping; a new layout joins it by being added to the enum). The edit is `Configuration.settingLayout(_:in:)` in `LayoutSetting.swift`, which uses `TOMLSourceMap` to find the lines: it replaces the value of an existing `layout` key, keeping the line's comment; or adds `layout` under an existing `[menu]` header; or uncomments the header's `# [menu]` example (and its `# layout = …` line) when no live key sits between it and the next table, which uncommenting would pull into `[menu]`; or adds a `[menu]` table before the first table, above the comments right over it, or at the end of a file without tables. A file that doesn't read, or a `[menu]` in another form (an inline table, dotted keys, a `[menu.x]` sub-table), is refused, and so is any edit that wouldn't read back as the same configuration with only the layout changed. A refusal writes nothing and sets `Shipyard.configError`, so the banner says why; the next reload replaces it. The file is written in place (not renamed over), so a symlinked file stays a symlink. The menu then switches through the reload `setLayout` returns, as for a hand edit.

## Reading and validating

`Configuration.decode` (in `ConfigurationReader.swift`) turns the text into a `Configuration` plus warnings, or throws a `ConfigError`:

1. TOMLDecoder parses the text into a `TOMLTable`. A syntax error becomes one issue whose line comes from TOMLDecoder's own "(Line N)" description.
2. `ConfigurationReader` walks the table key by key, known table by known table. Each value is read with a typed accessor (`int`, `bool`, `string`, `choice`, …) that records an error at its key path when the type or value is wrong. Every problem is collected, so one save reports all of them, not the first.
3. `TOMLSourceMap`, a light second pass over the raw text, maps each key path (and, for a bad array element, the value) back to its line. That is where "line 14" in the banner comes from.
4. An unknown choice (an event, a count style) suggests the nearest valid one (`Suggestion.nearest`): "unknown event `pr.openned` (did you mean `pr.opened`?)". An author selector that doesn't read is rejected with its own hint (see Selectors and the listing below).
5. Unknown keys are **warnings**, not errors, so a file written for a newer shipyard still loads in an older one. So are the **old forms** the reader still accepts and turns into the new ones: a top-level `hide-authors`, and a notification rule's `authors` written as one string. `ConfigStore.warnings` holds them; the panel shows them in its quiet banner and `config-status.json` records them, but a misspelled key otherwise silently does nothing. The schema is the check that catches it, which is why the skill tells agents to run `taplo check`.
6. Cross-key rules the reader enforces and the schema can't express: project names unique, a repository listed once per project ignoring case.

`ConfigStore.reload()` is the only caller in the running app. A rejected file sets `error` and leaves `lastValid` alone: **the last valid configuration keeps running**, so a broken edit never blanks the menu (ADR 0001's first consequence). A valid file clears `error`, and reports `.changed` only when it means something different, so saving a comment edit doesn't refresh.

## Selectors and the listing

Authors (and, as they arrive, repositories) are named with **selectors** (ADR 0002): a bare word is a group, `@` marks a login, `/` a repository. The key a selector sits under says which set it's from, so groups need no symbol. `Config/Selectors.swift` holds them:

- `AuthorSelector` is `me`, `others`, `bots` or `.login`. `AuthorSelector(parsing:)` reads the file's spelling and throws a `Rejection` whose message is the banner's text: a bare word that isn't a group gets "did you mean `bots` or `@bots2`?", a repository group (`owned`, `organizations`, `collaborator`, `anywhere`) or an `owner/name` gets a hint that `authors` takes authors. `matches(author:kind:viewer:)` is the **only author match in the code**: `me` is an item the fetch marked as the viewer's, or whose login is the viewer's; `bots` a Bot account or a `[bot]` login; `others` neither; a login matches ignoring case.
- `AuthorFilter` is a kind's `authors = { show, hide }`: `includes` is `show` (empty: everyone) minus `hide`. `AuthorFilterOverrides` is what a table sets, merged key by key like the kinds' other settings, so a project's `hide` keeps the default `show`.
- A notification rule's `authors` is a list of `AuthorSelector` (empty: everyone), and `NotificationRule.covers` asks it.

`Items/Listing.swift` is **the one place that decides what a project has** (ADR 0003). `Listing.items(for:in:viewer:now:)` keeps the snapshot's items that pass every filter, combined with AND: the kind is shown, a closed or finished item is inside its window, a draft is allowed, the author passes the kind's `authors`. `Shipyard` builds every project's listing once per refresh (and again when a configuration change rebuilds the menu), and the consumers read nothing else:

- `MenuModel.build(listings:…)` draws the listings, so the rows, each header's count, the tabs' counts and the menu bar count are all of listed items.
- The notification step notifies an event only in a project that lists its item, and then only when a rule selects it; a rule's `authors` can narrow the listing but never reach past it.
- `EventDetector` and `KnownItems` still see **every fetched item**, listed or not. An item a filter hides is known all along, so when a later edit shows it, it isn't an `opened` event.

A new filter is one field (with its model, reader, schema and skill entries, as below) and one more check in `Listing.lists`; nothing else needs to learn about it.

The old forms stay readable: `hide-authors` becomes a `hide` of those logins in each kind's `[defaults.*]`, and a rule's `authors = "others"` becomes `["others"]` (`"any"` is `[]`), each with a warning that says what to write instead. The schema keeps them too, marked `"deprecated": true`, so `taplo check` passes every file the app reads; `ConfigSchemaTests` checks that the deprecated keys are exactly the ones `everyKey` leaves out.

## How a change reaches the app

1. **The watcher.** `ConfigWatcher` (in `Sources/ShipyardApp/`, since `DispatchSource` file-system sources are Darwin-only and the core builds on Linux) watches the file's **directory**, plus the file itself.
   - Editors and agents usually save by writing a new file and renaming it over the old one. A watch on the old file's descriptor would then be looking at a file that's gone, so the directory watch is what sees a **rename-replacement**.
   - An in-place write (`>>`) doesn't touch the directory, so the file watch sees that one.
   - Both watches are reopened after every change, since the file may be a new inode now. When the directory doesn't exist yet, its nearest existing ancestor is watched, so creating it is noticed.
2. **The debounce.** A save makes a burst of events; the watcher waits until they've been quiet for 200 ms and then calls back once.
3. **Live reload through the orchestrator.** The callback is `Shipyard.reloadConfiguration()`, which reloads the store and follows the result: it sets `configError` (which the panel's banner shows, ending in "Using the last valid configuration."), and on `.changed` it re-applies `launch-at-login`, moves the phase (projects or the picker), rebuilds the menu at once from the last snapshot, and refreshes. There is no restart and no separate apply step. The order and the corner cases (a paused budget, a failing fetch) are in the design's `reloadConfiguration()` row.

The core has no file watcher of its own: tests drive the same path by writing the file (`Harness.writeConfig`) and calling `reloadConfiguration()`.

## The verdict record, for agents

Agents edit the file but can't see the panel's banner, so after every reload (at launch, on each save the watcher sees, after the picker appends projects, and after the layout button sets the layout) `Shipyard` also writes its verdict to `~/Library/Application Support/Shipyard/config-status.json`, through `ConfigStatusStore` (in `ConfigStatus.swift`). The skill's "Checking an edit" tells agents to read it after saving.

```json
{
  "accepted" : false,
  "checked" : "2026-09-25T12:05:01Z",
  "config" : "/Users/me/.config/shipyard/config.toml",
  "configModified" : "2026-09-25T12:05:00Z",
  "problems" : [
    { "banner" : "config.toml line 1: …", "line" : 1, "message" : "…" }
  ],
  "version" : 1,
  "warnings" : []
}
```

- `checked` is when the app read the file; `configModified` is the file's modification time as it read it (taken before the bytes, so it never claims a newer file than was read), `null` when there was no file. Both are UTC in whole seconds, the form `date -u -r <file> +%Y-%m-%dT%H:%M:%SZ` prints, so an agent can tell the verdict is for its own save.
- `accepted` is `false` exactly when the banner shows. `problems` then lists every issue of the `ConfigError`, in file order; `warnings` lists the unknown settings an accepted file has. Each entry has its `line` (`null` when it can't be placed), the `message`, and `banner`, the entry's line in the panel's banner word for word (`PanelText.configIssue`, which the banners use too).
- It sits beside `state.json`, not beside `config.toml`: the watcher watches the configuration's directory, so a write there would trigger another reload. It's app-owned, replaced atomically on every reload (unchanged ones too), and never read back by the app. `version` follows the same rule as `state.json`'s: a new field isn't a new version, a renamed or changed one is.

## Configuration and app state

Two stores, kept apart on purpose (ADR 0001; the terms are in `CONTEXT.md`):

- **Configuration** is what the user chose: projects, what they show, windows, notification rules, the refresh interval, the layout. It's in `config.toml`, written by the user and their agents, and read-only to the app except for appending projects and the layout button's `[menu] layout`.
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
3. **The schema.** Add the key to `schema/config.schema.json` with its `description`, `type`, `default` and any `enum`, `minimum` or `maximum`, under the right table or definition (a project-overridable key goes in the shared definition both `defaults` and `project` reference). A key or spelling the reader still accepts as an old form stays in the schema, marked `"deprecated": true` (an old spelling of a value sits beside the new one in an `anyOf`).
4. **The new-file header.** When users should discover the setting from a fresh file, show it commented out at its default in `Configuration.header`, in the `# [table]` / `# key = value` form the header already uses, under a one-line comment with no ` = ` in it (the header test takes such lines for settings). A top-level key goes above the first commented table, a table among the others; keep each example's lines together, since the test uncommenting them one example at a time treats a run of setting lines as one example.
5. **The skill.** Add the key to `skills/shipyard/SKILL.md`: its row in the right keys table (`| key | default | allowed |`), any new choice or event, and a worked request when it answers something users will ask for. Tests fail until every schema key is named beside its table, every default matches the code, and every TOML example decodes cleanly and validates.
6. **The README.** When the setting is something a user meets before reading the skill, give it a line in `README.md`'s Configuration section. The README stays short; the skill is the reference.
7. **Tests at the configuration seam.** In `ConfigurationTests`, set the key in `everyKey` (away from its default) and add decode and rejection cases with their lines and messages. `ConfigSchemaTests` then checks the schema declares exactly the keys `everyKey` sets, and `choicesMatch` needs a line for a new enum.
8. **Tests at the orchestrator seam.** When the setting changes behaviour, test it through the `Harness`: write the file, `reloadConfiguration()`, and assert on what the user sees (the menu model, notifications, the timer), including that an edit applies live without a restart. A filter is tested for what it lists, counts and notifies, and for not notifying an item it brings back into view.
9. **The design doc.** Update `docs/low-level-design.md` in the same change: the example file under *Configuration*, and the module whose behaviour the setting changes.
