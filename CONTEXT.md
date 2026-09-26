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
The flow shown when shipyard isn't connected to GitHub or has no projects: connect the GitHub account, then pick projects. Picking projects here writes the configuration.
_Avoid_: Setup wizard, welcome
