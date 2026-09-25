[Spec #1](https://github.com/yahyabedirhan/shipyard/issues/1) | Tickets #2–#12 | [Design](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-core-0.0.x/docs/low-level-design.md) | [Mac handoff](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-core-0.0.x/.handoff/2026-09-25-shipyard-macos.md)

## Why the change

Shipyard's rules — configuration, sign-in, fetching, attention, notifications, rate limits and onboarding — now live in a Foundation-only `ShipyardCore` library, tested end to end on Linux, so the macOS app (phase 2, #13–#20) only has to draw it and supply Apple services.

## Special things to note

- **Needs you:** the device flow's OAuth App client ID is a placeholder (`OAuthApp.clientID` in `GitHub/Auth/DeviceFlow.swift`); the flow refuses to start until it's set. `gh` sign-in works without it. The `ShipyardApp` target has never been compiled (Linux) — phase 2 does that first.
- **Choices the docs didn't settle:** the app target is renamed `ShipyardApp` (executable still `Shipyard`) so it doesn't clash with the core's `Shipyard` orchestrator; the core may import `Observation` so `Shipyard` is `@Observable`; only the *first* launch or a newly added project/repository/kind is silent (a PR opened while shipyard was quit is announced next launch); sign-out keeps seen state; running workflow runs never need attention.
- **Hand-built fixtures:** there was no network recording on the VPS, so GraphQL/REST fixtures follow GitHub's documented shapes; two lines in `docs/references/github-repositories.md` are marked "not yet confirmed". Workflow runs are fetched with `created>=` (finished window + 1 h), so a run started earlier than that is missed even while running.

## Change outline

The orchestrator drives one refresh pipeline; everything under it is pure or behind a port.

```text
Shipyard (@MainActor @Observable)       phase: signedOut → connecting → needsProjects → ready
  start / beginDeviceFlow / signOut     TokenProvider: token store → gh (/opt/homebrew, /usr/local, PATH) → device flow
  refresh()  (RefreshGate: one at a time, one queued)
    ConfigStore.lastValid                TOML → Configuration (+ line-numbered errors, warnings)
    GitHubClient.fetch                   1 GraphQL request (PRs, issues) + 1 REST/repo for runs (If-None-Match)
      every call via Shipyard.request    401 → signedOut
    EventDetector(known, snapshot)       pr.* / issue.* / run.* ; first sight silent
    NotificationRules → Notifying port   notified once, recorded apart from seen
    AppStateStore.update                 state.json: seen, known, notified, collapsed
    MenuModel.build                      sections, rows, attention counts, label, rate indicator
    RateBudget.nextDelay → RefreshTimer  stretch to share / back off <20% / pause at 0
  open / markSeen / markAllSeen / toggleCollapsed / openNotification
  suggestedRepositories / checkRepository / addProjects     (project picker)
SkillInstaller                           $SHELL -l -i -c "npx -y skills add yahyabedirhan/shipyard -g -y"
```

What lands where:

```text
Package.swift                 ShipyardCore (+ TOMLDecoder), ShipyardCoreTests, ShipyardApp (macOS only)
Sources/ShipyardCore/
├── Config/                   configuration model, reader, source map, store (append-only)
├── GitHub/                   client, transport, query, runs, repositories, rate budget, auth/
├── Items/                    item + fingerprint, attention, event detector, notification rules
├── Menu/MenuModel.swift      every display rule
├── State/AppStateStore.swift app state (corrupt or newer file → set aside)
├── Skill/SkillInstaller.swift
└── Shipyard.swift, Lifecycle.swift, Ports.swift, RefreshScheduler.swift, Version.swift (0.0.1)
Tests/ShipyardCoreTests/      239 tests; Harness drives Shipyard end to end over StubHTTP + fixtures
schema/config.schema.json     published JSON Schema (#:schema line)
skills/shipyard/SKILL.md      agent skill; its TOML examples are decoded and schema-checked in tests
.github/workflows/ci.yml      swift test on Ubuntu
```

🤖 Generated with [Claude Code](https://claude.com/claude-code)
