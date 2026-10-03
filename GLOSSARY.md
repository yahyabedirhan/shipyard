# Shipyard

A macOS menu bar app that shows the pull requests, issues and workflow runs on the projects a user chooses, so they can review the work their agents, and other people, send in.

## Language

### What is shown

**Project**:
A named group of one or more GitHub repositories, shown as one section in the menu. Usually a single repository.
_Avoid_: Repo (when the group is meant), workspace

**Item**:
Anything listed under a project: a pull request, an issue, a workflow run, a ping or a note.
_Avoid_: Entry, row (a row is how an item is drawn, not the item)

**Row**:
One line in the menu: usually an item as the menu draws it, but a project's header and a repository's error line are rows too.
_Avoid_: Entry, line

**Closed window**:
How far back closed items stay visible, counted from when they were closed.
_Avoid_: History, retention

**Workflow run**:
One GitHub Actions run in a project's repositories. It's shown while it runs and for a short window after it finishes.
_Avoid_: Action, job, build, CI

**Note**:
The user's own note (an idea, a reminder, a "not now" thought), kept in Notion under its project, with a title, labels, and a number unique in the project that is never given twice. Open until it's archived. An agent writes one only for the user, in the user's words.
_Avoid_: Idea, memo, issue (an issue is GitHub's)

### What a project lists

**Repository selector**:
One entry of a project's `repositories`: a single repository (`owner/name`), everything under an owner (`owner/*`), or a repository group.
_Avoid_: Scope, source

**Repository group**:
A named set of repositories, following GitHub's own affiliations: `owned` (the user's own account), `organizations` (through membership of an organization), `collaborator` (someone else's repository that added the user), and `anywhere` (any repository, for pull requests waiting on the user's review).
_Avoid_: Scope, affiliation (GitHub's word, not the configuration's)

**Author selector**:
One entry of an author filter: an author group or a single login written `@login`.
_Avoid_: Mute, user filter

**Author group**:
A named set of authors: `me` (the user, and their agents working as them), `others` (anyone but the user and bots) and `bots` (GitHub bot accounts). Together they cover every author.
_Avoid_: Role, user type

**Listing**:
The items a project has after its filters (kind, states, window, drafts, authors, review requested). Only listed items are shown, counted and notified.
_Avoid_: Result, view, feed

**Review request**:
An open pull request asking for the user's review, directly or through one of their teams.
_Avoid_: Assigned PR, review queue (the queue is a preset)

### How a project is arranged

**Group**:
The items of a project that share one key: a kind, a repository, a date bucket or an author. A project's items are always arranged into groups, unless grouping is `none`.
_Avoid_: Category, bucket (except for dates)

**Subsection**:
A group drawn with its own subheader (a name and a count) instead of a divider line. Only a subsection can be folded.
_Avoid_: Subgroup, nested section

**Fold**:
To collapse a project or a subsection down to its header, or expand it again. Remembered in app state.
_Avoid_: Hide, minimize

**Show more**:
A group capped to its first few rows, with a row that reveals the rest (and then Show less). Not remembered: the cap comes back when the menu closes.
_Avoid_: Fold, pagination

### Attention

**Seen**:
An item the user has clicked, or marked seen, since its last change. Opening the menu doesn't make anything seen.
_Avoid_: Read

**Needs attention**:
An item that is unseen, or is open and changed since it was seen, or requests the user's review, or has failed checks. Closed items never need attention.
_Avoid_: Unread, new, pending

**Attention count**:
The number of items that need attention across all projects, shown in the menu bar.
_Avoid_: Badge, unread count

### Notifications

**Notification**:
A macOS banner shipyard posts when a notification rule matches an event. A ping can cause one; it isn't one.
_Avoid_: Ping, alert

**Event**:
A change in an item that shipyard can notify about, such as `pr.opened` or `run.failed`.

**Ping**:
A short message an agent sends the user through shipyard, filed under every project that watches the agent's repository, with one action that takes the user where the agent wants them: a link, an app, or a Herdr tab. Kept by shipyard itself, not fetched from GitHub. An agent can replace or withdraw a ping it sent, by its id. The Mac numbers pings in each project (`#1`, `#2`, …), in the order it first sees them, like issues in a repository; a machine's own section counts on its own. A replace keeps the number, and a number is never given twice.
_Avoid_: Notification (that's the macOS banner), message, alert

**Known agent**:
A coding agent shipyard recognises in a ping's sender, such as Claude Code or Codex, shown with that agent's real logo, which the app bundles.
_Avoid_: Agent icon, monogram

**Machine**:
A computer where agents run in Herdr, known to the Mac's Herdr as a saved machine by its label, such as `netcup-vps`. The user names the machines shipyard asks for pings by those labels. The Mac itself is the local machine.
_Avoid_: Host, server, remote (on its own)

**Remote ping**:
A ping sent on a machine other than the Mac. The Mac asks each machine for its pings and lists them beside its own, saying which machine each came from. One that no project takes is listed under its machine's name.
_Avoid_: Remote notification, synced ping

**Filing**:
Deciding which projects a ping is listed under: those that watch its repository, or the one project the agent names. The Mac files pings. A machine without the app keeps each one unfiled, as the agent sent it, and the Mac files it when it reads that machine's pings.
_Avoid_: Routing, sorting, assigning

**Unfiled ping**:
A ping kept as the agent sent it: its repository, or the project it named, unchecked. Every ping on a machine without the app is one until the Mac files it. A remote ping the Mac can't file lists under its machine's name.
_Avoid_: Orphan ping, unassigned ping

**Notification rule**:
An event, a scope (all projects or one project) and an optional author filter that together decide whether a macOS notification is sent.
_Avoid_: Alert, subscription, watch

### Settings and state

**Configuration**:
The user's choice of what the app shows and when it notifies: projects, item kinds, windows, refresh interval, notification rules. It lives in one file on the Mac, `config.toml`, that the user and their agents edit, and only the app acts on it.
_Avoid_: Settings, preferences, state

**CLI settings**:
What the `shipyard` command does on the machine it runs on, such as which Mac it sends notices to. They live in `cli.toml` on every machine, beside `config.toml` on the Mac, and only the command reads them. No setting is in both files. A missing file means the defaults; one that doesn't read stops the command that needs it.
_Avoid_: Configuration (the app's), CLI config, preferences

**App state**:
What shipyard remembers on its own from how the user uses it, such as collapsed sections and which items have been seen. Never written to the configuration.
_Avoid_: Configuration, cache

### Agents and the app

**App control**:
The commands an agent on the Mac uses to open, quit and ask about the running app, open and steer its panel, and capture it, without clicking. It never changes the configuration: switching the layout is still an edit to the file.
_Avoid_: Automation, remote control, scripting

**Screenshot**:
An image of the panel as it really looks, which the app captures on an agent's request. When the screen can't be captured, the app draws the panel itself and says so.
_Avoid_: Snapshot. To capture is the act; the screenshot is the image.

**Demo run**:
The app running on a folder of example configuration and state, so that screenshots show example data. The user's own configuration and app state are left untouched, and opening the app normally brings them back.
_Avoid_: Sandbox, test mode, fixture

**Lease**:
The right to use app control, held by one agent at a time. An agent's first app control command takes it and each later one renews it. It ends by itself a minute after the holder's last command, and five minutes after it was taken at most. The app refuses another agent's command while it's held. `shipyard control take` holds it to the five minutes on purpose, `release` gives it up, and a `take --wait` waits in line for it, first come, first served. The maintainer can stop it from the panel, which keeps that agent out for five minutes unless they allow it back. Asking for the app's status needs no lease.
_Avoid_: Lock, mutex, session

**Holder**:
The agent a lease is held by, or refused to: its key (the agent's session, else its own process), its name and its place (a Herdr pane, else its working folder). The `shipyard` command works it out on every call, so agents never pass it; a setup where that key doesn't stay the same names one in `SHIPYARD_CONTROL_KEY`.
_Avoid_: Owner, client, user

### Setup

**Onboarding**:
The flow shown when shipyard isn't connected to GitHub or has no projects: connect the GitHub account, then choose a preset and pick projects. Choosing them here writes the configuration.
_Avoid_: Setup wizard, welcome

**Preset**:
A ready-made configuration for one main use of shipyard, defined in the app and listed in the skill: `my-agents` (what you and your agents open), `incoming-contributions` (what others open on your repositories), `review-queue` (pull requests waiting on your review).
_Avoid_: Template, profile, mode
