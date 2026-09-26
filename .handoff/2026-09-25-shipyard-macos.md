# Handoff: build shipyard 0.0.x, phase 2 (the macOS app)

Phase 1 is done: the orchestrator session of 2026-09-25 (Claude Code on the Linux VPS, Herdr workspace `w6`, tab "Orchestrator", session `1e9df955-5bae-4147-b676-19432c74682b`) built `ShipyardCore` for tickets #2–#12, and opened it as pull request #21 from `build/shipyard-core-0.0.x`. This handoff is for the agent that builds the app layer on a Mac. It extends `.handoff/2026-09-25-shipyard.md`, which still holds for everything below it doesn't change.

## Read first

- **Spec:** issue #1. **Tickets:** #13–#20, labelled `needs-macos`, with GitHub's "blocked by" edges. All their core blockers (#2–#12) are closed.
- **Phase 1 handoff:** `.handoff/2026-09-25-shipyard.md` (phase 2 section, Mac toolchain, ghbar, commits).
- **Pull request #21:** its description lists the choices phase 1 made. Read it before #13.
- **Design:** `docs/low-level-design.md`, kept in step with the code through phase 1. The code is the truth where they differ.
- **Glossary and decisions:** `CONTEXT.md`, `docs/adr/`. **GitHub facts:** `docs/references/`.

## Where to start

- If #21 is merged, branch from `main`. If not, branch from `build/shipyard-core-0.0.x`.
- Build the tickets in the order of the phase 1 handoff's diagram (#13 first, #20 last), verifying with `make install`, `make test` and by running the app.
- **At the end, open your own pull request** for #13–#20 with the **to-pr** skill. Target `main` if #21 is merged; otherwise target `build/shipyard-core-0.0.x` as a stacked pull request, and say in its description that it must be retargeted to `main` after #21 merges.

## What the builder should know

**What the core gives the app.**
- `Shipyard` (in `ShipyardCore`) is `@MainActor @Observable`: the panel observes it directly. The core imports Foundation, FoundationNetworking, Observation and TOMLDecoder only.
- The app target and module are `ShipyardApp` (`Sources/ShipyardApp/`), and the executable product is still `Shipyard`. It was renamed so the module doesn't clash with the core's `Shipyard` class. **It has never been compiled**; the placeholder struct inside is also named `ShipyardApp`, so rename it if the module/type clash bites.
- Ports the app supplies: `TokenStore` (Keychain), `Notifying`, `WallClock`, `URLOpening`, `RefreshTimer` (a default `TaskRefreshTimer` exists). Test doubles live in `Tests/ShipyardCoreTests/Doubles/`.
- App state: pass `~/Library/Application Support/Shipyard/` to `AppStateStore(directory:)`; the core writes `state.json` there.
- Configuration: the app watches the configuration *directory*, debounces, and calls `Shipyard.reloadConfiguration()`. The core has no watcher and no change callback.
- Notifications (#16): put `PostedNotification.itemURL` in the notification's user info and route a click to `Shipyard.openNotification(_:)`.
- Onboarding (#18): `suggestedRepositories()`, `checkRepository(_:)` (accepts `owner/name` or a github.com link) and `addProjects(_:)` on `Shipyard`. `SkillInstaller` is standalone: build it and call `install()` from onboarding and the footer. It has no timeout, so give the UI a cancel or a timeout. `SkillInstaller.command` is the text for the Copy button.
- The menu model already carries the attention counts, the menu bar label (`menuBarLabel`, text `nil` at 0), the rate indicator with its level, the refresh-delay reason, `canRefreshNow` (⌘R is refused only while paused), error rows and collapsed state. The colours are the app's: a closed pull request is red and a closed issue is purple (#17).

**Needs the user.**
- **OAuth App client ID (#14):** `OAuthApp.clientID` in `Sources/ShipyardCore/GitHub/Auth/DeviceFlow.swift` is `"REPLACE_WITH_OAUTH_APP_CLIENT_ID"`, and the device flow refuses to start (`clientIDMissing`) until it's set. The user registers an OAuth App under their GitHub account with device flow enabled and gives you the ID. The `gh` path works without it.

**Check on the Mac, because the VPS couldn't.**
- Compile `ShipyardApp` for the first time.
- The GraphQL and REST fixtures were hand-built. Compare one real response (for example with `gh api graphql`) against `Tests/ShipyardCoreTests/Fixtures/` and fix any shape drift.
- `docs/references/github-repositories.md` has two lines marked "not yet confirmed" (403 under SAML SSO, 301 on a rename). Confirm them against GitHub's docs or remove them.
- The spec wants a macOS CI job that builds everything and runs the tests. Only the Ubuntu job exists (`.github/workflows/ci.yml`).
- The `#:schema` line points at the schema on `main`, so `taplo check` through it only resolves once #21 is merged.

**Behaviours phase 1 chose.** They're in #21's description too; keep them unless the user says otherwise.
- Only the first launch, or a newly added project, repository or item kind, is silent. A pull request opened while shipyard was quit is announced at the next launch.
- Sign-out keeps seen state.
- Running workflow runs never need attention. Cancelled, skipped and stale runs aren't listed.
- Runs are fetched with `created>=` the finished window plus one hour, so a run that started earlier is missed even while it's still running.
- Review requests match the viewer as a user, not through a team.

**Build budget.** Nothing in phase 2 is limited the way the 4 GB VPS was, but keep phase 1's habit: validate at the end of a ticket, not after every change.

## Suggested skills

- `orchestrate-with-handoff` (given this file) to run #13–#20.
- `implement` and `tdd` per ticket; `code-review` before delivery; `to-pr` for the pull request.
