# Handoff: resume effort notes-and-notify

Where the effort stands on 2026-10-04, and what to do next, in order. The build is done (the orchestrator's report is PR #206's description); what's left is the maintainer's decisions, the merge and the release.

## Where things are

- **PR #206** "feat: notes from notion in the menu, and agents' notices with shipyard notify": open, CI green, mergeable, not yet approved. Branch `effort/notes-and-notify`.
- **Outside this repository:** yahyabedirhan/herdr-shipyard#2 "feat: hold shipyard notices for the mac's poll" is open and mergeable; it merges before the release. The maintainer's machine setup has its own pull request, tracked privately.
- **Nothing has been merged or released.** The orchestrator's prompt showed "merge it and release", but that was a dimmed Claude Code suggestion, never sent.

## Next, in order

1. **Decide the `[notices]` rename.** The maintainer leans towards renaming the `[notify]` settings tables in `config.toml` and `cli.toml` to `[notices]`, so the entity's name is used everywhere except the command. Confirm with them, then apply it on this branch before merging. The reasoning and the full list of files are in [the comment on PR #206](https://github.com/yahyabedirhan/shipyard/pull/206#issuecomment-5978379521). #204 and #188 quote the table and need the same edit.
2. **Decide on the pushed history.** Commit ab34333 still holds the private machine details that a later commit removed. Rewriting the branch is the maintainer's call (PR #206, "Surprises").
3. **Merge,** with the maintainer's yes: herdr-shipyard#2 first, then #206.
4. **Release 0.3.0** end to end, per AGENTS.md's Releases section, including carrying it to the machines.
5. **Settle the effort** with `/settle-effort`.

The maintainer's own todos (QA #202 and #204, the #188 spike, the private setup tickets, adding `{ event = "agent.notice" }` to the `shipyard` project's notifications) are listed under "Follow-ups" in PR #206's description.

## Decided in this session

- **Three words, three things.** A **notice** is the message, the entity: `Notice`, `ShipyardNotices`, the event `agent.notice`, the plugin's `notices` actions. **Notify** is the act of sending one: `shipyard notify`. A **notification** is the macOS banner a notice may cause. The glossary already says so.
- **"Notification" as the entity's name was considered and turned down.**
  - It already names the banner, which pings cause too.
  - It names the `notifications` rules list, so `agent.notification` would read as a rule about notifications.
  - A notice doesn't always become a notification: it can be refused, dropped as stale, or shown passively without a banner.
- **The `[notices]` rename** is the one naming change left, as in step 1.

## Outside this repository

- **An explainer video of this setup** was made in the maintainer's explainer studio (`yahyabedirhan/explainer-studio`). It stays private, in that studio's ignored `videos/` folder on the Mac, and describes PR #206 at 862fe6f.
  - Its screen shows the `[notify]` tables, so if the rename lands, update those labels in the video too.
  - The maintainer hasn't listened to its narration yet.
- **The studio's own follow-ups** are explainer-studio issues #5 "Keep Kokoro's word timings so captions and beats line up exactly", #6 "A shared captions component" and #7 "A shared folder of sound effects".

## Suggested skills

- `shipyard`: the configuration and the ping commands.
- `to-pr`: rewriting PR #206's description after the rename.
- `settle-effort`: after the merge.
- `herdr`: reaching the orchestrator's session and the remote machines during the release.
