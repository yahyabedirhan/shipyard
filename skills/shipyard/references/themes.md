# Themes

A **theme** decides how the panel looks: its colours, its font, its density, its corner radii and its material.
Every theme draws the same panel, with the same rows and the same layout.
A theme is a set of **tokens**, each one colour named by what it means, such as `surface.panel` or `text.secondary`, never by hue.
It also sets the **state colours** of pull requests, issues and runs, one for each state of each kind, which may share one colour per **phase**.

Shipyard has six **built-in themes**, part of the app: Shipyard, the default, then Native, Graphite, Paper, Midnight and Harbor.
A **theme file** is the user's own theme: one TOML file in the `themes` folder beside `config.toml`, so `~/.config/shipyard/themes/<anything>.toml`, or under `$XDG_CONFIG_HOME` when it is set.

## Picking a theme

Set the top-level `theme` key in `config.toml` to a theme's name, ignoring case, above the first `[table]` header:

```toml
version = 1
theme = "Midnight"
```

- The name is a built-in theme's or the `name` a theme file sets, not the file's name.
- An unknown name is an error on its line that suggests the nearest name.
- Without `theme`, the panel draws Shipyard.
- A save applies at once, with no restart.
- Paper fills only a light look and Midnight only a dark one: each draws its look whatever the system's appearance.

## Writing a theme

1. Make the `themes` folder beside `config.toml` when it is missing.
2. Write the file, `themes/<Name>.toml`, starting from a built-in theme with `extends` and setting only what changes. The example below is a whole file.
3. Set `theme` in `config.toml` to the file's `name`.
4. Run `shipyard config check`. It is done when it exits 0 and prints no `warning` line for the `theme` line.

```toml
# themes/Sunset.toml
name = "Sunset"
version = 1
extends = "Shipyard"
description = "Shipyard with a coral accent."

[light.palette]
coral = "#C2410C"
[dark.palette]
coral = "#FB923C"

[accent]
accent = "coral"

[signal]
attention = "coral"

[light.text]
on-accent = "#ffffff"
[dark.text]
on-accent = "#1a0b02"

[material]
style = "flat"
```

The text on an accent fill, `text.on-accent`, follows the accent: change both together.

### Top-level keys

| Key | Meaning |
|---|---|
| `name` | The name `theme` picks. Required. A file with a built-in theme's name replaces that theme. |
| `version` | The format version, `1`. Required. |
| `extends` | A theme, by name, that fills every token, phase, state and knob this file leaves out, palette names included. A built-in theme or another file's. |
| `description` | One line about the theme. Optional. |

A token that no theme in the `extends` chain sets is `system`.

### Colours per appearance

- Tokens sit in tables named after their section, such as `[text]`.
- A table without a prefix sets both the light and the dark look.
  A `[light.*]` or `[dark.*]` table, such as `[dark.text]`, changes a token for that appearance only.
- An `[any.*]` table is a problem on its line: remove the `any.` prefix.
- A token's value is a palette name, a hex colour `#rrggbb` or `#rrggbbaa`, or `system`, the matching macOS colour.
- `[palette]` names raw colours once.
  `[light.palette]` and `[dark.palette]` give one name a different colour per appearance, so one table without a prefix serves both.
- A theme with no `extends` that fills only one appearance draws that one in both, as Paper and Midnight do.

### Tokens

| Section | Token | Meaning |
|---|---|---|
| `surface` | `window` | Reserved: accepted and checked, with no effect. |
| | `panel` | The panel's surface. Text contrast is measured against it. |
| | `header` | A project header in the list layout. Opaque, so rows scroll under it. |
| | `chrome` | The footer's tint. |
| | `raised` | A lifted surface: the selected tab's pill. |
| | `field` | A card's, command box's or chip's fill. |
| | `track` | The tab strip's sunk track. |
| `text` | `primary` | Titles. |
| | `secondary` | Authors, repositories, detail lines. |
| | `tertiary` | Ages, last updated, hints. |
| | `seen` | The title of a row already seen. |
| | `on-accent` | Text on an accent fill. |
| `accent` | `accent` | The one accent: the attention dot, a prominent button, the active count. |
| | `soft` | Reserved: accepted and checked, with no effect. |
| `line` | `separator` | Hairlines between parts. |
| | `border` | Around cards and secondary buttons. |
| `row` | `hover` | A hovered row or button, and the keyboard-highlighted row. |
| | `pressed` | A pressed row or button. |
| | `selected` | Reserved: accepted and checked, with no effect. The keyboard-highlighted row draws with `row.hover`. |
| `state` | `success` | A passing check, an approval. |
| | `failure` | A failing check, an error, an exhausted rate limit. |
| | `pending` | A pending check, a low rate limit. |
| | `neutral` | A ping, a note. |
| `signal` | `attention` | A row that needs attention. |
| | `lease` | The banner while an agent drives the app. |

### State colours

A row's state icon takes the colour its theme gives that kind in that state.
Two tables set them, without a prefix for light and dark or under `[light.*]` and `[dark.*]` for one appearance:

- `[phase]` names one colour per phase, for every state in it to share.
  A phase's value is a palette name, a hex colour or `system`, never a phase's name.
- `[states.<kind>]` gives each state of one kind its colour.
  A state's value is a phase name, a palette name, a hex colour or `system`.
- A phase's name, such as `quiet`, always means the phase: give a palette entry another name.

| Phase | Its states | Its default |
|---|---|---|
| `active` | `pull-request.open`, `issue.open`, `run.running` | The macOS green. |
| `done` | `pull-request.merged`, `issue.closed`, `run.succeeded` | The macOS purple. |
| `failed` | `pull-request.closed`, `run.failed` | The macOS red. |
| `quiet` | `pull-request.draft` | The macOS secondary label grey. |

| Table | States |
|---|---|
| `[states.pull-request]` | `open`, `draft`, `merged`, `closed` |
| `[states.issue]` | `open`, `closed` |
| `[states.run]` | `running`, `succeeded`, `failed` |

- A state colour comes from the appearance's table, then the table without a prefix, then the `extends` chain.
- A state no theme in the chain sets takes its phase, and a phase no theme sets is its macOS colour.
- `system` in a state is the macOS colour of its own phase.
- Every built-in theme follows one rule: active is green, done is purple, failed is red and quiet is grey.

```toml
[phase]
failed = "#DC2626"

[states.run]
running = "#F59E0B"

[dark.states.issue]
closed = "#A78BFA"
```

`[state]` has no `open`, `draft`, `merged`, `closed` or `running` token.
A theme file that writes one has a problem on its line that names the keys to write instead, such as `[phase] done` for `state.merged`.

### Knobs

Knobs are shared by both appearances and sit in their own tables, with no `light` or `dark` prefix.

| Table | Keys |
|---|---|
| `[font]` | `family`: `system`, `rounded`, `mono` or a font's name. `mono`: `system` or a font's name, for code. `size`: the body size in points, from 9 to 20; every other size follows it. The default is the system font at 12. |
| `[density]` | `preset`: `compact`, `regular` or `comfortable`. Or `row`, `header`, `bar` and `gutter` in points, from 4 to 80; a key you set wins over the preset. |
| `[shape]` | `small` and `medium` corner radii, from 0 to 30: small controls, and cards and banners. `large` is reserved: accepted and checked, with no effect. |
| `[material]` | `style`: `flat` paints the panel with `surface.panel`; `glass` lays the system's material under a veil of `surface.panel`. |

### Contrast

The text must read on the panel, in each appearance the theme fills:

- `text.primary`, `text.secondary` and `text.seen` need 4.5:1 on `surface.panel`.
- `text.tertiary` needs 3:1 on `surface.panel`.

A shortfall of the picked theme is a warning on `config.toml`'s `theme` line.
The theme still draws: raise the contrast until the warning is gone.

## Checking a theme file

`shipyard config check` prints a verdict for each theme file, after `config.toml`'s and before `cli.toml`'s:

```text
/Users/me/.config/shipyard/config.toml: accepted
  warning: config.toml line 2: theme `Sunset` isn't one shipyard has read, and `themes/Sunset.toml` has a problem; the panel draws Shipyard until it reads
/Users/me/.config/shipyard/themes/Sunset.toml: rejected
  problem: themes/Sunset.toml line 22: unknown token `accent.acent`; did you mean `accent`?
/Users/me/.config/shipyard/cli.toml: accepted (no file: the defaults)
```

- Every problem in a theme file stops it: an unknown key, section, token, phase, kind or state, an `[any.*]` table, a removed `state.*` token, a value that isn't a palette name, a colour or `system` (or, for a state, a phase), a phase that names another phase, a broken hex colour, a knob out of range, an `extends` that names no theme or goes in a circle, and two files with one `name`.
- A theme file has problems and no warnings.
- A file with a problem keeps the theme it last read, and the panel shows a banner with the file, the line and the problem until it is fixed.
  A file that has never read leaves `theme` drawing Shipyard.
- `--json` prints each theme file's result under `themes/<file>`, beside `config.toml` and `cli.toml`.
- The app's record, `config-status.json`, holds `config.toml`'s verdict alone: check theme files with `shipyard config check`.
- Theme files are read on the Mac only: the `shipyard` command on another machine checks `cli.toml` alone.
