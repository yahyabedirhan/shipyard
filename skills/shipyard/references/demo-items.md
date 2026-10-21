# Demo items

A demo run (`shipyard app open --demo <folder>`, see Demo runs in [SKILL.md](../SKILL.md)) reads GitHub as the signed-in user.
Put a `demo-items.json` in the demo folder, beside its `shipyard/` folder, and the run lists the file's items instead: made-up pull requests, issues, workflow runs and notes, under a made-up account.
It then sends nothing to GitHub or Notion, reads no token and never runs `gh`, so a screenshot shows only what the file says.
Without the file, the run reads GitHub as before.

## The file

```json
{
  "account": { "login": "mira-dev", "name": "Mira", "avatar": "mira-dev.png" },
  "repositories": {
    "acme/rocket": {
      "pullRequests": [
        { "number": 12, "title": "feat: count down from ten", "author": "mira-dev", "state": "open",
          "checks": "failed", "branch": "feat/countdown", "age": "2h", "updated": "15m" },
        { "number": 11, "title": "docs: explain the launch window", "author": "teo-builds", "state": "open",
          "checks": "passed", "review": "review-required", "reviewRequested": true, "age": "50m" }
      ],
      "issues": [
        { "number": 9, "title": "The countdown skips three", "author": "noor-codes", "state": "open", "comments": 2, "age": "1d" }
      ],
      "runs": [
        { "workflow": "ci", "number": 40, "branch": "feat/countdown", "state": "running", "actor": "mira-dev", "age": "3m" }
      ]
    }
  },
  "notes": {
    "rocket": [
      { "number": "RKT-4", "title": "Which sound says lift-off", "labels": ["design"], "age": "5h" }
    ]
  }
}
```

- **`account`**: the account the panel's header shows.
  `login` is required; `name` shows in its hover text.
  `avatar` is an image file, relative to the demo folder; without it, the header shows the login alone.
  Items whose author is this login count as yours (`me` in author filters and notification rules).
- **`repositories`**: each repository by `owner/name`, as the demo's `config.toml` names it.
  A project lists the items of the repositories it watches, filtered as its settings say (kinds, states, windows, authors).
  A login ending in `[bot]`, such as `dependabot[bot]`, is a bot.
- **`notes`**: each project's notes, by the project's `title` (its slug when it has none), as Notion keys them.
  `number` is `14` or, with the project's prefix, `"SHIP-14"`.

Every age is how long ago, as a whole number and a unit: `m`, `h`, `d` or `w` (`"25m"`, `"3h"`, `"2d"`).
They count back from when the demo launched, so the file never goes stale.
`age` is when the item was opened (a run: started); `updated` is its latest change and defaults to `age`; `closed` is when a merged or closed item closed and defaults to `updated`.
Shipyard sorts by `updated` unless `sort-by` says otherwise.

## Keys

| Item | Required | Optional |
|---|---|---|
| pull request | `number`, `title`, `author`, `state` (`open`, `draft`, `merged`, `closed`), `age` | `checks` (`none`, `pending`, `passed`, `failed`), `review` (`approved`, `changes-requested`, `review-required`), `reviewRequested` (`true`: it waits on your review), `branch`, `base`, `additions`, `deletions`, `files`, `comments`, `reviews`, `updated`, `closed` |
| issue | `number`, `title`, `author`, `state` (`open`, `closed`), `age` | `comments`, `updated`, `closed` |
| workflow run | `workflow` (the row's name), `number`, `branch`, `state` (`running`, `succeeded`, `failed`), `actor`, `age` | `title` (its commit or pull request), `event` (`push`, `pull_request`…), `updated` (when it finished) |
| note | `title`, `age` | `number`, `labels` |

A repository may also set `defaultBranch` (`main` when unset).
With the default `branches = "default-and-pull-requests"`, a run lists only on that branch or on an open pull request's `branch`.

- **What needs attention follows the items.** Failed checks, a failed run and `reviewRequested` mark rows as they would with GitHub's items.
- **A file that doesn't read lists nothing.** Every refresh fails with a banner that names the file, where in it, and why, such as an age written `"soon"`. The run never falls back to GitHub.
- **Edit the file, then relaunch the demo** with `shipyard app open --demo <folder>`: the run reads it once, at launch.
- **Clicking opens nothing real.** A row opens its item's address on GitHub, which doesn't exist for a made-up number, and the new-note icon can't start a note in a demo.
