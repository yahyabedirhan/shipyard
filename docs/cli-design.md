# CLI design

The design of the `shipyard` command line: who calls it, its command tree, its inputs, outputs and help, how the code keeps it, and how it changes.
Its commands, flags, output shapes and exit codes are a contract with agents, scripts and the herdr-shipyard plugin (ADR 0004).
`docs/low-level-design.md` holds the modules behind it; this page holds what a caller sees.

The page follows the CLI design delivery framework, one section per stage, in order:

1. **Requirements:** the callers, their jobs, the command roles, what each command needs to run, and what is out of scope.
2. **Command model:** the command tree, its nouns, verbs and targets, the previous command forms, and the renames from them.
3. **Inputs:** every command's usage line, its flags, the environment and the configuration.
4. **Output and errors:** what each command prints, its `--json`, its refusals, the exit codes and the error messages.
5. **Help:** the top help, the group help and the machine-readable listing.
6. **Implementation:** the files, the command table, one command's path, one refusal, and the contract tests.
7. **Evolution:** the likely changes and the rules for changing the contract.
8. **Verification:** the CLI checked against the framework's checklist.

## Requirements

### Callers

1. Coding agents on the Mac and on the user's other machines, the main caller of every command. They learn the CLI from the shipyard skill and from `--help`.
2. Programs: the herdr-shipyard plugin runs `herdr-event` from Herdr's hooks and `ping list --json` for the Mac's poll; the session-status mod runs `ping send` and `ping withdraw`; the workstation's `notification-method` runs `notice send`.
3. The maintainer at a terminal, now and then: checking the setup, listing pings, driving a demo.

### Jobs

A caller should be able to:

1. Ping the user and wait for them, replace or withdraw that ping, and list the machine's pings.
2. Tell the user about progress with a notice that isn't kept, and take it away.
3. Open, quit and ask about the Mac's app, steer its panel and capture it, without clicking.
4. Take turns on the app with other agents, through the lease.
5. Check `config.toml`, the theme files beside it, `cli.toml` and the notes workspace after an edit.
6. Let Herdr's hooks ping when an agent is blocked.

### Roles

| Role | Commands | Rules |
|---|---|---|
| Change data | `ping send`, `ping withdraw` | Local files only; safe to rerun with the same `--id` |
| Tell the user | `notice send`, `notice withdraw` | Reaches the app: its socket, the tailnet, or the plugin's queue |
| Read only | `ping list`, `app status`, `config check`, `notes check`, `help` | No lease |
| Act on the app | `app open`, `app quit`, `app capture`, `panel *` | Leased (ADR 0007), Mac only |
| Wait | `lease take --wait` | Bounded: 0 to 3600 seconds |
| Plumbing | `herdr-event` | Run by hooks; reads its input from the environment |

### Runtime

- `ping`, `config check`, `help` and `herdr-event` need only local files and work offline.
- `notice` needs the running app on the Mac, the tailnet to the app machine, or the plugin.
- `app`, `panel`, `lease` and `notes` need the Mac's app.
- `app open` works when the app isn't running and starts it.
- `app status` says the app isn't running and exits 1.

### Out of scope

- No interactive prompts or pickers.
- No colour.
- No shell completions.
- No Windows build.
- No command that changes `config.toml`: agents edit the file (ADR 0001).

## Command model

### Command tree

```text
shipyard
├── ping          send · withdraw · list               every machine
├── notice        send · withdraw                      every machine
├── app           open · quit · status · capture       Mac
├── panel         open · close · fold · unfold ·       Mac
│                 show-more · show-tab · show-view
├── lease         take · release                       Mac
├── notes         check                                Mac
├── config        check                                every machine
├── herdr-event                                        plumbing, every machine
└── help          [<group> | --json]
```

### Nouns

Nouns are the glossary's: ping, notice, app, panel, lease, notes, config.
Every group is a noun, and every command is `shipyard <noun> <verb>`, two levels at most.
`herdr-event` is the one exception, kept whole because the plugin's hooks call it by that name and no person runs it.

### Verbs

One meaning each:

| Verb | Meaning | Used on |
|---|---|---|
| `send` | deliver a message to the user | ping, notice |
| `withdraw` | take a sent message back by its id | ping, notice |
| `list` | print many items; changes nothing | ping |
| `status` | print the state of one running thing | app |
| `check` | read a setup and print each problem; exit 1 on an error | config, notes |
| `open` / `close` | bring up or dismiss a window or the app | app, panel |
| `quit` | end the running app | app |
| `capture` | save an image of what the app shows | app |
| `fold` / `unfold` | collapse or expand a project's section | panel |
| `show-*` | bring one part of the panel into view: more rows, a tab, a status view | panel |
| `take` / `release` | hold or give up the lease | lease |

### Targets

A command names what it acts on with a required word (`ping withdraw <id>`, `panel fold <project>`).
A ping or notice is filed by the working folder's repository unless `--repo` or `--project` names one: the current default, overridden by a flag.

### Previous command forms

Before this design, shipyard had nine top-level commands in a flat list, each module writing its own help lines.
The last column names the item in Verification that each finding fails.

| Finding | Evidence | Verification item |
|---|---|---|
| Sending was the group itself: `ping "<title>"` and `notify "<title>"`, while `ping withdraw` and `ping list` were verbs. A title equal to a verb needed `--` (`shipyard ping -- withdraw`). | `PingCommands.swift`, `NotifyCommand.swift` | 2 |
| The same idea had two names: the noun is *notice* (GLOSSARY.md) but the command was `notify`; the noun is *lease* but the command was `control`. | GLOSSARY.md "Notice", "Lease" | 3 |
| `screenshot` was a top-level verb about the app, beside `app`; GLOSSARY.md says *capture* is the act. | GLOSSARY.md "Screenshot" | 3, 4 |
| `panel tab <name>` and `panel view <name>` used nouns as verbs. | `PanelCommand.swift` | 2 |
| The top help was written by hand, twice per command, and had drifted: it left `--for` out of `control take`, and cut `notify`'s flags to `…`. | `ControlCommands.swift` `controlHelp` | 9 |
| `help ping` printed the top help and ignored `ping`; `ping list --help` printed `ping`'s help. | run the binary from before this design | 1 |
| A mistyped command printed the whole top help, 40 lines, after one line of error; so did every argument error in `app`, `panel`, `control` and `screenshot`. | `ShipyardCLI.run`, each `misread` | 7 |
| `ping list` refused to run without `--json`. | `PingCommand.list` | 6 |
| `herdr-event` was listed among the everyday commands, though only hooks run it, and `herdr-event --help` exited 2. | `PingCommands.swift` | 4 |
| No machine-readable listing of the commands for agents. | — | 9 |

What held from the previous forms:

- Exit codes 0, 1 and 2 on every command.
- Data on standard output and messages on standard error.
- No prompts.
- Every wait bounded.
- `--json` on `app status` and `config check`.
- The Mac-only refusal on Linux.

### Renames

Each old form is replaced, with no alias: an old form is refused like any unknown command (exit 2, one line).
The CLI, the skill and the callers move together in one release.

| Before | After | Rule it broke |
|---|---|---|
| `shipyard ping "<title>"` | `shipyard ping send "<title>"` | the group was also its verb; a title could clash with a verb |
| `shipyard notify "<title>"` | `shipyard notice send "<title>"` | the noun is *notice*; a verb as a group |
| `shipyard notify withdraw <id>` | `shipyard notice withdraw <id>` | the noun is *notice* |
| `shipyard screenshot <file.png>` | `shipyard app capture <file.png>` | a top-level verb about the app; *capture* is the act |
| `shipyard control take` / `release` | `shipyard lease take` / `release` | the noun is *lease* |
| `shipyard panel tab <name>` | `shipyard panel show-tab <name>` | a noun as a verb |
| `shipyard panel view <name>` | `shipyard panel show-view <name>` | a noun as a verb |

Unchanged: `ping withdraw`, `ping list --json`, `app open|quit|status`, `panel open|close|fold|unfold|show-more`, `notes check`, `config check`, `herdr-event`, and every flag.

## Inputs

### Usage lines

```text
shipyard ping send <title> [--body <text>] [--from <label>] [--id <id>]
                           [--open <url> | --app <bundle id or name> | --herdr [<tab or pane id>]]
                           [--repo <owner/name> | --project <name>]
shipyard ping withdraw <id>
shipyard ping list [--json]
shipyard notice send <title> [--subtitle <text>] [--body <text>] [--from <label>]
                             [--repo <owner/name> | --project <name>] [--image <path>]
                             [--sound default|none|<name>] [--thread <key>] [--level passive|active]
                             [--id <id>] [--open <url> | --app <app> | --herdr [<id>]]
                             [--button "<label>=<action>"]…
shipyard notice withdraw <id>
shipyard app open [--demo <folder>]
shipyard app quit
shipyard app status [--json]
shipyard app capture <file.png> [--appearance light|dark] [--menu-bar-icon] [--with-indicator]
shipyard panel open | close
shipyard panel fold <project> | unfold <project>
shipyard panel show-more <project> <kind>
shipyard panel show-tab <name>
shipyard panel show-view <name>
shipyard lease take [--wait <seconds>] [--for <purpose>] [--key <k>]
shipyard lease release [--key <k>]
shipyard notes check
shipyard config check [--json]
shipyard herdr-event
shipyard help [<group> | --json]
shipyard --version
```

### Words and flags

- A title, an id, a file and a project are words, in their natural order; everything else is a long flag.
- The same flag means the same thing on `ping send` and `notice send`.
- `--` ends the flags of `ping send` and `notice send`, so a title can start with a dash.
- `-h` and `--help` print help wherever they appear before `--`.

### Environment

- `SHIPYARD_CONTROL_KEY` names the lease holder (`--key` wins).
- `HERDR_PANE_ID` is the pane `--herdr` focuses with no id.
- `HERDR_PLUGIN_EVENT` and `HERDR_PLUGIN_EVENT_JSON` are `herdr-event`'s input.
- `SHIPYARD_SUPPORT_DIR` and `XDG_CONFIG_HOME` move the files, for demo runs and tests.

### Configuration

Precedence: flags, then `cli.toml` (where a notice goes), then built-in defaults.
The command never reads `config.toml` for its own behaviour, only to file a ping on the Mac.

### Interaction

No command prompts, and none takes a secret.

## Output and errors

### Output by command

| Command | Standard output | `--json` | Refusals (exit 1) |
|---|---|---|---|
| `ping send` | the ping's id | — | no project takes it; the store can't be written |
| `ping withdraw` | the id | — | no ping has the id |
| `ping list` | one line per live ping: id, age, title, where it's filed; `no pings` | one line, `PingList`'s shape, which the Mac reads | — |
| `notice send` | `shown`, or `queued` through the plugin | — | notices off for its projects; no project; the app not running; the plugin missing; the Mac unreachable |
| `notice withdraw` | `withdrawn` | — | the route refuses |
| `app open` / `quit` | one line on what happened | — | the app doesn't answer in time |
| `app status` | the version, the panel, the layout, the projects | one object | the app isn't running |
| `app capture` | the file's path | — | the app isn't running; nothing written |
| `panel *` | one line | — | the app isn't running; no such project, kind, tab or view, naming those that exist |
| `lease take` / `release` | `you hold shipyard until <HH:mm:ss>` / one line | — | another agent holds it |
| `notes check` | one line per project, then each problem | — | an error in the layout; the app isn't running |
| `config check` | each file's verdict, problems and warnings: `config.toml`, each theme file in file-name order, `cli.toml` | each file's result by name: `config.toml`, `themes/<file>`, `cli.toml` | a file has a problem |
| `help` | the top help, or a group's help | every command | — |

### `config check` output

Files checked (ADR 0014):

- The Mac's `shipyard` checks `config.toml`, then each `*.toml` theme file in the `themes` folder beside it, in file-name order, then `cli.toml`.
- The Linux `shipyard` checks `cli.toml` alone.

Each file prints its absolute path and `accepted` or `rejected`, then one indented `problem:` or `warning:` line per issue in the panel banner's words.
A theme file's problems read `themes/<file> line N: …`, and a theme file has no warnings.

```text
/Users/me/.config/shipyard/config.toml: accepted
/Users/me/.config/shipyard/themes/Sunset.toml: rejected
  problem: themes/Sunset.toml line 22: unknown token `any.accent.acent`; did you mean `accent`?
/Users/me/.config/shipyard/cli.toml: accepted (no file: the defaults)
```

`--json` prints one object with a key per file, `config.toml`, `themes/<file>` and `cli.toml`, each in `config-status.json`'s fields: `config` is the file's path and `configModified` its modification time.

### Exit codes

The same on every command:

| Code | Meaning |
|---|---|
| 0 | success |
| 1 | failed or refused, with one line on why |
| 2 | wrong usage, with one line and the help to read |

### Error messages

Errors are one line on standard error that names the command, says what is wrong and ends with the way out.

- Wrong usage: ``shipyard panel show-tab: missing <name>. Run `shipyard panel --help` for usage.``
- A mistyped group names the closest one and never runs it: ``shipyard: unknown command `pnig`. Did you mean `shipyard ping`? Run `shipyard --help` for the commands.``
- A Mac-only group on another machine: ``shipyard: `shipyard app` runs on the Mac, where the app is``.

### Old forms

Old forms are unknown commands.

- `shipyard notify` names `shipyard notice` as the closest group.
- `shipyard ping "<title>"` says ``shipyard ping: unknown command `<title>`; send a ping with `shipyard ping send <title>`. Run `shipyard ping --help` for usage.``

## Help

Three levels, each made from the same table.

### Top help

`shipyard --help` and `shipyard help` print the top help, grouped by job:

```text
shipyard: a macOS menu bar app for keeping up with your projects while your agents work

Usage: shipyard <group> <command> [options]

Tell the user (any machine):
  ping send <title> [options]     send the user a ping that waits until they click it
  ping withdraw <id>              take a ping back
  ping list [--json]              list this machine's live pings
  notice send <title> [options]   show the user a notice, a status message that isn't kept
  notice withdraw <id>            take a shown notice away

Drive the app (on the Mac):
  app open [--demo <folder>]         launch the app, or a demo run, and wait until it answers
  app quit                           quit the app and wait until it's gone
  app status [--json]                print whether the app runs, its version, layout and projects
  app capture <file.png> [options]   save the panel, or the menu bar icon, as a PNG
  panel open                         open the menu bar icon's panel
  panel close                        close the panel
  panel fold <project>               collapse a project's section
  panel unfold <project>             expand a project's section
  panel show-more <project> <kind>   show every row of a project's group past its cap
  panel show-tab <name>              show a tab of the tabs layout
  panel show-view <name>             show a status view, or the projects again
  lease take [options]               hold app control for a run of steps, waiting in line with --wait
  lease release [--key <k>]          give app control up to the next agent

Check the setup:
  notes check             check that the app can read the notes workspace in Notion
  config check [--json]   check the settings files, each problem and warning with its line

Plumbing (run by Herdr's plugin hooks, not by hand):
  herdr-event   ping when a Herdr agent is blocked, and withdraw it when it goes on

Options:
  -h, --help   show help; `shipyard <group> --help` for a group's commands
  --version    print the version

Environment:
  SHIPYARD_CONTROL_KEY   the holder key app, panel and lease commands are sent as

Exit codes: 0 success, 1 failed or refused, 2 wrong usage.

Agents: `shipyard help --json` lists every command as JSON.
Learn more: docs/cli-design.md in github.com/yahyabedirhan/shipyard.
```

A build lists only the groups it links: on Linux the "Drive the app" section and `notes` are left out.

### Group help

`shipyard <group> --help`, `shipyard help <group>`, and `shipyard <group>` alone on standard error print the group help, in this order:

1. A summary line.
2. A `Usage:` block with every command's full usage.
3. Examples.
4. Each command's details.
5. The group's exit codes.

`ping` and `notice` hold every flag there, since `send` is where they're used.

### Machine-readable listing

`shipyard help --json` prints `version` and `commands` (each `group`, `usage`, `summary`, `section`).
Agents read it to learn the build's commands without parsing text.

## Implementation

### Files

```text
Sources/
├── ShipyardCommand/
│   ├── CommandTable.swift          the table (Entry, Command, Section), macOnly; ShipyardCLI: the top help,
│   │                               help --json, help <group>, the closest-name hint, and routing
│   ├── CommandResult.swift         output, error, status 0 / 1 / 2
│   └── ConfigurationCommands.swift config
├── ShipyardPings/PingCommands.swift ping (send, withdraw, list) and herdr-event
├── ShipyardNotices/NotifyCommand.swift notice (send, withdraw)
├── ShipyardControl/ControlCommands.swift app (with capture), panel, lease, notes; their parsers in
│                                   ControlCommand, PanelCommand, LeaseCommand, ScreenshotCommand
└── ShipyardCLI/main.swift          assembles the build's table and prints what ShipyardCLI.run returns
```

### Command table

- `CommandTable.Entry` is one group: `name`, `section`, `commands` and `run`.
- `CommandTable.Command` is one command: its `usage` after the group's name, verb first, and its one-line `summary`.
- The top help and `help --json` are made from these, so a group a build doesn't link is never listed.
- Each group's detailed help (`usageText`) lives beside its parser, and a contract test checks it names every command in the table.

### Command path

`shipyard notice send "done" --from claude`:

```text
main.swift                    builds the table: ping, notice, app, panel, lease, notes, config, herdr-event
└── ShipyardCLI.run(["notice", "send", "done", "--from", "claude"])
    ├── not --help, help or --version
    ├── table.entry(named: "notice")
    └── NoticeCommands' run(["send", "done", "--from", "claude"])
        └── verb "send" → NotifyCommand.run(["done", "--from", "claude"])
            └── ControlNoticeRoute → the app → "shown", exit 0
```

### Refusal path

`shipyard app capture` with no file:

```text
ShipyardCLI.run(["app", "capture"])
└── table.entry(named: "app")
    └── run sees "capture" → ScreenshotCommand.parse([])
        └── .usage("shipyard app capture: missing <file.png>. Run `shipyard app capture --help` for usage."), exit 2
```

Nothing is sent to the app.

### Contract tests

`CommandTableTests` checks that:

- Every old form is refused in one line and runs nothing.
- Every group's `--help` names each of its table commands.
- A mistyped group suggests the closest one in one line.
- `help --json` lists every command.
- `help <group>` is `<group> --help`.

`SkillDocumentTests` checks that the skill teaches each command as it's built.

## Evolution

### Likely changes

| Change | What you touch |
|---|---|
| A new verb on a group, such as `ping get <id>` | the group's parser, one `Command` in its table entry, its `usageText`; the top help and `help --json` follow |
| A new group, such as `notes list` growing into `note` | one `Entry` in its module and `main.swift`'s `add`; `macOnly` when it needs the app |
| A new flag | the parser and the group's `usageText`; additive, no rename |
| A rename | the parser, the table's `Command`, the skill, the docs, and every caller in the same release |

### Contract rules

- Add before changing: a new command, flag or JSON field breaks no caller.
- A rename is a breaking change: it ships with the skill, the herdr-shipyard plugin and every caller updated in the same release, and the changelog says so. No aliases are kept.
- `ping list --json`'s shape is read by older Macs through Herdr: change it only by adding fields.
- The skill, the herdr-shipyard plugin and the docs ship with the release that changes a command.
- The callers outside this repository (the session-status mod's `ping`, the workstation's `notification-method`) move to the new forms in the same release, since the new `shipyard` refuses the old ones and an older one doesn't know the new ones.

## Verification

| # | Item | Status |
|---|---|---|
| 1 | Each job can be done from the help alone | yes: the group help holds every flag and an example |
| 2 | Each verb means one thing; each idea has one name | yes, after the renames |
| 3 | Every noun is the glossary's | yes |
| 4 | Two levels at most; everyday commands at the top | yes; `herdr-event` is listed apart as plumbing |
| 5 | The same flag means the same thing everywhere | yes |
| 6 | `--json` on every command that prints data | `ping list`, `app status`, `config check`, `help`; `notes check` prints text only |
| 7 | Every error says what to do next; every exit code documented | yes |
| 8 | Nothing prompts or hangs | yes: no prompts; every wait bounded |
| 9 | Every list in the help is made from the table | the top help and `help --json`; each group's detailed help is written beside its parser and tested against the table |
| 10 | Every example tested; every command named in a doc exists | the skill's examples are parsed by `SkillDocumentTests` |
| 11 | Every rename leaves an alias; breaking changes announced | no aliases, by choice: the renames ship as one breaking release, announced in CHANGELOG.md |
