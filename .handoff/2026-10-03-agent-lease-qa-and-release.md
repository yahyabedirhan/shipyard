# Handoff: QA the agent lease, then release 0.2.0, on the Mac

You're a Claude session on the maintainer's Mac. Effort `agent-lease` is merged. Two things are left that need the Mac: the maintainer's QA in the real app, then releasing 0.2.0. The maintainer started this session for that. Treat this handoff as their go-ahead, except where `AGENTS.md` asks for their yes, such as merging.

## Where things are

- **Merged:** pull request #186 "feat: agent-lease, one agent at a time holds app control, and the 0.2.0 bump", merge commit `e1914a5` on `main`. Its description covers the design, the decisions made alone and the surprises; read it first.
- **The version bump is already in `main`**, so it is the Releases section's step 2: `ShipyardVersion.current` is `0.2.0`, the changelog has its `0.2.0 (2026-10-03)` entry, and the README says 0.2.0. `main`'s CI is green after the merge (run 37150978158).
- **Spec:** #176 "The agent lease…" (closed). Tickets #177–#184 are all closed.
- **QA:** #185 "QA: see who holds shipyard (dot, banner, countdown, screenshots)". It's open, assigned to the maintainer, and has numbered steps for the dot and banner (#180), notifications (#182) and Stop/Allow (#181). A comment on it says how to install the build.
- **Filed for triage, not blocking:** #197 "A standalone app quit posts 'using shipyard' without a matching 'done'" and #198 "Overlapping screenshots can leave the app in a forced appearance".
- **This handoff** is on the branch `release/0.2.0`, cut from `main` at `e1914a5`. Check it out in a worktree of your own (the maintainer's worktree tool), or read the file from the branch. Nothing else is on the branch.
- **The session that wrote this** ran on a Linux VPS and can't be reached from the Mac. Decide open questions yourself, and list them in your report.

## What to do

1. **Install and hand QA to the maintainer.**
   - In a checkout of `main` at `e1914a5`, run `make install`. Check that `/Applications/Shipyard.app/Contents/Helpers/shipyard --version` prints `shipyard 0.2.0`.
   - Use the shipyard skill to add `control.started` and `control.ended` to the maintainer's `config.toml`. It lists its own `[[defaults.notifications]]`, which replace the built-in rules, so the lease's notifications don't arrive without them.
   - Follow `AGENTS.md`'s Testing section, which now uses the lease:
     - take it before `make install` with `shipyard control take --wait <seconds>`;
     - take it again on the new app;
     - release it at the end.
   - Take the screenshots QA asks for: the banner with `--with-indicator`, the menu bar icon with and without the dot, light and dark. Use a demo run (`shipyard app open --demo <folder>`, public repositories only), then `shipyard app open`. Commit them under `assets/screenshots/agent-lease/` and add them to #185 (`docs/agents/issue-tracker.md` says how to embed them).
   - Clicking Stop or Allow, hovering, the real menu bar strip and clicking notifications are for the maintainer. Tell them #185 is ready to try.
   - Nothing on the build machine checked the real app. Watch these risks:
     - the dot is drawn into a coloured, non-template menu bar image, which may tint wrongly;
     - `MenuBarWindow.open()` from a notification click on macOS 27;
     - the lease-end timer removing the dot and banner with no request.
2. **When QA finds a bug,** file it as a `bug` ticket under a new effort and fix it before releasing. When the maintainer is happy, or says to release anyway, go on.
3. **Release 0.2.0** by `AGENTS.md`'s Releases section, steps 3–6.
   - Step 2's bump is already merged, so it's done. Still confirm the version with the maintainer at step 1: the commits since `v0.1.0` include `feat`, so it's 0.2.0.
   - Run `make release` on `main` at the bump's merge commit (`e1914a5`).
   - Publish with `gh release create v0.2.0 build/Shipyard-0.2.0-macos.zip --target e1914a5 --title "shipyard 0.2.0" --notes-file .scratch/<notes>`. Write the notes in `v0.1.0`'s shape (`gh release view v0.1.0`), from #186 and the changelog's 0.2.0 entry.
   - Wait for the `linux cli` run and check the Linux assets. If it fails, stop and report, with every machine left as it was.
   - Carry the release to the machines: the Mac's app (`make install` at `v0.2.0`, then `npx skills update shipyard -g`), then each machine in the maintainer's `[remote] machines` through Herdr, as the section says.
   - Report in a comment on #186: the release link, the Linux run, and each machine's checked versions.
4. **Settle** with `/settle-session` once the release is reported. Remove the `release/0.2.0` branch once this handoff is no longer needed; it holds nothing else. The VPS effort worktree is that machine's to clear.

## Suggested skills

- **shipyard**: editing `config.toml`, app control (`shipyard app`, `panel`, `screenshot`, `control take` and `release`; read its "Taking turns" part), and pings.
- **herdr**: reaching the remote machines in the release's machine step.
- **treehouse**: a worktree for this branch or the release.
- **diagnosing-bugs** and **implement**: if QA finds something to fix.
- **settle-session**: at the end.
