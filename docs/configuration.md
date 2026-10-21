# Configuration, for maintainers

How shipyard's configuration works inside the code, and what to touch when you add or change a setting.
This file is for the people who build shipyard, not the user reference the docs site publishes under the same name: users (and their agents) learn every key from the agent skill, [`skills/shipyard/SKILL.md`](../skills/shipyard/SKILL.md).

The document follows these sections, in order:

1. **References**: the design and the decisions this document links to.
2. **Modules**: where the configuration code lives.
3. **File location**: which file the app and the command read.
4. **Creation and header**: when the app creates the file, and what a new file holds.
5. **Writers**: the three places the app writes the file.
6. **Reading and validating**: how the text becomes a `Configuration`, its errors and warnings.
7. **Selectors and the listing**: how authors and repositories are named, and what a project lists.
8. **Live reload**: how a saved edit reaches the running app.
9. **Verdict record**: `config-status.json`, the reload's verdict for agents.
10. **`shipyard config check`**: the same verdict without the app.
11. **Configuration and app state**: the two stores and the test between them.
12. **Schema publishing**: how `schema/config.schema.json` reaches editors.
13. **`cli.toml`**: the command's own file.
14. **Themes**: what to touch for a theme change.
15. **Adding or changing a setting**: the checklist.

## References

- **The skill.** [`skills/shipyard/SKILL.md`](../skills/shipyard/SKILL.md) is the complete user-facing reference: every key, default, event and worked example lives there, not here.
- **The low-level design.** The module design (state, operations, the refresh pipeline, the broken-edit trace) is in [the low-level design](low-level-design.md): see its sections *Configuration*, *ConfigurationStore*, *ConfigurationStore on change* and *Trace 2: a broken edit*.
  This document links to it rather than repeating it.
- **ADR 0001.** Why the configuration is a TOML file agents edit is [ADR 0001](adr/0001-configuration-is-a-toml-file-agents-edit.md).

## Modules

| Module | Holds |
|---|---|
| `Sources/ShipyardConfig/` (ADR 0006) | Reading the file: the model, the reader, the selectors' parsing, the windows, the layout edit and `ConfigurationStore`. The Mac's `shipyard` links it to file pings without the app's rules. |
| `Sources/ShipyardCore/Config/` | What only the app does with the configuration: matching items against selectors, presets and their writer, and `config-status.json`. |

## File location

- **The app's file.** It lives at `$XDG_CONFIG_HOME/shipyard/config.toml` when `XDG_CONFIG_HOME` is an absolute path, else `~/.config/shipyard/config.toml`.
  `ConfigurationStore.defaultURL` is the one place that decides; tests pass their own URL.
- **The command's lookup.** The Mac's `shipyard` command files pings against the file the app reads, not the one its own shell's `XDG_CONFIG_HOME` points at: the app, started from Finder, may not see a variable set in `.zshrc`.
  At every start the app records its file's path in `config-location.json` in its support folder, beside `repositories.json` (`ConfigurationLocation`), and the command reads it there.
  Before the app has ever run, the command looks the file up itself, as `ConfigurationStore.defaultURL` does (#126).
- **A missing or empty file.** It is `Configuration()`: every default and no projects, which puts the app in onboarding: its preset step, or its project picker.
- **The schema line.** The file's first line is `#:schema <url>`, pointing at the published schema.
  Taplo and editors with TOML support use that line for completion and `taplo check`.
  The URL is `Configuration.schemaURL`.

## Creation and header

### Creation

The app creates the file whenever it's missing:

- at every start (`Shipyard.start()`);
- when the Refresh button is clicked (`Shipyard.refreshNow()`);
- from the gear menu's **Open configuration file**;
- on the picker's first append.

It never touches a file that exists, except through the [writers](#writers).

### Header

A created file starts with `Configuration.header`:

- the `#:schema` line;
- a comment saying the file is edited by hand and by agents;
- `version = 1`;
- the settings people reach for first, as commented-out TOML at their defaults, each under a one-line comment: `theme`, `[defaults.pull-requests] authors`, `[menu] layout`, `[menu-bar] count`, `[defaults] group-by`, `sort-by` and `show-first`, `[defaults.issues]` `show` and `states`, `[defaults.workflow-runs]` `show`, `[defaults.pings]` `show` and `seen-window`, `refresh-interval`, the five default `[[defaults.notifications]]` rules and `[rate-limit] max-share-percent`;
- a comment (not an example, since it has no default to show) telling Herdr users to set `[herdr] terminal`.

Top-level keys come above every table, and the tables above the projects the picker appends.

### Header test

A test reads the header as a configuration, again with each example uncommented alone, and again with all of them uncommented.
So the header can't teach a key that doesn't parse or a placement that breaks the file.

## Writers

The app never rewrites a file that holds the user's settings, because TOMLDecoder only decodes and a rewrite would lose their comments.
It has three writers (ADR 0001 and its amendments).
The first two touch only their own lines, and the third writes a whole file only over one that holds nothing of the user's.

| Writer | Caller | Writes |
|---|---|---|
| `ConfigurationStore.append(projects:)` | the project picker | `[[projects]]` blocks at the end |
| `ConfigurationStore.setLayout(_:)` | the header's layout button (`Shipyard.switchToNextLayout()`) | `[menu] layout` |
| `ConfigurationStore.writePreset(_:projects:)` | onboarding's preset step (`Shipyard.choosePreset(_:projects:)`) | a whole preset file |

### Project picker: `append(projects:)`

It adds `[[projects]]` blocks at the end: always valid TOML, nothing above it touched.

### Layout button: `setLayout(_:)`

It sets `[menu] layout` to `MenuLayout.next` of the current layout.
The enum's case order is the cycle, wrapping; a new layout joins it by being added to the enum.

**The edit.** It is `Configuration.settingLayout(_:in:)` in `LayoutSetting.swift`, which uses `TOMLSourceMap` to find the lines.
It does the first of these that applies:

1. Replaces the value of an existing `layout` key, keeping the line's comment.
2. Adds `layout` under an existing `[menu]` header.
3. Uncomments the header's `# [menu]` example (and its `# layout = …` line) when no live key sits between it and the next table, which uncommenting would pull into `[menu]`.
4. Adds a `[menu]` table before the first table, above the comments right over it, or at the end of a file without tables.

**Refusals.** These are refused:

- a file that doesn't read;
- a `[menu]` in another form (an inline table, dotted keys, a `[menu.x]` sub-table);
- any edit that wouldn't read back as the same configuration with only the layout changed.

A refusal writes nothing and sets `Shipyard.configError`, so the banner says why; the next reload replaces it.

**The write.** The file is written in place (not renamed over), so a symlinked file stays a symlink.
The menu then switches through the reload `setLayout` returns, as for a hand edit.

### Preset step: `writePreset(_:projects:)`

It writes `Preset.text(projects:)`: the whole commented file of `my-agents`, `incoming-contributions` or `review-queue`, with the repositories picked for it.

**When it writes.** Only when the file is missing or its only live key is `version`, as in `Configuration.header`.
`Configuration.acceptsPreset(_:)` (beside `ConfigurationStore`, which records it) reads the file and asks `TOMLSourceMap` for its entries.
Comments and blank lines don't count, but any other key or any table, even an empty one, does.

**Refusals.** Each is refused with a `ConfigurationError`, and nothing is written:

- a file with anything else, or one that doesn't read;
- the picker's projects when one is invalid (as for `append`);
- the picker's projects when the preset wouldn't read with them (a picked project named like the preset's own).

**The preset list.** Every reload records the same check in `ConfigurationStore.acceptsPreset`, and `Shipyard.presets` follows it.
It holds all three while a preset may be written, and none once the file has settings, when onboarding shows the plain picker instead.

**The recheck.** `writePreset` checks the file again before writing, so a setting saved since the last reload is never overwritten.
It's the core's, in `ConfigurationStore+Preset.swift`, since presets are the app's.
`choosePreset` then reloads, and onboarding falls back to the picker.

**The write.** An existing file is written in place, so a symlinked file stays a symlink.
The menu follows the reload `writePreset` returns, as after the picker: with projects, the phase moves to `ready` and the first refresh runs, without a restart.

## Reading and validating

### Decode steps

`Configuration.decode` (in `ConfigurationReader.swift`) turns the text into a `Configuration` plus warnings, or throws a `ConfigurationError`:

1. TOMLDecoder parses the text into a `TOMLTable`.
   A syntax error becomes one issue whose line comes from TOMLDecoder's own "(Line N)" description.
2. `ConfigurationReader` walks the table key by key, known table by known table.
   Each value is read with a typed accessor (`int`, `bool`, `string`, `choice`, …) that records an error at its key path when the type or value is wrong.
   Every problem is collected, so one save reports all of them, not the first.
3. `TOMLSourceMap`, a light second pass over the raw text, maps each key path (and, for a bad array element, the value) back to its line.
   That is where "line 14" in the banner comes from.
4. An unknown choice (an event, a count style) suggests the nearest valid one (`Suggestion.nearest`): "unknown event `pr.openned` (did you mean `pr.opened`?)".
   An author selector that doesn't read is rejected with its own hint (see [Selectors and the listing](#selectors-and-the-listing)).
5. Unknown keys and the other cases under [Warnings](#warnings) are warnings, not errors.
6. The reader enforces the [cross-key rules](#cross-key-rules).

### Warnings

These are **warnings**, not errors:

- **Unknown keys**, so a file written for a newer shipyard still loads in an older one.
- **The old forms** the reader still accepts and turns into the new ones (see [Old forms](#old-forms)).
- **A file that sets any key without `version`.** It reads, and from version 2 it will be an error.
- **Rules that mean nothing for app control's events**, `control.started` and `control.ended` (since 0.2.0, #182): one in a project's own list (only the top-level rules decide them), and one with `authors` (no item's author sends one).
  Each is read and ignored.

`ConfigurationStore.warnings` holds them.
The panel shows them in its quiet banner and `config-status.json` records them, but a misspelled key otherwise silently does nothing.
The schema is the check that catches it, which is why the skill tells agents to run `taplo check`.

### Old forms

Each old form reads with a warning that says what to write instead.

| Old form | New form |
|---|---|
| a top-level `hide-authors` | a `hide` of those logins in each kind's `[defaults.*]` |
| a notification rule's `authors` written as one string: `authors = "others"` | `["others"]` (`"any"` is `[]`) |
| a kind's `closed-window-days` (a whole number of days): `closed-window-days = 3` | `closed-window = "3d"` |
| a kind's `finished-window-hours` (a whole number of hours): `finished-window-hours = 4` | `finished-window = "4h"` |
| `refresh-interval-seconds` (a whole number of seconds): `refresh-interval-seconds = 90` | `refresh-interval = "90s"` |
| `[banners] snooze` | `snooze-duration` |
| a project's `name` (since 0.6.0, #255) | its `title`, with a `slug` made of it |

- **Old beside new.** An old key beside its new one in one table is an error instead, as is `name` beside `slug` or `title`.
- **The slug.** `Configuration.slug(from:)` makes it: lowercased, each run of characters other than `a`–`z` and `0`–`9` one hyphen, none at either end.
- **Old project names.** `--project` (`shipyard ping`, `shipyard notice send`) finds a project by its slug, then by its title (`Configuration.project(named:)`), so an older `shipyard` that sends a project's old name still files under it.
  The app names each filed ping's projects by slug the same way (`ProjectFiling.named`), so pings filed before the rename stay listed.
- **The schema.** It keeps the old forms too, marked `"deprecated": true`, so `taplo check` passes every file the app reads.
  `ConfigSchemaTests` checks that the deprecated keys are exactly the ones `everyKey` leaves out.

### Cross-key rules

The reader enforces these, and the schema can't express them:

- Project slugs are unique: the second one is rejected on its line, `slug` or the old `name` it was made from.
- A repository is listed once per project, ignoring case.
- A project using `anywhere` lists pull requests with `review-requested = true` and no issues or runs, once its defaults are merged; otherwise it's rejected on the `anywhere` entry's line.

### Reload

`ConfigurationStore.reload()` is the only caller in the running app.

- **A rejected file** sets `error` and leaves `lastValid` alone: **the last valid configuration keeps running**, so a broken edit never blanks the menu (ADR 0001's first consequence).
- **A valid file** clears `error`, and reports `.changed` only when it means something different, so saving a comment edit doesn't refresh.

## Selectors and the listing

### Selectors

Authors and repositories are named with **selectors** (ADR 0002): a bare word is a group, `@` marks a login, `/` a repository.
The key a selector sits under says which set it's from, so groups need no symbol.
`ShipyardConfig/Selectors.swift` holds them, and the core's `Config/Selectors+Items.swift` matches them against authors and items.

- **`AuthorSelector`** is `me`, `others`, `bots` or `.login`.
  `AuthorSelector(parsing:)` reads the file's spelling and throws a `Rejection` whose message is the banner's text:
  - a bare word that isn't a group gets "did you mean `bots` or `@bots2`?";
  - a repository group (`owned`, `organizations`, `collaborator`, `anywhere`) or an `owner/name` gets a hint that `authors` takes authors.

  `matches(author:kind:viewer:)` is the **only author match in the code**:
  - `me` is an item the fetch marked as the viewer's, or whose login is the viewer's;
  - `bots` is a Bot account or a `[bot]` login;
  - `others` is neither;
  - a login matches ignoring case.
- **`AuthorFilter`** is a kind's `authors = { show, hide }`: `includes` is `show` (empty: everyone) minus `hide`.
  `AuthorFilterOverrides` is what a table sets, merged key by key like the kinds' other settings, so a project's `hide` keeps the default `show`.
- **A notification rule's `authors`** is a list of `AuthorSelector` (empty: everyone), and `NotificationRule.covers` asks it.
- **`RepositorySelector`** is one entry of a project's `repositories`:
  - `.repository` (`owner/name`, as written);
  - `.owner` (`owner/*`);
  - `.group` (`owned`, `organizations`, `collaborator`, the `RepositoryGroup` cases);
  - `.anywhere` (no lookup: the review search's pull requests; `ProjectSettings.usesAnywhere`, and `resolved(by:)` keeps it).

  `RepositorySelector.parse` throws a `RepositorySelectorRejection` whose message is the banner's text:
  - an author group or an `@login` gets a hint that `repositories` takes repositories (and, for a login, to write `owner/*`);
  - a misspelt group gets the nearest one;
  - a bare login gets "did you mean `owner/*`".

  The reader keeps the selectors as written; `ProjectSettings.repositorySlugs` is the single repositories among them.
  `ProjectSettings.resolved(by:)` swaps the selectors for what `RepositoryResolver` found, each as `owner/name`, which is what the fetch, the query plan and the known sources read.
  `archived` and `forks` (in `[defaults]` and per project) are read by the resolver only.

### Listing

`Items/Listing.swift` is **the one place that decides what a project has** (ADR 0003).
`Listing.items(for:in:viewer:now:)` keeps the snapshot's items that pass every filter, combined with AND:

- the kind is shown;
- the item's `StateGroup` (`ItemState.group`) is in the kind's `states`;
- a closed or finished item is inside its window;
- a draft is allowed;
- the author passes the kind's `authors`.

`Shipyard` builds every project's listing once per refresh, again when a configuration change rebuilds the menu, and at each timer firing while the rate budget pauses.

### Listing consumers

The consumers read nothing else:

- **The menu.** `MenuModel.build(listings:…)` draws the listings, so the rows, each header's count, the tabs' counts and the menu bar count are all of listed items.
- **Notifications.** The notification step notifies an event only in a project that lists its item, and then only when a rule selects it; a rule's `authors` can narrow the listing but never reach past it.
- **App control's lease events.** These (`EventKind.isControl`: `control.started`, `control.ended`) aren't an item's, so no listing or project is involved.
  `NotificationRules.shouldNotify(_:configuration:)` asks only the top-level rules, `[[defaults.notifications]]` or the built-in list (`Configuration.Defaults.notifications`, which holds both).
  The app hands each lease that starts or ends to `Shipyard.notify(_:)` as a `ControlNotice`.
- **An agent's notice.** `agent.notice` (since effort `notes-and-notify`, #190) isn't an item either, but it belongs to projects.
  `NoticeRules` files it as a ping is filed (the one project it names, or every project watching its repository).
  It shows it under the first of those whose own rules select `agent.notice`, a project's `notifications` list or the defaults, as for any project event; a rule with `authors` never selects one.
  It's in the built-in list, so a file without `[[defaults.notifications]]` shows notices everywhere.
  No listing is involved, and nothing is kept.
- **Event detection.** `EventDetector` and `KnownItems` still see **every fetched item**, listed or not.
  An item a filter hides is known all along, so when a later edit shows it, it isn't an `opened` event.

### Windows

The windows (`closed-window`, `finished-window`, `pings.seen-window`) are held in seconds and written as a whole number and one unit, `s`, `m`, `h` or `d`.
`ShipyardConfig/ConfigurationDuration.swift` is the one parser, and suggests the nearest spelling for a near miss such as `"30min"` or `"1h30m"`.
The schema's `pattern` takes exactly what it takes.
They count back from the clock at each listing, and the timer fires at least every refresh interval, pause or not, so a closed item leaves within an interval of its window passing.

### New filters

A new filter is one field (with its model, reader, schema and skill entries, as in [Adding or changing a setting](#adding-or-changing-a-setting)) and one more check in `Listing.lists`.
Nothing else needs to learn about it.

## Live reload

1. **The watcher.** `ConfigurationWatcher` watches the file's **directory**, plus the file itself.
   It's in `Sources/ShipyardApp/`, since `DispatchSource` file-system sources are Darwin-only and the core builds on Linux.
   - Editors and agents usually save by writing a new file and renaming it over the old one.
     A watch on the old file's descriptor would then be looking at a file that's gone, so the directory watch is what sees a **rename-replacement**.
   - An in-place write (`>>`) doesn't touch the directory, so the file watch sees that one.
   - Both watches are reopened after every change, since the file may be a new inode now.
     When the directory doesn't exist yet, its nearest existing ancestor is watched, so creating it is noticed.
2. **The debounce.** A save makes a burst of events; the watcher waits until they've been quiet for 200 ms and then calls back once.
3. **Live reload through the orchestrator.** The callback is `Shipyard.reloadConfiguration()`, which reloads the store and follows the result.
   - It sets `configError`, which the panel's banner shows, ending in "Using the last valid configuration.".
   - On `.changed` it re-applies `launch-at-login`, moves the phase (projects or the picker), rebuilds the menu at once from the last snapshot, and refreshes.
   - There is no restart and no separate apply step.
   - The order and the corner cases (a paused budget, a failing fetch) are in the design's `reloadConfiguration()` row.

The core has no file watcher of its own: tests drive the same path by writing the file (`Harness.writeConfig`) and calling `reloadConfiguration()`.

## Verdict record

### Writes

Agents edit the file but can't see the panel's banner, so `Shipyard` also writes its verdict to `~/Library/Application Support/Shipyard/config-status.json` after every reload:

- at launch;
- on each save the watcher sees;
- after the picker appends projects;
- after onboarding writes a preset;
- after the layout button sets the layout.

`ConfigurationStore.check(at:)` gives the latest reload's `ConfigurationCheck` (in `Sources/ShipyardCommand/`), and `ConfigStatusStore` (in `ConfigStatus.swift`) writes it.
The skill's "Checking an edit" tells agents to read it after saving.

### Format

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

### Fields

- **`checked` and `configModified`.** `checked` is when the app read the file.
  `configModified` is the file's modification time as it read it (taken before the bytes, so it never claims a newer file than was read), `null` when there was no file.
  Both are UTC in whole seconds, the form `date -u -r <file> +%Y-%m-%dT%H:%M:%SZ` prints, so an agent can tell the verdict is for its own save.
- **`accepted`, `problems` and `warnings`.** `accepted` is `false` exactly when the banner shows.
  `problems` then lists every issue of the `ConfigurationError`, in file order; `warnings` lists the unknown settings an accepted file has.
  Each entry has its `line` (`null` when it can't be placed), the `message`, and `banner`, the entry's line in the panel's banner word for word (`ConfigurationCheck.banner`, which `PanelText.configIssue` and so the banners use too).
- **`version`.** It follows the same rule as `state.json`'s: a new field isn't a new version, a renamed or changed one is.

### Location and lifetime

- It sits beside `state.json`, not beside `config.toml`: the watcher watches the configuration's directory, so a write there would trigger another reload.
- It's app-owned, replaced atomically on every reload (unchanged ones too), and never read back by the app.

## `shipyard config check`

`shipyard config check` gives the record's verdict without the app, so an agent can check an edit when the app isn't running, or on a machine without it.
The skill's edit steps tell agents to run it after each edit.

### Ownership and builds

- `ConfigurationCommands` (in `Sources/ShipyardCommand/`) owns the command.
  The executable hands it one check per file, so the command never links a file's reader.
- The Mac's build checks `config.toml` and each theme file with `ConfigurationStore.checks(_:at:)`, a fresh store's `reload()`, and `cli.toml` with `CLISettingsFile.check(at:)`.
- The Linux build checks only `cli.toml` and never links `ShipyardConfig`.
- On the Mac, `config.toml` is the file `config-location.json` names, as for `shipyard ping` (`ConfigurationLocation.current`), and the `themes` folder and `cli.toml` are beside it.

### Output

- **Text.** It prints `config.toml`, then each theme file in file-name order, then `cli.toml`: each file's path and `accepted` or `rejected`, then a `problem:` or `warning:` line for each issue in the banner's words.
  A missing file is `accepted (no file: the defaults)`.
- **`--json`.** It prints one object, each file's `ConfigurationCheck` under its name (`config.toml`, `themes/<file>`, `cli.toml`), in the record's fields.
  Both encode through `ConfigurationCheck`, so the `config.toml` entry and `config-status.json` match field for field when they read the same file at the same time; `ConfigurationCheckTests` holds that.
- **Exit codes.** It exits 1 when a file has a problem, else 0; a bad argument exits 2.

### Scope

- A `cli.toml` has no warnings: what it doesn't know is a problem (see [`cli.toml`](#clitoml)).
  Neither has a theme file.
- `config-status.json` holds `config.toml`'s verdict alone: a theme file's problems show in the panel's banner and in `config check` (ADR 0014).

## Configuration and app state

Two stores, kept apart on purpose (ADR 0001; the terms are in `GLOSSARY.md`):

| Store | What it holds | Where | Who writes it |
|---|---|---|---|
| **Configuration** | what the user chose: projects, what they show, windows, notification rules, the refresh interval, the layout | `config.toml` | the user and their agents; read-only to the app except for appending projects, the layout button's `[menu] layout`, and the preset onboarding writes into a file that holds nothing but `version` |
| **App state** | what shipyard remembers from use: seen items, collapsed sections, the items it knew last refresh, what it already notified | `~/Library/Application Support/Shipyard/state.json` | `AppStateStore`; never written to the configuration |

The test when a new value arrives:

- if the user would want to set it on purpose, or an agent would want to change it for them, it's configuration;
- if it only records what happened while the app ran, it's app state.

Keeping them apart is what lets the app treat the file as read-only.
It never has to save its own memory into a file full of the user's comments, and an agent editing the file never races the app writing to it.

## Schema publishing

`schema/config.schema.json` is the public contract (JSON Schema draft-07; Taplo applies it to TOML).
It's published by being on `main`: its `$id`, `Configuration.schemaURL` and every file's `#:schema` line are all the raw GitHub URL on the `main` branch, and a test keeps those three equal.
There is no build or upload step.

Two consequences:

- **Merge timing.** A schema change reaches every user's editor and `taplo check` when it's merged to `main`, before any release ships the code that reads it.
  Merge it together with that code, and keep it accepting every file the released app accepts.
  A key added early only lets through a setting the installed app ignores, but a key removed or narrowed early fails files that still work.
- **Breaking changes.** Changing what a key means, renaming one or removing one is a breaking change: it needs the `version` key and a migration in `Configuration.decode` (the design's *Extensibility* table).

The schema is stricter than the reader on purpose: `additionalProperties: false` everywhere, so `taplo check` rejects the unknown keys the app only warns about.

## `cli.toml`

`cli.toml` holds the `shipyard` command's own settings, on every machine (ADR 0008).

### Location and reader

- **Location.** Beside `config.toml` on the Mac, in `$XDG_CONFIG_HOME/shipyard/` (default `~/.config/shipyard/`) elsewhere.
- **Reader.** `CLISettings.decode`, in `Sources/ShipyardCLISettings/`, reads it; the Linux build links that module and never `ShipyardConfig`.
- **A missing file** is the defaults.
- **Errors.** An unknown key, a value of the wrong type and invalid TOML are errors, not warnings: the command that reads the file fails with exit 1, naming the file and what's wrong.
  `shipyard config check` lists the same problems without running a command that needs the file.

### Example

```toml
#:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/cli.schema.json
version = 1

[notices]
app-machine = "my-mac"
# app-scheme = "http"
# app-port = 47420
```

### Version

- `version` is the file's format, `CLISettings.supportedVersion` (1).
- A file without it reads as version 1 with no warning, since a warning would print on every `shipyard notice send`.
- Any other version is an error that names the version this build reads.
- An older `shipyard` rejects `version` as an unknown key, so a machine's `shipyard` is updated before its `cli.toml` gains the line.

### Schema

- `schema/cli.schema.json` is published as `config.schema.json` is: its `$id`, `CLISettings.schemaURL` and the `#:schema` line of the examples here and in `skills/shipyard/references/notices.md` are one URL on `main`, and `CLISettingsSchemaTests` keeps them equal.
- Its `additionalProperties: false` rejects unknown keys as the reader does, and the test checks it declares exactly the keys the reader takes, with its choices and port range.

### New setting

A new `cli.toml` setting is:

1. a property on its table's struct;
2. a key in `CLISettings.Reader`'s known list, and its read;
3. a property in the schema;
4. a line in `CLISettingsSchemaTests`' `everyCLIKey`, and its key list;
5. read and rejection cases in `CLISettingsTests`;
6. the skill's notices reference.

## Themes

The `theme` key picks a theme by name, and its themes come from two places (ADR 0014):

- the six built-in themes, embedded in `Sources/ShipyardConfig/Theme/` as `BuiltInThemes+<Name>.swift`;
- the user's theme files, every `*.toml` in the `themes` folder beside `config.toml`.

The module design is the low-level design's *Themes*; this section is what to touch.
The file format, for users and their agents, is `skills/shipyard/references/themes.md`, and `docs/themes/example-custom.toml` is the commented example theme the tests read.

- **The reader.** `ThemeReader` in `ThemeReader.swift` reads a theme file with TOMLDecoder and `TOMLSourceMap`, as `ConfigurationReader` reads `config.toml`, but strictly.
  An unknown key, section or token is a problem, not a warning, since a mistyped colour would otherwise draw the default without a word.
- **A file with a problem.** It keeps the theme it last read, and its problems reach the panel's banner through `Shipyard.themeIssues`; it never rejects `config.toml`.
  A `theme` that names a file that never read is a warning on its line.
- **A new token.** A case in `ThemeToken` with its `section.name` and its `system(_:)` shade, a value in each built-in theme where `system` won't do, its row in the skill's themes reference, a `ThemeColor` name in the app, and a case in `ThemeReaderTests`.
- **A new knob.** A field in `ThemeKnobs` with the Shipyard theme's default, its read and range in `ThemeReader`, its row in the skill's themes reference, and a case in `ThemeReaderTests`.
- **A new built-in theme.** One `BuiltInThemes+<Name>.swift` holding the file as text, one line in `BuiltInThemes.sources`, the name in the schema's `theme` description and the skill's `theme` row, and the name in `ThemeReaderTests`' list of built-ins, which reads each one and runs the contrast check on it in both appearances.

## Adding or changing a setting

Do every step in the same change; the tests fail on most of the ones you miss.

1. **The model and its default.** Add the field, with its default, to `Configuration.swift`: a top-level field, a table's struct, or an override type with its `applied(to:)` when a project can override it.
   A new choice is a `CaseIterable` string enum.
2. **The reader.** In `ConfigurationReader.swift`, read the key with the typed accessor, and record errors for out-of-range values at the key's path.
   Add the key to its table's `warnUnknownKeys` known list, otherwise it's reported as unknown.
3. **The schema.** Add the key to `schema/config.schema.json` with its `description`, `type`, `default` and any `enum`, `minimum` or `maximum`, under the right table or definition.
   A project-overridable key goes in the shared definition both `defaults` and `project` reference.
   A key or spelling the reader still accepts as an old form stays in the schema, marked `"deprecated": true` (an old spelling of a value sits beside the new one in an `anyOf`).
4. **The new-file header.** When users should discover the setting from a fresh file, show it commented out at its default in `Configuration.header`, in the `# [table]` / `# key = value` form the header already uses.
   Put it under a one-line comment with no ` = ` in it (the header test takes such lines for settings).
   A top-level key goes above the first commented table, a table among the others.
   Keep each example's lines together, since the test uncommenting them one example at a time treats a run of setting lines as one example.
5. **The skill.** Add the key to `skills/shipyard/SKILL.md`: its row in the right keys table (`| key | default | allowed |`), any new choice or event, and a worked request when it answers something users will ask for.
   Tests fail until every schema key is named beside its table, every default matches the code, and every TOML example decodes cleanly and validates.
6. **The README.** When the setting is something a user meets before reading the skill, give it a mention in `README.md`'s "Configure" section.
   When the README's examples use it, keep them decoding (`ReadmeDocumentTests` checks them).
   The README stays short; the skill is the reference.
7. **Tests at the configuration seam.** In `ConfigurationTests`, set the key in `everyKey` (away from its default) and add decode and rejection cases with their lines and messages.
   `ConfigSchemaTests` then checks the schema declares exactly the keys `everyKey` sets, and `choicesMatch` needs a line for a new enum.
8. **Tests at the orchestrator seam.** When the setting changes behaviour, test it through the `Harness`: write the file, `reloadConfiguration()`, and assert on what the user sees (the menu model, notifications, the timer), including that an edit applies live without a restart.
   A filter is tested for what it lists, counts and notifies, and for not notifying an item it brings back into view.
9. **The design doc.** Update `docs/low-level-design.md` in the same change: the example file under *Configuration*, and the module whose behaviour the setting changes.
