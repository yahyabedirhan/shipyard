# Themes are TOML files beside config.toml, the built-ins are embedded, a bad file keeps the last good theme

A **theme** decides how the panel looks: its **tokens**, each one colour named by what it means, for light and dark, and its font, density, corner radii and material.
The panel draws its colours from the theme's tokens, so a theme changes the whole panel at once.
The top-level `theme = "<name>"` in `config.toml` picks one, and Shipyard is the default.

**A theme is a TOML file.**
A **theme file** is the user's own theme: one `*.toml` file in the `themes` folder beside `config.toml`, read in file-name order.
It names its tokens by meaning (`surface.panel`, `text.secondary`), may `extends` another theme and set only what changes, and may take a built-in theme's name to replace it.
The user and their agents write theme files as they write `config.toml` (ADR 0001): with an editor, the same TOML reader, problems on their lines and a save that applies at once.

**The built-in themes are embedded.**
The six **built-in themes**, Shipyard, Native, Graphite, Paper, Midnight and Harbor, are theme files in the same format, compiled into the app as text and read once.
They need no folder on disk, can't be edited by accident, and update with the app.
A theme file extends them by name.

**A bad file keeps the last good theme.**
A theme file with a problem keeps the theme it last read, and the panel shows a configuration banner with the file, the line and the problem.
A picked theme whose file has never read is a warning on the `theme` line, not an error, and the panel draws Shipyard until the file reads.
So a broken theme file never rejects `config.toml`, as a broken `config.toml` never blanks the menu (ADR 0001).

## Considered Options

- **Themes inside `config.toml`.** One file to edit, but a long colour table would bury the settings, and a typo in a colour would reject the whole configuration.
- **A theme picker in the settings menu, or a command that sets the theme.** The configuration has no settings window and no command writes it (ADR 0001); picking a theme is one key.
- **Built-in themes as files in the support folder.** The user could edit them in place, but an update would have to overwrite or merge their edits, and a missing file would leave no default.
- **Theme files beside `config.toml`, the built-ins embedded (chosen).** Each file is one theme the user owns, the built-ins can always be extended, and a broken file costs only that theme.

## Consequences

- Theme files are a second kind of configuration file, so `shipyard config check` prints one verdict per theme file between `config.toml`'s and `cli.toml`'s, and `--json` keys each one `themes/<file>`.
- `config-status.json` keeps `config.toml`'s verdict alone: theme problems show in the panel's banner and in `config check`.
- The theme reader is pure and lives in ShipyardConfig, so the Mac `shipyard` checks theme files without the app; the Linux `shipyard` never links ShipyardConfig, so it reads neither theme files nor `theme` (ADR 0006).
- A theme's text must reach 4.5:1 on its panel, 3:1 for the tertiary tier; a shortfall is a warning on the `theme` line and never stops the theme.
- The app watches the `themes` folder and each file in it, as it watches `config.toml`.

## Amendment, 2026-10-22: one appearance per built-in theme, System, and the Theme submenu

The built-in themes are now ten, each of one appearance except System (#342): System, the default, follows the macOS appearance and accent colour; Shipyard Light, Shipyard Dark, Paper Light, Paper Dark, Harbor, Heather, Brass, Ocean and Sunset each draw their one appearance whatever the system's.
They replace Shipyard, Native, Graphite, Paper and Midnight outright, with no aliases: a `theme` that names a removed theme is an error that lists every theme's name.
A theme that extends another keeps the appearances it has, and adds the one whose `[light.*]` or `[dark.*]` tables it writes, so a theme that extends Shipyard Dark is dark too.
Two themes of one appearance each look different from each other, where one theme of two appearances made light and dark look alike.

The gear menu's Theme submenu now picks a theme (#327): it sets the one `theme` key, a fourth targeted edit (ADR 0001).
The considered option "a theme picker in the settings menu" is chosen for picking alone; making a theme stays a theme file.
A theme whose `signal.attention` and `signal.attention-failed` are closer than ΔE 25 reads with a warning on the `theme` line, as a contrast shortfall does (#343).
