# Security policy

## Supported versions

Only the latest release of shipyard gets security fixes.
Update to it before you report a problem.

## Reporting a vulnerability

Report a vulnerability privately, through GitHub's private vulnerability reporting: open the repository's **Security** tab and choose **Report a vulnerability**.
Do not open a public issue, pull request or discussion about it.

Include:

- what an attacker can do, and what they need first,
- the steps to reproduce it,
- the shipyard version (`shipyard --version`) and your macOS version.

You get an answer within seven days.
When the report is confirmed, the fix ships in a new release, and the advisory credits you unless you ask otherwise.

## What shipyard keeps

- Your GitHub sign-in token is kept in the macOS Keychain. When you connect through the GitHub CLI instead, shipyard asks `gh` for its token and keeps no copy.
- Shipyard keeps no Notion token. Notes go through Notion's own `ntn` command, with its own login.
- Your configuration is `~/.config/shipyard/config.toml`, and the app's state is in `~/Library/Application Support/Shipyard`.
