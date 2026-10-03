# Changelog

What changed in each version of shipyard, newest first. 0.0.1 to 0.0.3 are GitHub releases with a download. 0.0.5 to 0.0.7 are plain tags on `main` that record the history between 0.0.3 and 0.1.0: no build was released for them, and the app and the `shipyard` command they build still report 0.0.3. There is no 0.0.4: its plan shipped in 0.0.5.

## Unreleased

- Build: CI runs once per pull request push and shares the SDK module cache: [#157](https://github.com/yahyabedirhan/shipyard/pull/157) "build: run ci once per pull request push and share the sdk module cache".
- The shipyard skill compares pinging from the Mac with pinging from another machine: [#158](https://github.com/yahyabedirhan/shipyard/pull/158) "docs(skill): compare pinging from the mac and from another machine, and start --from with the agent's name".
- Shipyard is licensed under MIT, and the bundled agent logos' notices are in `THIRD-PARTY-NOTICES.md`: [#159](https://github.com/yahyabedirhan/shipyard/pull/159) "docs: license shipyard under mit and give the bundled logos' notices a home".

## 0.0.7 (2026-10-03, tag only)

The fixes from the first QA round of pings, and one ping number per project.

- **Pings read like the rows beside them.** Gray ping icons, the ping's number on its line, the sending agent's real logo and kebab-case name, and failures as a few words on the row ("Pane gone", "No app", and "Offline" or "No machine" for a remote machine) with the whole reason in the hover card. A Herdr ping's click brings forward the `[herdr] terminal`, or else the terminal the ping was sent from. The menu orders its kinds as pull requests, pings, issues, runs: [#148](https://github.com/yahyabedirhan/shipyard/pull/148) "fix: the rough edges pings qa round 1 found (0.0.7)".
- **The Mac numbers pings per project, in the order they arrive.** Every ping in a project, local or remote, gets the next number, like issue numbers, so a smaller number always means earlier; the numbers live in the app's state. `shipyard ping` prints only the id again: [#155](https://github.com/yahyabedirhan/shipyard/pull/155) "feat(menu): the mac numbers pings per project, in the order they arrive (0.0.7)".
- A handoff for the remote pings follow-ups: [#149](https://github.com/yahyabedirhan/shipyard/pull/149) "docs(handoff): remote pings follow-ups from the mac".

## 0.0.6 (2026-10-02, tag only)

Pings from agents on your other machines, through Herdr, and faster builds.

- **Remote pings.** Agents on other machines send `shipyard ping` as on the Mac, and a blocked agent pings by itself through the herdr-shipyard plugin. The Mac reads each machine listed under `[remote] machines` through Herdr's own connection (never SSH), files, notifies and lists its pings, shows a quiet line for a machine it can't reach, and focuses the agent's pane on that machine when you click. The `linux cli` workflow builds static Linux `shipyard` files for each release: [#143](https://github.com/yahyabedirhan/shipyard/pull/143) "feat: remote pings, from agents on my other machines through herdr (0.0.6)".
- **Faster builds.** CI builds once, caches `.build` between runs, and bundles the app only on `main` and tags: [#142](https://github.com/yahyabedirhan/shipyard/pull/142) "ci: build once, cache .build and bundle only on main and tags".

## 0.0.5 (2026-10-02, tag only)

Pings from agents through the `shipyard` command, plus what 0.0.4 planned: the project setup and the menu freeze fix.

- **Pings.** The app bundles a `shipyard` command. `shipyard ping "…"` files a short message under the projects watching the repository it runs in, notifies under the new `ping.sent` event, and on a click opens a link, an app or a Herdr tab. `shipyard ping withdraw` takes one back, and its banner with it. New settings: `[defaults.pings]` `show` and `seen-window`, and `[herdr] terminal`: [#106](https://github.com/yahyabedirhan/shipyard/pull/106) "feat: pings, sent by agents through the shipyard cli (0.0.5)".
- **The menu no longer freezes.** Its measured scroll view stopped looping its layout: [#95](https://github.com/yahyabedirhan/shipyard/pull/95) "fix(panel): stop the menu's measured scroll view looping its layout".
- **The project setup for agents**: [#90](https://github.com/yahyabedirhan/shipyard/pull/90) "chore: audit the repo with set-up-project and keep two memory notes", [#91](https://github.com/yahyabedirhan/shipyard/pull/91) "chore: adopt the skills repo's folder standard for agent records", [#92](https://github.com/yahyabedirhan/shipyard/pull/92) "refactor: rename context.md to glossary.md and update issue-tracker.md" and [#93](https://github.com/yahyabedirhan/shipyard/pull/93) "docs(agents): create an effort label only when it's missing".
- A test audit pruned the tests that didn't earn their keep: [#123](https://github.com/yahyabedirhan/shipyard/pull/123) "test: prune tests that don't earn their keep, with a test audit".

## 0.0.3 (2026-09-26)

A new logo; nothing else changed from 0.0.2. [Release](https://github.com/yahyabedirhan/shipyard/releases/tag/v0.0.3).

- **The khaki green logo.** The app icon and the connect screen's badge are a cream sailboat on khaki green (`#72873A`), in place of 0.0.2's olive khaki: [#85](https://github.com/yahyabedirhan/shipyard/pull/85) "feat(icon): make shipyard's logo khaki green".
- The version bump: [#86](https://github.com/yahyabedirhan/shipyard/pull/86) "build(release): bump shipyard to 0.0.3".

## 0.0.2 (2026-09-26)

Each project chooses whose items it shows and how it arranges them, watches whole groups of repositories, starts from a preset, and signs in to GitHub without the GitHub CLI. Every 0.0.1 configuration file still works. [Release](https://github.com/yahyabedirhan/shipyard/releases/tag/v0.0.2).

- **Filters** by author, state and review request, for every project or one; **closed items for as long as you like** with `closed-window` and `finished-window`, which replace `closed-window-days` and `finished-window-hours`; **repository groups** (`my-org/*`, `owned`, `organizations`, `collaborator`, `anywhere`); **arranging** with `group-by`, `sort-by`, `subsections` and `show-first`; **presets and onboarding**; **Sign in with GitHub** on a redesigned connect screen; the olive khaki logo; and the agent skill installs again with `npx skills add`: [#71](https://github.com/yahyabedirhan/shipyard/pull/71) "feat: build shipyard 0.0.2, filters, repository groups, arrangement, presets and sign-in".
- **A hover card** replaces macOS's native tooltips: [#75](https://github.com/yahyabedirhan/shipyard/pull/75) "feat(panel): replace native tooltips with a hover help card".

## 0.0.1 (2026-09-26)

Shipyard's first release. [Release](https://github.com/yahyabedirhan/shipyard/releases/tag/v0.0.1).

- Every open pull request on the projects you pick, with issues and workflow runs if you turn them on; an attention count with seen marks; notifications for the events you choose; a list or tabs layout; keyboard navigation; at most 10% of your GitHub rate limit; one commented `config.toml` your agents can edit, with a JSON Schema; a guided first launch; and launch at login: [#21](https://github.com/yahyabedirhan/shipyard/pull/21) "feat: build shipyard 0.0.1, the core and the macos app".
