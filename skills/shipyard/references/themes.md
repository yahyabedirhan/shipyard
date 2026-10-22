# Themes

A **theme** decides how the panel looks: its colours, its font, its density, its corner radii and its material.
Every theme draws the same panel, with the same rows and the same layout.
A theme is a set of **tokens**, each one colour named by what it means, such as `surface.panel` or `text.secondary`, never by hue.
It also sets the **state colours** of pull requests, issues, runs, checks, reviews, the rate limit, pings and notes, one for each state of each kind, which may share one colour per **phase**.

Shipyard has ten **built-in themes**, part of the app.
System, the default, follows the macOS appearance, light or dark, and the accent colour picked in System Settings > Appearance.
Every other built-in theme has one appearance, which it draws whatever the system's appearance:

| Theme | Appearance | Accent |
|---|---|---|
| `System` | follows macOS | the macOS accent colour |
| `Shipyard Light` | light | blue `#2F6BDE` |
| `Shipyard Dark` | dark | blue `#6D9CFF` |
| `Paper Light` | light | terracotta `#B4491E` |
| `Paper Dark` | dark | beige `#E3CFA8` |
| `Harbor` | light | teal `#0E7C86` |
| `Heather` | light | violet `#6A4FB0` |
| `Brass` | light | ochre `#8A6100` |
| `Ocean` | dark | sky cyan `#4FC3F7` |
| `Sunset` | dark | orange `#FB923C` |

A **theme file** is the user's own theme: one TOML file in the `themes` folder beside `config.toml`, so `~/.config/shipyard/themes/<anything>.toml`, or under `$XDG_CONFIG_HOME` when it is set.

## Picking a theme

Set the top-level `theme` key in `config.toml` to a theme's name, ignoring case, above the first `[table]` header:

```toml
version = 1
theme = "Ocean"
```

- The name is a built-in theme's or the `name` a theme file sets, not the file's name.
- An unknown name is an error on its line that suggests the nearest name and lists every theme's.
- Without `theme`, the panel draws System.
- A save applies at once, with no restart.
- The panel's gear menu has a Theme submenu that sets `theme` too: the built-in themes, then the theme files after a separator, each with a circle of its panel and accent colours.
  It changes that one key and keeps the rest of the file, its comments included.

## Writing a theme

1. Make the `themes` folder beside `config.toml` when it is missing.
2. Write the file, `themes/<Name>.toml`, starting from a built-in theme with `extends` and setting only what changes. The theme takes the appearance of the theme it extends. The example below is a whole file.
3. Set `theme` in `config.toml` to the file's `name`.
4. Run `shipyard config check`. It is done when it exits 0 and prints no `warning` line for the `theme` line.

```toml
# themes/Tide.toml
name = "Tide"
version = 1
extends = "Shipyard Light"
description = "Shipyard Light with a deep green accent."

[palette]
green = "#2E7357"

[accent]
accent = "green"

[signal]
attention = "green"

[text]
on-accent = "#ffffff"

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
- A table without a prefix sets every appearance the theme has.
  A `[light.*]` or `[dark.*]` table, such as `[dark.text]`, changes a token for that appearance only.
- An `[any.*]` table is a problem on its line: remove the `any.` prefix.
- A token's value is a palette name, a hex colour `#rrggbb` or `#rrggbbaa`, or `system`, the matching macOS colour.
- `[palette]` names raw colours once.
  `[light.palette]` and `[dark.palette]` give one name a different colour per appearance, so one table without a prefix serves both.
- A theme with no `extends` that fills only one appearance draws that one in both, as every built-in theme but System does.
- A theme that extends another keeps the appearances it has, and adds the one whose `[light.*]` or `[dark.*]` tables it writes: a theme that extends Shipyard Dark is dark too.

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
| `accent` | `accent` | The one accent: a prominent button, the active count, a caught-up or connected tick. |
| | `soft` | Reserved: accepted and checked, with no effect. |
| `line` | `separator` | Hairlines between parts. |
| | `border` | Around cards and secondary buttons. |
| `row` | `hover` | A hovered row or button, and the keyboard-highlighted row. |
| | `pressed` | A pressed row or button. |
| | `selected` | Reserved: accepted and checked, with no effect. The keyboard-highlighted row draws with `row.hover`. |
| `signal` | `attention` | The attention dot of a row that is new or changed, or whose pull request's checks are pending while it needs attention. |
| | `attention-failed` | The attention dot while a pull request's checks fail. Without it, the `failed` phase's colour. |
| | `lease` | The banner while an agent drives the app. |

### State colours

A row's state icon, the hover card's review and checks, the rate-limit bar and text, and a ping's or a note's icon take the colour the theme gives that kind in that state.
The rest of the panel that shows a phase draws the phase's colour: an error, a failed action or the lease banner's Stop is `failed`, an informational banner is `quiet`.
A tick that says all is well, such as the one before "All caught up", draws the accent, not `done`.
Two tables set the state and phase colours, without a prefix for light and dark or under `[light.*]` and `[dark.*]` for one appearance:

- `[phase]` names one colour per phase, for every state in it to share.
  A phase's value is a palette name, a hex colour or `system`, never a phase's name.
- `[states.<kind>]` gives each state of one kind its colour.
  A state's value is a phase name, a palette name, a hex colour or `system`.
- A phase's name, such as `quiet`, always means the phase: give a palette entry another name.

| Phase | Its states | Its default |
|---|---|---|
| `active` | `pull-request.open`, `issue.open`, `run.running`, `check.pending`, `review.review-required`, `rate.normal` | The macOS green. |
| `done` | `pull-request.merged`, `issue.closed`, `run.succeeded`, `check.passed`, `review.approved` | The macOS purple. |
| `failed` | `pull-request.closed`, `run.failed`, `check.failed`, `review.changes-requested`, `rate.exhausted` | The macOS red. |
| `quiet` | `pull-request.draft`, `ping.open`, `note.open` | The macOS secondary label grey. |

`rate.low` is a warning, not a phase: its default is the macOS orange.

| Table | States | What it colours |
|---|---|---|
| `[states.pull-request]` | `open`, `draft`, `merged`, `closed` | A pull request's icon. |
| `[states.issue]` | `open`, `closed` | An issue's icon. |
| `[states.run]` | `running`, `succeeded`, `failed` | A workflow run's icon, and a running run's duration on its hover card. |
| `[states.check]` | `pending`, `passed`, `failed` | A pull request's checks on the hover card, and the "checks failed" reason. The row shows its checks through the attention dot. |
| `[states.review]` | `review-required`, `approved`, `changes-requested` | The review on a pull request's hover card, and the "review requested" reason. |
| `[states.rate]` | `normal`, `low`, `exhausted` | The rate-limit bar, lighter while `normal`; its text once `low` or `exhausted`, and the slow-down and paused banners. |
| `[states.ping]` | `open` | A ping's icon. |
| `[states.note]` | `open` | A note's icon. |

- A state colour comes from the appearance's table, then the table without a prefix, then the `extends` chain.
- A state no theme in the chain sets takes its phase, and a phase no theme sets is its macOS colour.
- `system` in a state is the macOS colour of its own phase, and the macOS orange for `rate.low`.
- Every built-in theme follows one rule: active is green, done is purple, failed is red and quiet is grey.

```toml
[phase]
failed = "#DC2626"

[states.run]
running = "#F59E0B"

[dark.states.issue]
closed = "#A78BFA"
```

`[state]` has no tokens: every state's colour is in `[phase]` and `[states.<kind>]`.
A theme file that writes a key in `[state]`, such as `open`, `merged`, `success` or `neutral`, has a problem on its line that names the keys to write instead, such as `[phase] done` or `[states.check] passed` for `state.success`.

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

### Attention

The attention dot has two colours that must read apart: `signal.attention` for a new or changed row, and `signal.attention-failed` while a pull request's checks fail.
When they are closer than ΔE 25 (CIE76) in an appearance the theme fills, `config.toml`'s `theme` line has a warning.
Move `signal.attention-failed`, or `[phase] failed`, away from the accent until the warning is gone.
System follows the user's accent colour: with a red accent, its failed dot draws a deeper red.

## Checking a theme file

`shipyard config check` prints a verdict for each theme file, after `config.toml`'s and before `cli.toml`'s:

```text
/Users/me/.config/shipyard/config.toml: accepted
  warning: config.toml line 2: theme `Tide` isn't one shipyard has read, and `themes/Tide.toml` has a problem; the panel draws System until it reads
/Users/me/.config/shipyard/themes/Tide.toml: rejected
  problem: themes/Tide.toml line 11: unknown token `accent.acent`; did you mean `accent`?
/Users/me/.config/shipyard/cli.toml: accepted (no file: the defaults)
```

- Every problem in a theme file stops it: an unknown key, section, token, phase, kind or state, an `[any.*]` table, a removed `state.*` token, a value that isn't a palette name, a colour or `system`, a state value that isn't one of those or a phase, a phase that names another phase, a broken hex colour, a knob out of range, an `extends` that names no theme or goes in a circle, and two files with one `name`.
- A theme file has problems and no warnings.
- A file with a problem keeps the theme it last read, and the panel shows a banner with the file, the line and the problem until it is fixed.
  A file that has never read leaves `theme` drawing System.
- `--json` prints each theme file's result under `themes/<file>`, beside `config.toml` and `cli.toml`.
- The app's record, `config-status.json`, holds `config.toml`'s verdict alone: check theme files with `shipyard config check`.
- Theme files are read on the Mac only: the `shipyard` command on another machine checks `cli.toml` alone.
