# Configuration is a TOML file under ~/.config that agents edit directly

Shipyard's configuration lives in one TOML file, `$XDG_CONFIG_HOME/shipyard/config.toml` (default `~/.config/shipyard/config.toml`). The app watches the file and applies changes live. There is no CLI, and no settings window as the main way to change it. Agents learn the format from a published JSON Schema (referenced by a `#:schema` line that TOML tooling such as Taplo understands) and from a shipyard skill offered at install. App state (collapsed sections, seen items) is kept apart, in `~/Library/Application Support/Shipyard/`.

We chose this because the configuration is meant to be written by the user's agents and read by the user. A plain file with a schema is the easiest thing for an agent to read, edit and validate, and it needs no running app. The alternatives were Apple's usual `UserDefaults`/plist storage, which agents can't read or edit well, and a CLI that talks to the running app, which is one more thing to build and to keep in sync. `~/.config/<app>/` is where developer tools on macOS put their configuration (cmux, CodexBar, Ghostty, gh, Herdr), so agents and users look for it there.

TOML over JSON: the file is edited by hand as often as by agents, and TOML allows comments, which JSON can't hold. It's also the common format for developer-tool configuration (Herdr, Alacritty, AeroSpace, Starship). The costs are a dependency, since Swift can't parse TOML natively (we use TOMLDecoder, which only decodes), and that the app can't rewrite the file without losing comments.

## Consequences

- A broken edit must never blank the menu. The app keeps the last valid configuration and shows the error with its line.
- The app never rewrites the file. The project picker only appends `[[projects]]` tables at the end, which is always valid TOML and keeps the user's comments.
- The schema is a public contract. Changing a key needs a migration, and the file has a `version` key to drive it.

## Amendment, 2026-09-26: two targeted edits

The app now writes to `config.toml` in two targeted ways, and still never rewrites the file as a whole:

- The project picker appends `[[projects]]` tables at the end of the file, as before.
- The layout button in the menu's header sets `[menu] layout` to the next layout. It replaces the key's value, adds the key under an existing `[menu]`, uncomments the new file's `# [menu]` example, or adds a `[menu]` table above the first table. It refuses a `[menu]` written in a form it doesn't edit, and any edit that wouldn't read back as the same configuration with only the layout changed.

Every other line and comment stays as the user wrote it. The consequence above that "the app never rewrites the file" now means the file as a whole.

## Amendment, 2026-09-26: a third targeted edit, the preset at onboarding

From 0.0.2, onboarding also writes a **preset** (`my-agents`, `incoming-contributions` or `review-queue`): a whole commented configuration, with the repositories the user picked. It writes one only when the file is missing or its only live key is `version`, which is the case for the header the app creates. Any other file is refused, and onboarding then shows the plain project picker, which appends projects as before. The app still never rewrites a file that holds the user's own settings.

"Only live key" is read from the file's text, not its meaning: comments and blank lines don't count, and any other key or table does, even one set to its default or an empty `[menu]`. A file that doesn't read is refused too. The check runs again just before writing, so a setting saved while onboarding was open is never overwritten. The file is written in place, like the layout edit, so a symlinked file stays a symlink.
