# Herdr and the outer terminal

Checked 2026-10-03 against herdr/herdr at commit 7b116c05 (tag v0.9.3), `src/pane.rs`.

What a shell inside a Herdr pane can see of the terminal app Herdr itself runs in:

- `apply_pane_terminal_env` sets `TERM_PROGRAM=herdr` (and `TERM_PROGRAM_VERSION`), so `TERM_PROGRAM` no longer names the outer terminal. It also sets `TERM` to Herdr's own value.
- It removes the outer terminal's per-window handles: `ITERM_SESSION_ID`, `LC_TERMINAL`, `LC_TERMINAL_VERSION`, `WEZTERM_PANE`, `KITTY_WINDOW_ID`, `WT_SESSION`, and tmux, screen and zellij markers.
- It does not touch `__CFBundleIdentifier`, which macOS sets for a process launched from an app (`com.mitchellh.ghostty` for Ghostty), nor `ALACRITTY_WINDOW_ID` or `GHOSTTY_*`. These come from the environment of the process that started the Herdr server, so they name the terminal the server was started in, which is the one Herdr is shown in unless the server outlives it.

How `shipyard ping --herdr` uses this (`PingCommand.outerTerminal`): a known `TERM_PROGRAM` wins (outside Herdr), then `__CFBundleIdentifier`, then kitty's (`KITTY_WINDOW_ID`, `TERM=xterm-kitty`) and Alacritty's variables. The bundle id is stored on the ping and brought forward on a click when `[herdr] terminal` is unset.
