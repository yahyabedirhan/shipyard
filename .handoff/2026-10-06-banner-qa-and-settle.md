# Handoff: finish the dismissable-banners QA and settle the effort

The maintainer closed their laptop in the middle of QA. Everything is pushed; this file says what remains.

## Where things stand

- Effort `dismissable-banners`: [Spec #219](https://github.com/yahyabedirhan/shipyard/issues/219). Its tickets #220, #221 and #224 are closed, and its PR #226 is merged into `main` (`a6cb571`).
- QA: [#225 QA: Dismissable panel banners](https://github.com/yahyabedirhan/shipyard/issues/225), open and assigned to the maintainer.
- The QA found [Bug #227: A banner's dismiss button does not hide the banner](https://github.com/yahyabedirhan/shipyard/issues/227). Its fix is [PR #228](https://github.com/yahyabedirhan/shipyard/pull/228), still open, on branch `fix/banner-dismiss-hides` in the worktree `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/2/shipyard` (treehouse holder `banner-dismiss-fix`, lease id `9a5444f0ebc92485e97c66947361f362`). The PR also adds `[banners] snooze`, at the maintainer's request, so the QA can use a 10-second snooze.
- The maintainer clicked ✕ on the PR's earlier build (the first commit), and the banner hid. They have not yet seen the 10-second snooze bring a banner back.
- The Mac runs the PR #228 build (`make install` from that worktree at `2f5f703`).
- Separately, [PR #223](https://github.com/yahyabedirhan/shipyard/pull/223) fixed GitHub's `RESOURCE_LIMITS_EXCEEDED` emptying every project. It is merged and needs nothing more.

## Temporary lines in the maintainer's `config.toml`

Both exist for the QA only. Remove both once the QA is done, then check `config-status.json` says `"accepted": true` with no warnings (the shipyard skill's "Checking an edit"):

- `qa-test-banner = true` under `refresh-interval-seconds`: an unknown key that makes the gray config-warnings banner to dismiss.
- The `[banners]` table with `snooze = "10s"` at the end of the tables.

Keep `refresh-interval-seconds = 60` and `[rate-limit] max-share-percent = 12`: the maintainer chose both.

## Next steps, in order

1. Ask the maintainer to click ✕ on the config-warnings banner and say whether it comes back after about 10 seconds.
2. When they confirm, merge PR #228 with a merge commit (`gh pr merge 228 --merge --match-head-commit <head>`). The maintainer already said they'll approve it once that check passes; still ask for their "merge".
3. Remove the two temporary lines from `config.toml`, then `make install` from `main` in the main checkout, holding the app lease the way AGENTS.md's Testing section says.
4. Have the maintainer finish #225 (the lease banner's ✕ and the menu bar dot; Allow and ✕ on the "You took shipyard back" line; VoiceOver). Skip its step 10: with `max-share-percent = 12` no stretch happens, and tests cover it.
5. When the QA passes, run the settle-effort skill: close #225 and #219, and free the worktrees below.

## Worktrees and leftovers for settle-effort

- `/Users/yahyabedirhanpak/.treehouse/shipyard-1e47e3/1/shipyard` (`feat/dismissable-banners`, merged; treehouse holder `dismissable-banners`, lease id `e2d6989657634e0eb57e2e3134d63325`). Kept because the maintainer wants cleanup to wait for their QA. Its Herdr workspace is already closed.
- Delegate worktrees under the main checkout's `.claude/worktrees/`. Their commits were rebased before #226 merged, so only the third merge proof (the merged PR's head) can free them:
  - `agent-a3a62196fcf39e28e` (`feat/no-stretch-banner`)
  - `agent-a44efede12dcf2eca`
  - `agent-a8e8e1b5318e80f2c` (`feat/dismiss-every-banner`)
  - `agent-ac77793152fe683f0`, which has 6 uncommitted changes. Look at them before freeing it.
- `~/shipyard-demo-banners`: the orchestrator's demo folder.
- `.scratch/empty-panel/` in the main checkout: captures from the #223 diagnosis, safe to delete.

## Suggested skills

- `shipyard`: the config edits, app control and the lease.
- `settle-effort`: once the QA passes.
- `treehouse`: freeing the leased worktrees.
