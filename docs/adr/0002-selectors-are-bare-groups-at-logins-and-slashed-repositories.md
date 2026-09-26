# Selectors: bare words are groups, `@` marks a login, `/` marks a repository

The configuration names authors and repositories with one small syntax. A bare word is a group: `me`, `others` and `bots` in an author filter; `owned`, `organizations`, `collaborator` and `anywhere` in `repositories`. A login always starts with `@` (`@dependabot[bot]`). A repository always contains a `/` (`owner/name`, `owner/*`). The key a selector sits under says which set it belongs to, so a group needs no symbol of its own. A bare word that isn't a group of that key is an error with a hint ("did you mean `bots` or `@bots2`?"). So is a group used under the wrong key.

We chose this for newcomers and their agents: there's nothing to learn beyond "`@` is a person, `/` is a repository". GitHub logins can't contain `@`, `#` or `/`, so none of the forms can collide with a real name.

## Considered options

- **`@` for groups too** (`@me`, `@others`): rejected, because `@` tags a person everywhere else on GitHub, so `@me` reads as a login.
- **A symbol for each set** (`#owned` for repository groups, `$me` for author groups): rejected. It adds two symbols to learn for what the key already says. Inside TOML, `#` also reads as a comment.
- **Bare logins** (`dependabot[bot]` without `@`): rejected, because a mistyped group (`bot`) would silently become a login that matches nobody.

## Consequences

- The syntax is part of the configuration's public contract (ADR 0001). Changing it needs the `version` key and a migration.
- The older forms (`hide-authors`, and notification rules' `authors = "others"`) are still read and turned into the new form, with a warning.
