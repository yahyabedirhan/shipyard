# Messaging kit

The one source of truth for what every public surface says about shipyard: the README, the repository's description and topics, the site, the social cards, the app's own help and the launch posts.
Every surface quotes this file, and nothing contradicts it.
When the product changes, change this file first, then the surfaces.

## Name

- **Name:** `shipyard`, always lowercase in prose, headings and copy, also at the start of a sentence.
- **The app's bundle:** `Shipyard.app`, as macOS shows it in Finder and in notifications. Use it only where a path or a window title names the bundle.
- **The command:** `shipyard`, in code font.
- **Never:** "ShipYard", "Ship Yard", "the Shipyard app" in prose.

## Category

A macOS menu bar app for pull requests.

## One line

The positioning is not chosen yet.
Each candidate is under 80 characters, and each is a variant to show on the positioning board, with its id.

| Id | One line | Characters |
|---|---|---|
| `positioning/A` | A macOS menu bar app for the pull requests your agents open. | 60 |
| `positioning/B` | See, review and triage what your coding agents ship, from the menu bar. | 71 |
| `positioning/C` | Your agents' pull requests, issues and runs, one click away in the menu bar. | 76 |

Until one is picked, every surface uses `positioning/A`.
The README's current line, "A macOS menu bar app for seeing and reviewing the pull requests your agents open on your behalf.", is 96 characters, over the limit, and goes when the choice is made.

## Uses

Two uses, as equals.
Every surface names both or neither.

- **Your agents' work:** the pull requests, issues and workflow runs that you and your agents open.
- **Other people's work:** what other people open on your repositories, and the pull requests waiting on your review anywhere.

## Reach

Every GitHub repository your account can read, on github.com, from one Mac, with pings from your machines that run Herdr with the herdr-shipyard plugin.

## Proof points

Each one is true of the code today.

- **One number in the menu bar,** by default: how many items need attention: new, changed since you last opened them, waiting on your review, or failing their checks.
- **One file, edited by you or your agents:** everything lives in `~/.config/shipyard/config.toml`, every key is optional, and each save applies at once. A broken edit keeps the last good configuration and shows the error.
- **An agent skill:** `npx skills add yahyabedirhan/shipyard -g -y` teaches coding agents to change the file in your words.
- **Pings from agents:** `shipyard ping send` lists a message under the project the agent works in, with a notification, and its click opens a link, an app or the agent's Herdr pane.
- **Pings from other machines:** the `shipyard` command runs on Linux too, and the Mac collects pings from the machines named in `[remote] machines`, which run Herdr with the herdr-shipyard plugin.
- **Three presets:** `my-agents`, `incoming-contributions` and `review-queue`, offered on first launch.
- **Notes in Notion:** optional, one database per project, listed beside the pull requests.
- **Native and open:** a Swift app with no Dock icon, open source under Apache 2.0.

## Non-claims

What shipyard does not do yet.
Each one is stated once, plainly, in the docs' Limits section, and never in marketing copy.

- It runs on macOS 14 or later only. The `shipyard` command also runs on Linux, without the app.
- It reads github.com only. GitHub Enterprise Server is not supported.
- The download is not notarized yet: macOS asks you to clear the quarantine flag before the first launch. PLACEHOLDER: remove this line when the notarized build ships.
- There is no Homebrew cask and no automatic update yet. PLACEHOLDER: remove this line when the cask ships.
- Its settings live in `config.toml`. The app's settings menu shows the setup of GitHub, Notion, the skill and the command, the layout button switches between list and tabs, and the rest is edited in the file, by you or your agents.
- With Herdr 0.9.3, clicking another machine's ping focuses its pane on that machine, but the Mac's Herdr window moves there only when it already shows that machine.

## Glossary

The public names, as `GLOSSARY.md` defines them.
Use only these words on public surfaces.

| Name | Means | Not |
|---|---|---|
| project | A named group of one or more repositories, one section of the menu | repo group, workspace |
| item | A pull request, issue, workflow run, ping or note listed under a project | entry |
| needs attention | Unseen, changed since seen, requesting your review, or failing its checks | unread, new |
| attention count | The number in the menu bar | badge, unread count |
| preset | A ready-made configuration for one use | template, profile |
| layout | `list` or `tabs` | view, mode |
| ping | An agent's message to you, listed until you have seen it and its `seen-window` passes | notification, alert |
| notice | An agent's disposable status message, such as "tests running" | ping, toast |
| notification | The macOS banner shipyard posts when a rule matches | ping, alert |
| note | Your own note, kept in Notion per project | idea, memo |
| configuration | `config.toml`: what the app shows and when it notifies | settings, preferences |
| agent skill | The `shipyard` skill that teaches agents to edit the configuration | plugin, integration |
| the `shipyard` command | The command line tool inside the app, also built for Linux | CLI tool, binary |

## Install

The first screen of every surface carries these lines.

```sh
git clone https://github.com/yahyabedirhan/shipyard.git
cd shipyard
make install
```

Or download `Shipyard-<version>-macos.zip` from the [latest release](https://github.com/yahyabedirhan/shipyard/releases/latest).
PLACEHOLDER: the notarized download and `brew install --cask shipyard` replace the zip's quarantine steps at the last launch step.

The agent path:

```sh
npx skills add yahyabedirhan/shipyard -g -y
```

Then ask your agent: "Watch this repo in shipyard".

## Links

| Link | Address |
|---|---|
| Product site | `https://shipyard.yahyapak.dev` (PLACEHOLDER: live at launch) |
| Docs | `https://shipyard.yahyapak.dev/docs` (PLACEHOLDER: live at launch) |
| Code host | `https://github.com/yahyabedirhan/shipyard` |
| Releases | `https://github.com/yahyabedirhan/shipyard/releases/latest` |
| Agent skill | `npx skills add yahyabedirhan/shipyard` |
| Herdr plugin | `https://github.com/yahyabedirhan/herdr-shipyard` |
| Personal site page | `https://yahyapak.dev/projects/shipyard` (PLACEHOLDER: live at launch) |

## Channel lengths

Each surface says the one line in its own length, never a different idea.

| Channel | Field | Text | Limit |
|---|---|---|---|
| GitHub | Repository description | The one line | 350 characters |
| GitHub | Topics | `macos`, `menu-bar`, `menubar-app`, `swift`, `swiftui`, `github`, `pull-requests`, `code-review`, `coding-agents`, `ai-agents`, `claude-code`, `codex`, `agent-skills`, `notifications`, `developer-tools` | 20, lowercase, hyphenated |
| GitHub | Website | `https://shipyard.yahyapak.dev` | |
| GitHub | Social preview | The name, the one line and the logo, 1280 by 640 | |
| Web | Page title | `shipyard: <page>` | About 60 characters |
| Web | Meta description | The one line, then one proof point | About 155 characters |
| Open Graph | Image | The page's card, 1200 by 630 | |
| `shipyard --help` | First line | The one line | One line |

## Rules

- Examples on first screens show only shipyard's own keys and commands. Edge cases go in the docs.
- Leave use categories out of the one line. Show what shipyard lists, and let people bring their own uses.
- Say only what the app does today. Describe behavior, and leave how it looks to the screenshots.
- State each limit once, in the docs' Limits section.
- A `PLACEHOLDER:` marker names a gap that a later launch step fills. The launch check fails while one is open.
