# Shipyard

A macOS menu bar app that shows the pull requests, issues and workflow runs on the projects a user chooses, so they can review the work their agents, and other people, send in.

## Language

### What is shown

**Project**:
A named group of one or more GitHub repositories, shown as one section in the menu. Usually a single repository.
_Avoid_: Repo (when the group is meant), workspace

**Item**:
Anything listed under a project: a pull request, an issue or a workflow run.
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

**Event**:
A change in an item that shipyard can notify about, such as `pr.opened` or `run.failed`.

**Notification rule**:
An event, a scope (all projects or one project) and an optional author filter that together decide whether a macOS notification is sent.
_Avoid_: Alert, subscription, watch

### Settings and state

**Configuration**:
The user's choice of what shipyard shows and when it notifies: projects, item kinds, windows, refresh interval, notification rules. It lives in one file that the user and their agents edit.
_Avoid_: Settings, preferences, state

**App state**:
What shipyard remembers on its own from how the user uses it, such as collapsed sections and which items have been seen. Never written to the configuration.
_Avoid_: Configuration, cache

### Setup

**Onboarding**:
The flow shown when shipyard isn't connected to GitHub or has no projects: connect the GitHub account, then choose a preset and pick projects. Choosing them here writes the configuration.
_Avoid_: Setup wizard, welcome

**Preset**:
A ready-made configuration for one main use of shipyard, defined in the app and listed in the skill: `my-agents` (what you and your agents open), `incoming-contributions` (what others open on your repositories), `review-queue` (pull requests waiting on your review).
_Avoid_: Template, profile, mode
