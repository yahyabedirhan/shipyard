# Notices

A **notice** is a status message you post with `shipyard notify`: a macOS notification titled with the project and your title, over your body and who sent it. It's shown when the user's notification rules select `agent.notice` for the project it's filed under, and it's never listed, counted or kept. Use it for progress the user may want to glance at ("orchestration started", "tests running", "done"); use a ping for what they must act on (see Ping or notice? in [SKILL.md](../SKILL.md)).

## The command

The command is found as for pings (`~/.local/bin/shipyard`), on the user's Mac and on their other machines. Where you run decides the route the notice takes (see Routes, below).

```sh
shipyard notify "<title>" [--subtitle <text>] [--body <text>] [--from <label>]
                          [--repo <owner/name> | --project <name>]
                          [--image <path>] [--sound default|none|<name>]
                          [--thread <key>] [--level passive|active] [--id <id>]
                          [--open <url> | --app <bundle id or name> | --herdr [<tab or pane id>]]
                          [--button "<label>=<action>"]…
shipyard notify withdraw <id>
```

| Flag | What it does |
|---|---|
| `"<title>"` | the one line the notification shows after the project's name; quote it, it's one argument |
| `--subtitle <text>` | a line between the title and the body |
| `--body <text>` | more than the title fits, shown under it |
| `--from <label>` | who sent it, such as your name and the task (`"claude · checkout"`), shown under the body as "from <label>" |
| `--repo <owner/name>` | file it by this repository instead of the working folder's |
| `--project <name>` | file it under this one project, by its `name` in `config.toml` |
| `--image <path>` | a PNG, JPEG or GIF shown with it, 5 MB at most; a relative path is from the working folder |
| `--sound <sound>` | `default` (without the flag too), `none` for a quiet update, or a sound's name such as `Glass` |
| `--thread <key>` | stacks it in Notification Center with the other notices of this key, such as one orchestration's; without it, it stacks with its project's |
| `--level <level>` | `passive`: into Notification Center without a banner, for routine updates; `active`, the default: a banner. Critical and time-sensitive aren't offered |
| `--id <id>` | shows it under this id: a later notice with the same id replaces it in place, and `shipyard notify withdraw <id>` takes it away. 1 to 64 lowercase letters, digits, `-` and `_` |
| `--open <url>` | clicking it opens the URL (a pull request, a run, an artifact) |
| `--app <bundle id or name>` | clicking it brings the app forward |
| `--herdr [<id>]` | clicking it focuses this Herdr tab or pane (`w1:t2`, `w1:p3`), then your terminal; with no id, your own pane (`$HERDR_PANE_ID`), as a ping's `--herdr`. Not on the tailnet route (see Routes) |
| `--button "<label>=<action>"` | a button, up to 3, each with its own action: `open:<url>`, `app:<bundle id or name>`, `herdr:<tab or pane id>`, or `herdr` alone for your own pane (no `herdr` button on the tailnet route) |
| `--` | ends the flags: everything after it is the title, even a word starting with `--` |

- **Where it's filed.** As a ping is: without `--repo` or `--project`, the repository is the working folder's git remote `origin`, and the notice goes under every project that watches it. It's shown once, under the first of those whose rules select `agent.notice`. `--repo` and `--project` don't go together.
- **Each notice is its own** unless you give it an `--id`: two notices with the same title are two notifications. A notice with an id replaces the one shown under it, so "tests 3/10" can become "tests 10/10" in place; the ids are the user's, across agents, so make yours specific (`checkout-tests`, not `tests`).
- **Clicking it** runs its `--open`, `--app` or `--herdr` action, one at most; without one, it only dismisses it. Buttons show under the notification's Options, or on it when the user's style for shipyard is Alerts.
- **Withdrawing** an id that isn't shown (already dismissed, or never sent) is no error.

## Routes

A notice reaches the user's Mac one of three ways. You don't pick one: the machine you run on does, and the command's output tells you which it took.

| Where you run | Route | What it prints |
|---|---|---|
| the Mac | straight to the running shipyard app, which says whether it was shown; shipyard is never started for a notice | `shown` |
| another machine whose `cli.toml` has `[notices] app-machine` set | over the user's tailnet to the Mac's app, within about a second, which says whether it was shown | `shown` |
| another machine without `app-machine` | left with the herdr-shipyard plugin, which holds it until the Mac's next poll of the machine, the poll remote pings take | `queued; shown within about 30 seconds if the Mac is awake` |

**No Herdr on the tailnet route.** A notice sent over the tailnet carries no machine, so a `--herdr` click or a `herdr` button would focus the Mac's own Herdr, not your pane: the command refuses it before sending (exit 2), and the Mac refuses one that arrives anyway. There, use `--open` or `--app`; to keep the Herdr action, leave `app-machine` out of the machine's `cli.toml` so the notice takes the poll route, which focuses your pane on your machine as a remote ping's does.

Setting up the tailnet route is in Receive notices from another machine, below. To tell which a machine uses before sending, look for `app-machine` under `[notices]` in its `cli.toml` (`~/.config/shipyard/cli.toml`, or under `$XDG_CONFIG_HOME`); no file, or no `app-machine` in it, means the poll route.

On the poll route, `queued` isn't `shown`:

- **The Mac decides when it arrives.** The same rules apply as to any notice, so one for a project with notices off is dropped there, and you aren't told.
- **Late is dropped.** A notice more than ten minutes old when the Mac collects it is dropped: the Mac asleep, away or not polling the machine. Don't resend; a stale status isn't worth showing.
- **No image.** `--image` isn't carried: the notice arrives without it.
- **An id works on what's waiting.** A notice with the `--id` of one still waiting replaces it in the queue; `withdraw <id>` takes a waiting one away, but not one the Mac already showed.
- **The plugin must be installed** (`herdr plugin install yahyabedirhan/herdr-shipyard`), which also puts `shipyard` on the machine.

## Exit codes

- **0**: shown, printing `shown`; or, on the poll route, queued for the Mac, printing `queued; shown within about 30 seconds if the Mac is awake`. `withdraw` prints `withdrawn`, or on the poll route `withdrawn if it was still waiting; one the Mac already showed stays`.
- **1**: not shown, with one line on standard error, `shipyard notify: ` and why. Don't retry; tell the user in your reply if it mattered.
  - "notices are off for project `<name>`" (or projects, naming each): the user's rules leave out `agent.notice` there. They chose that; don't turn it back on unasked, and don't send the same thing as a ping instead.
  - "shipyard isn't running, so this notice wasn't shown": the app is quit. Don't start it for a notice.
  - "shipyard's notifications are off in System Settings, so this notice wasn't shown": the user turned them off for the whole app.
  - no project takes it: `no project is named …` or `no project watches …`, listing the projects. Pass `--project <name>`, or leave it.
  - the working folder has no `origin`: pass `--repo <owner/name>` or `--project <name>`.
  - on the poll route, the herdr-shipyard plugin is missing ("… isn't the herdr-shipyard plugin's link …"), too old to hold notices ("… can't hold notices; update it …"), or didn't queue this one ("the herdr-shipyard plugin didn't queue this notice: …", such as a notice too large). Tell the user the line if it mattered; installing or updating the plugin is theirs to do.
  - on the tailnet route:
    - "couldn't reach the app machine `<name>` …" or "the app machine `<name>` didn't answer within <n> seconds …": the Mac is asleep, away or off the tailnet. Nothing is queued or retried.
    - "the app machine `<name>` answered HTTP <status> without a verdict …": the Mac answered, but not shipyard: the app isn't running, `[notices] listen` isn't `true`, or `tailscale serve` points elsewhere.
    - "… isn't this Mac's Tailscale login …", "the request carried no Tailscale login …" or "shipyard couldn't learn this Mac's Tailscale login …": the identity check refused it (see below).
  - on another machine, "…/cli.toml doesn't read (…)": fix the file it names; nothing is sent either way until it reads.
- **2**: the arguments don't read, with what's wrong: a missing title, two titles, an unknown option, `--repo` and `--project` together, two click actions, a fourth button, a button without `<label>=<action>`, a level other than `passive` or `active`, an id that isn't one, a `--herdr` click or a `herdr` button on the tailnet route, or an image that can't be read, isn't a PNG, JPEG or GIF, or is over 5 MB.

## Receive notices from another machine

A notice from another machine goes straight to the Mac over the user's tailnet (Tailscale) and shows within about a second. Nothing is opened to the internet: the app listens on the Mac's 127.0.0.1 only, `tailscale serve` exposes that port to the user's own tailnet, and the app takes a notice only when Tailscale says it came from the Mac's own Tailscale login. Shipyard never installs or configures Tailscale; the user (or you, when asked) runs these steps once.

1. **Both machines on the tailnet as the user.** The Mac and the other machine are logged in to Tailscale as the same user, as the user's own devices: not tagged (a tagged device's requests carry no login, so they're refused), and with key expiry turned off in the admin console so they stay on.
2. **The Mac listens.** In `config.toml`:

   ```toml
   [notices]
   listen = true
   # port = 47420   the default; change it here and in the two steps below together
   ```

3. **Tailscale exposes the port on the Mac**, in the background, so it survives a restart:

   ```sh
   tailscale serve --bg --http=47420 http://127.0.0.1:47420
   ```

   `tailscale serve status` shows it. Should `--http` not work on the user's tailnet, `--https=443` with the same target serves it over HTTPS instead; then the machine's `cli.toml` says `app-scheme = "https"` and `app-port = 443`.
4. **The machine names its Mac** in its own `cli.toml` (`~/.config/shipyard/cli.toml`, or under `$XDG_CONFIG_HOME`), by the Mac's MagicDNS name, short or full (`tailscale status` on the machine lists it):

   ```toml
   [notices]
   app-machine = "my-mac"
   # app-scheme = "http"   http or https, as tailscale serve exposes it
   # app-port = 47420      the port tailscale serve exposes
   ```

   `cli.toml` is the command's own file, not the app's: `app-machine`, `app-scheme` and `app-port` go there, never in `config.toml` (whose `[notices]` has the Mac's `listen` and `port`), and an unknown key in it is an error.
5. **A test notice**, from the machine:

   ```sh
   shipyard notify "Hello from the VPS" --project shipyard
   ```

   It prints `shown` once the Mac showed it; otherwise it exits 1 with why (see Exit codes).

From then on `shipyard notify` on that machine takes the same flags as on the Mac, except a Herdr click or button (see Routes). `shipyard notify withdraw <id>` goes the same way. It waits up to 3 seconds for the Mac's answer (a few more for a notice carrying an image), and nothing is queued: a Mac asleep or away means exit 1.

## Worked notices

**Starting a long run.** At the start of an orchestration, from the checkout, stacked under one thread:

```sh
shipyard notify "Orchestration started" --body "4 tickets, 2 in parallel" --from "claude · notes" --thread notes-effort
```

**Progress, in place.** The same id replaces the last update, quietly:

```sh
shipyard notify "Tests running" --body "12 of 40 passed" --project shipyard --id shipyard-tests --level passive --sound none
shipyard notify "Tests passed" --body "40 of 40" --project shipyard --id shipyard-tests
```

**Done, with somewhere to go.** A click opens the pull request, a button brings the user to your pane; the pull request that needs review is still a ping (see Sending pings in [SKILL.md](../SKILL.md)). The pane button works on the Mac and on the poll route; on the tailnet route, leave it out:

```sh
shipyard notify "Done" --from claude --open https://github.com/owner/shop/pull/7 --button "Your pane=herdr:w1:p3" --button "CI=open:https://github.com/owner/shop/actions"
```

**A chart with it:**

```sh
shipyard notify "Benchmark finished" --subtitle "checkout" --image bench.png
```

**Taking a status away** once it's out of date:

```sh
shipyard notify withdraw shipyard-tests
```
