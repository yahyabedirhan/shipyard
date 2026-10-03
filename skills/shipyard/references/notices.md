# Notices

A **notice** is a status message you post with `shipyard notify`: a macOS notification titled with the project and your title, over your body and who sent it. It's shown when the user's notification rules select `agent.notice` for the project it's filed under, and it's never listed, counted or kept. Use it for progress the user may want to glance at ("orchestration started", "tests running", "done"); use a ping for what they must act on (see Ping or notice? in [SKILL.md](../SKILL.md)).

## The command

The command is found as for pings (`~/.local/bin/shipyard`), on the user's Mac and on their other machines. Where you run decides the route the notice takes (see Routes, below).

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

## Routes

A notice reaches the user's Mac one of three ways. You don't pick one: the machine you run on does, and the command's output tells you which it took.

| Where you run | Route | What it prints |
|---|---|---|
| the Mac | straight to the running shipyard app, which says whether it was shown; shipyard is never started for a notice | `shown` |
| another machine whose `cli.toml` has `[notify] app-machine` set | over the user's tailnet to the Mac's app, within about a second, which says whether it was shown | `shown` |
| another machine without `app-machine` | left with the herdr-shipyard plugin, which holds it until the Mac's next poll of the machine, the poll remote pings take | `queued; shown within about 30 seconds if the Mac is awake` |

To tell which a machine uses before sending, look for `app-machine` under `[notify]` in its `cli.toml` (`~/.config/shipyard/cli.toml`, or under `$XDG_CONFIG_HOME`); no file, or no `app-machine` in it, means the poll route.

On the poll route, `queued` isn't `shown`:

- **The Mac decides when it arrives.** The same rules apply as to any notice, so one for a project with notices off is dropped there, and you aren't told.
- **Late is dropped.** A notice more than ten minutes old when the Mac collects it is dropped: the Mac asleep, away or not polling the machine. Don't resend; a stale status isn't worth showing.
- **The plugin must be installed** (`herdr plugin install yahyabedirhan/herdr-shipyard`), which also puts `shipyard` on the machine.

## Exit codes

- **0**: shown, printing `shown`; or, on the poll route, queued for the Mac, printing `queued; shown within about 30 seconds if the Mac is awake`.
- **1**: not shown, with one line on standard error, `shipyard notify: ` and why. Don't retry; tell the user in your reply if it mattered.
  - "notices are off for project `<name>`" (or projects, naming each): the user's rules leave out `agent.notice` there. They chose that; don't turn it back on unasked, and don't send the same thing as a ping instead.
  - "shipyard isn't running, so this notice wasn't shown": the app is quit. Don't start it for a notice.
  - "shipyard's notifications are off in System Settings, so this notice wasn't shown": the user turned them off for the whole app.
  - no project takes it: `no project is named …` or `no project watches …`, listing the projects. Pass `--project <name>`, or leave it.
  - the working folder has no `origin`: pass `--repo <owner/name>` or `--project <name>`.
  - on the poll route, the herdr-shipyard plugin is missing ("… isn't the herdr-shipyard plugin's link …"), too old to hold notices ("… can't hold notices; update it …"), or didn't queue this one ("the herdr-shipyard plugin didn't queue this notice: …", such as a notice too large). Tell the user the line if it mattered; installing or updating the plugin is theirs to do.
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
