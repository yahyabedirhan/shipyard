# Handoff: config-convention

Build the effort `config-convention` and deliver it as a pull request against `main`.

## Where

- Worktree: `~/.treehouse/shipyard-1e47e3/3/shipyard` (treehouse lease holder `config-convention`).
- Branch: `effort/config-convention`, cut from `main` at `fc364a7`. It has no upstream until the first `git push -u`.

## Spec and tickets

- Spec: #253 (`effort:config-convention`). It holds the why, the context and the end result.
- Build tickets, in order:
  1. #254 Rename the configuration types to the `Configuration` prefix. Do it first, because the other tickets touch the same files.
  2. #257 Give `cli.toml` a version and a schema. It does not depend on #254.
  3. #255 Rename `config.toml` keys. Blocked by #254.
  4. #256 `shipyard config check`. Blocked by #254 and #257.
- Follow-up: #258 migrates the files on the maintainer's machines. It is blocked by the three build tickets and runs only **after the merge and a release**. Do not do it in this effort's pull request. Leave it open, and name it in the pull request as the step after the merge.

## Decisions already made

The maintainer settled these in the session that wrote this handoff. Do not reopen them.

- Names come from terms the industry already uses: `-timeout` (longest wait), `-interval` (time between repeats), `-duration` (how long a thing lasts once started), `-window` (a time range that ends now), `max-<noun>` (largest count). No invented phrases such as `keep-closed-for`.
- `closed-window`, `finished-window` and `seen-window` stay as they are. They are time ranges that end now.
- `refresh-interval-seconds` becomes `refresh-interval`, a duration as text, default `"2m"`.
- `[banners] snooze` becomes `snooze-duration`.
- `[[projects]] name` becomes `slug` (required) and `title` (optional, default the slug). An old `name` still reads with a warning: its title is the name, its slug is the name lowercased with other characters as single hyphens. `--project` finds a project by slug first, then by title, so older remote `shipyard` builds keep working.
- Every renamed key keeps an old form with a warning, and stays in the schema as `"deprecated": true`, as `docs/configuration.md` already does for `closed-window-days`.
- `config.toml` without `version` is accepted with a warning now, and becomes an error from version 2.
- `cli.toml` accepts `version = 1`. A `cli.toml` without `version` stays valid in version 1, with no warning, because a warning would print on every `shipyard notify`.
- File names do not change: `config.toml`, `cli.toml`, `config-status.json`, `config-location.json`.

## How to deliver

- One pull request for the effort, opened through the `to-pr` skill. Put the tickets it closes in the description, and say #258 follows the merge and a release.
- The maintainer approves and merges. Do not merge.
- The session that wrote this handoff does not wait for messages. Decide open questions yourself, and list each one in the pull request.

## Suggested skills

- `orchestrate-effort` and `orchestrating`, to delegate the tickets.
- `implement` and `tdd`, for the delegates.
- `write-swift`, for the Swift changes.
- `shipyard`, for the configuration file and the skill text.
- `to-pr`, to open the pull request.
