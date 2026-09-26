# shipyard presets

A preset is a ready-made configuration for one main use of shipyard. The app offers the same three when it's set up (its onboarding writes the one the user chooses), so a user may name one: "set shipyard up as a review queue".

| Preset | For | Asks for |
|---|---|---|
| `my-agents` | the pull requests and issues the user and their agents open, one project per repository | the repositories to watch |
| `incoming-contributions` | the pull requests and issues other people open on the user's repositories, bots hidden, plus the pull requests waiting on their review anywhere | all their repositories (`owned`, as written below) or the ones they pick |
| `review-queue` | only the pull requests waiting on the user's review, in any repository | nothing |

## Starting from one

1. Pick the preset whose use matches the request, and ask the user which one when none clearly does.
2. Write the preset's file as the whole of `config.toml` only when the file is missing or holds nothing live but `version` (the app's commented header). Otherwise the file is the user's: make the request's change with the keys in the skill instead, taking from the preset only the lines the request needs.
3. Put the user's repositories in place of the examples: in `my-agents`, one `[[projects]]` block per repository, named after it; in `incoming-contributions`, the "Incoming" project's `repositories` (keep `owned` for all of the user's own).
4. Check the edit as the skill says.

## `my-agents`

Everything the user and their agents open in their repositories: pull requests and issues, grouped by kind, one project per repository. Notifications are the default: every new pull request.

```toml
#:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json
# shipyard configuration, started from the my-agents preset: the pull
# requests and issues you and your agents open, one project per
# repository.
# You and your agents edit this file; shipyard applies changes live.
# Every key is optional; keys, defaults and events are in the schema above.
version = 1

# Group each project's items by kind: pull requests, then issues.
[defaults]
group-by = "kind"

# List issues too, not only pull requests, in every project.
[defaults.issues]
show = true

# Projects: one [[projects]] block per repository. Add more at the end.
[[projects]]
name = "hello-world"
repositories = ["octocat/hello-world"]

[[projects]]
name = "Spoon-Knife"
repositories = ["octocat/Spoon-Knife"]
```

## `incoming-contributions`

What other people open on the user's repositories, with their own (and their agents') and bots' items hidden, grouped by repository under subheaders, and a second project of the pull requests waiting on their review in any repository. It notifies when someone else opens a pull request or an issue, and on each new review request.

```toml
#:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json
# shipyard configuration, started from the incoming-contributions preset:
# the pull requests and issues other people open on your repositories,
# bots left out, and the pull requests waiting on your review anywhere.
# You and your agents edit this file; shipyard applies changes live.
# Every key is optional; keys, defaults and events are in the schema above.
version = 1

# Group each project's items by repository, each under a subheader.
[defaults]
group-by = "repository"
subsections = true

# List other people's pull requests: yours (and your agents') and
# bots' are hidden.
[defaults.pull-requests]
authors = { hide = ["me", "bots"] }

# List other people's issues too, hiding the same authors.
[defaults.issues]
show = true
authors = { hide = ["me", "bots"] }

# Notify when someone else opens a pull request or an issue.
[[defaults.notifications]]
event = "pr.opened"
authors = ["others"]

[[defaults.notifications]]
event = "issue.opened"
authors = ["others"]

# Projects: one [[projects]] block each. owned is every repository
# your account owns, including ones you create later.
[[projects]]
name = "Incoming"
repositories = ["owned"]

# The pull requests waiting on your review, or a team's you're in, in
# any repository. anywhere lists only those, so this project shows no
# issues, and it notifies each new request instead.
[[projects]]
name = "Review requests"
repositories = ["anywhere"]
pull-requests = { review-requested = true }
issues = { show = false }
notifications = [
  { event = "pr.review_requested" },
]
```

## `review-queue`

Only the pull requests waiting on the user's review, or a team's they're in, in any repository, grouped by repository under subheaders. Each new request notifies.

```toml
#:schema https://raw.githubusercontent.com/yahyabedirhan/shipyard/main/schema/config.schema.json
# shipyard configuration, started from the review-queue preset: only the
# pull requests waiting on your review, in any repository.
# You and your agents edit this file; shipyard applies changes live.
# Every key is optional; keys, defaults and events are in the schema above.
version = 1

# The pull requests waiting on your review, or a team's you're in, in
# any repository, grouped by repository under subheaders. Each new
# request notifies.
[[projects]]
name = "Review queue"
repositories = ["anywhere"]
pull-requests = { review-requested = true }
group-by = "repository"
subsections = true
notifications = [
  { event = "pr.review_requested" },
]
```
