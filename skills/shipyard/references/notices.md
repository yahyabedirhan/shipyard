# Notices

A **notice** is a status message you post with `shipyard notify`: a macOS notification titled with the project and your title, over your body and who sent it. It's shown when the user's notification rules select `agent.notice` for the project it's filed under, and it's never listed, counted or kept. Use it for progress the user may want to glance at ("orchestration started", "tests running", "done"); use a ping for what they must act on (see Ping or notice? in [SKILL.md](../SKILL.md)).

## The command

On the user's Mac, the command is found as for pings (`~/.local/bin/shipyard`). The notice goes straight to the running shipyard app, which says whether it was shown; shipyard is never started for a notice. On another machine `shipyard notify` isn't available yet: it exits 2, "runs on the Mac, where the app is"; ping there instead only when the user should act.

```sh
shipyard notify "<title>" [--body <text>] [--from <label>]
                          [--repo <owner/name> | --project <name>]
```

| Flag | What it does |
|---|---|
| `"<title>"` | the one line the notification shows after the project's name; quote it, it's one argument |
| `--body <text>` | more than the title fits, shown under it |
| `--from <label>` | who sent it, such as your name and the task (`"claude · checkout"`), shown under the body as "from <label>" |
| `--repo <owner/name>` | file it by this repository instead of the working folder's |
| `--project <name>` | file it under this one project, by its `name` in `config.toml` |
| `--` | ends the flags: everything after it is the title, even a word starting with `--` |

- **Where it's filed.** As a ping is: without `--repo` or `--project`, the repository is the working folder's git remote `origin`, and the notice goes under every project that watches it. It's shown once, under the first of those whose rules select `agent.notice`. `--repo` and `--project` don't go together.
- **Each notice is its own.** Two notices with the same title are two notifications. Nothing replaces or withdraws one; it leaves Notification Center as the user's settings say.
- **Clicking it** only dismisses it.

## Exit codes

- **0**: shown. It prints `shown`.
- **1**: not shown, with one line on standard error, `shipyard notify: ` and why. Don't retry; tell the user in your reply if it mattered.
  - "notices are off for project `<name>`" (or projects, naming each): the user's rules leave out `agent.notice` there. They chose that; don't turn it back on unasked, and don't send the same thing as a ping instead.
  - "shipyard isn't running, so this notice wasn't shown": the app is quit. Don't start it for a notice.
  - "shipyard's notifications are off in System Settings, so this notice wasn't shown": the user turned them off for the whole app.
  - no project takes it: `no project is named …` or `no project watches …`, listing the projects. Pass `--project <name>`, or leave it.
  - the working folder has no `origin`: pass `--repo <owner/name>` or `--project <name>`.
- **2**: the arguments don't read (a missing title, two titles, an unknown option, `--repo` and `--project` together), with what's wrong.

## Worked notices

**Starting a long run.** At the start of an orchestration, from the checkout:

```sh
shipyard notify "Orchestration started" --body "4 tickets, 2 in parallel" --from "claude · notes"
```

**Progress, filed by name.** Outside a checkout, or for a project that isn't the folder's:

```sh
shipyard notify "Tests running" --body "12 of 40 passed" --project shipyard
```

**Done.** When the run finishes, a notice says so; the pull request that needs review is a ping (see Sending pings in [SKILL.md](../SKILL.md)):

```sh
shipyard notify "Done" --from claude
```
