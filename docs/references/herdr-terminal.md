# Herdr and the outer terminal

Checked 2026-10-03 against herdr/herdr at commit 7b116c05 (tag v0.9.3), `src/pane.rs`.

What a shell inside a Herdr pane can see of the terminal app Herdr itself runs in:

- `apply_pane_terminal_env` sets `TERM_PROGRAM=herdr` (and `TERM_PROGRAM_VERSION`), so `TERM_PROGRAM` no longer names the outer terminal. It also sets `TERM` to Herdr's own value.
- It removes the outer terminal's per-window handles: `ITERM_SESSION_ID`, `LC_TERMINAL`, `LC_TERMINAL_VERSION`, `WEZTERM_PANE`, `KITTY_WINDOW_ID`, `WT_SESSION`, and tmux, screen and zellij markers.
- It does not touch `__CFBundleIdentifier`, which macOS sets for a process launched from an app (`com.mitchellh.ghostty` for Ghostty), nor `ALACRITTY_WINDOW_ID` or `GHOSTTY_*`. These come from the environment of the process that started the Herdr server, so they name the terminal the server was started in, which is the one Herdr is shown in unless the server outlives it.

How `shipyard ping --herdr` uses this (`PingCommand.outerTerminal`): a known `TERM_PROGRAM` wins (outside Herdr), then `__CFBundleIdentifier`, then kitty's (`KITTY_WINDOW_ID`, `TERM=xterm-kitty`) and Alacritty's variables. The bundle id is stored on the ping and brought forward on a click when `[herdr] terminal` is unset.

## Named sessions

Checked 2026-10-03 against the same commit, `src/session.rs`, `src/server/autodetect.rs`, `src/integration/env.rs`, `src/cli/target.rs` and `src/cli/server_not_running.rs`.

- `herdr --session <name>` (or `herdr session attach <name>`) sets `HERDR_SESSION=<name>` in its own environment before it starts or attaches to that session's server (`apply_explicit_name`); the name `default` removes the variable instead, so Herdr's default session has none. The server inherits it (`spawn_server_daemon`), and its panes and plugin hooks inherit the server's environment (nothing clears it), so a shell in a named session's pane sees `HERDR_SESSION=<name>`.
- Each pane also gets `HERDR_SOCKET_PATH`, its server's socket (`apply_pane_base_env`), which is how `herdr` run inside a pane reaches the right server. An app outside Herdr has neither, so plain `herdr` there reaches the default session.
- `--session <name>` is read from anywhere before `--` (`configure_from_args`) and works with every subcommand: `herdr --session work pane get w1:p3` asks the `work` server, and an explicit `--session` wins over an inherited `HERDR_SOCKET_PATH`. `--session default` is the default session.
- `--machine` can't be combined with `--session` ("it uses the saved machine's session").
- With no server on the session's socket, a command fails with code `server_not_running`.
- Each session numbers its workspaces, tabs and panes on its own, so `w1:p3` names a pane in each running session.

How shipyard uses this: `shipyard ping --herdr` and `shipyard herdr-event` record `HERDR_SESSION` on the ping (`Ping.herdrSession`, `nil` when unset or `default`), and a click focuses it with `herdr --session <name> …` (`HerdrFocus`). A ping listed to the Mac from another machine leaves its session out: the Mac focuses it with `herdr --machine`, in the session the saved machine names.
