# Configuration is a TOML file under ~/.config that agents edit directly

Shipyard's configuration lives in one TOML file, `$XDG_CONFIG_HOME/shipyard/config.toml` (default `~/.config/shipyard/config.toml`). The app watches the file and applies changes live. There is no CLI, and no settings window as the main way to change it. Agents learn the format from a published JSON Schema (referenced by a `#:schema` line that TOML tooling such as Taplo understands) and from a shipyard skill offered at install. App state (collapsed sections, seen items) is kept apart, in `~/Library/Application Support/Shipyard/`.

We chose this because the configuration is meant to be written by the user's agents and read by the user. A plain file with a schema is the easiest thing for an agent to read, edit and validate, and it needs no running app. The alternatives were Apple's usual `UserDefaults`/plist storage, which agents can't read or edit well, and a CLI that talks to the running app, which is one more thing to build and to keep in sync. `~/.config/<app>/` is where developer tools on macOS put their configuration (cmux, CodexBar, Ghostty, gh, Herdr), so agents and users look for it there.

TOML over JSON: the file is edited by hand as often as by agents, and TOML allows comments, which JSON can't hold. It's also the common format for developer-tool configuration (Herdr, Alacritty, AeroSpace, Starship). The costs are a dependency, since Swift can't parse TOML natively (we use TOMLDecoder, which only decodes), and that the app can't rewrite the file without losing comments.

## Consequences

- A broken edit must never blank the menu. The app keeps the last valid configuration and shows the error with its line.
- The app never rewrites the file. The project picker only appends `[[projects]]` tables at the end, which is always valid TOML and keeps the user's comments.
- The schema is a public contract. Changing a key needs a migration, and the file has a `version` key to drive it.
