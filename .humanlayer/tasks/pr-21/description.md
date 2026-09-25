[Spec #1](https://github.com/yahyabedirhan/shipyard/issues/1) | Phase 1: #2–#12 | Phase 2: #13, #15–#20, #24–#27, #29–#32, #35–#40 | [Design](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-core-0.0.x/docs/low-level-design.md) | [Install](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-core-0.0.x/README.md#install) | [Configuration docs](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-core-0.0.x/docs/configuration.md)

## Why the change

This delivers shipyard 0.0.1: a macOS menu bar app, built over a tested Foundation-only core, that shows the pull requests, issues and workflow runs on your chosen projects, says which need you, notifies on the events you pick, and stays within a share of your GitHub rate limit.

## Special things to note

- **0.0.x connects through `gh` only.** Sign-in without `gh` (the device flow, which needs an OAuth App client ID, plus the Keychain) moved to its own effort, #22, with #23 and #14. The device-flow code stays in the core, switched off. With a `gh` token, Sign out only lasts until Try again or the next launch; that is deferred to #22 too.
- **Still for the maintainer (#20):**
  - install from the zip through the README's `xattr` step;
  - launch at login after a reboot;
  - refresh on wake;
  - offline;
  - typing in the picker with a real click.

  Everything else in the spec's user stories was walked in the real menu on a Mac, including both layouts in light and dark (screenshots on #20). One intermittent issue is open: the menu once needed extra clicks to reopen after opening an item (#42).
- **Choices worth a look:**
  - opening the menu never refreshes (#26);
  - the menu closes after opening an item through the status item's own click, with a guarded private fallback on newer macOS, because SwiftUI can't dismiss a `.window` `MenuBarExtra` (#39);
  - unknown settings warn instead of failing (#38);
  - the layout is a setting, `[menu] layout = "list" | "tabs"` (#35, #36).

  Phase 1's choices still hold: only a first launch or a newly added project, repository or kind is silent; sign-out keeps seen state; running workflow runs never need attention.

## Change outline

Phase 1 put every rule in `ShipyardCore`. Phase 2 adds the app that draws it and supplies the Apple-only services through the core's ports:

```text
ShipyardApp (@main, MenuBarExtra .window, menu-bar-only)
  AppServices                      builds Shipyard with the adapters, owns the panel's actions
    ConfigWatcher                  watches ~/.config/shipyard (debounced, rename-safe) → reloadConfiguration()
    WakeObserver                   wake → refresh()
    Notifier                       UNUserNotificationCenter; asks on the first notification; click → openNotification
    LaunchAtLogin                  SMAppService, follows launch-at-login live
    Workspace                      open in browser / editor, then closeMenu()
  Panel                            header · banners · ready body · footer
    ConnectView                    gh auth login, Copy, Try again           (no usable gh token)
    ProjectPicker, SkillInstallCard                                          (no projects yet)
    [menu] layout = "list"  → ListLayout   one line per item, pinned project headers
                    "tabs"  → TabsLayout   All + a tab per project, grouped by kind
```

The core gained what the menu needed:

```diff
 Shipyard
+  signedOutReason, configError, configWarnings     what the connect screen and banners say
+  rebuild the menu on every configuration change   edits show at once, even while paused or offline
   MenuModel.build(snapshot, …)
+    snapshot may be nil → every project "Not loaded yet"
+    layout, showsRepository (only when a project has several repositories)
+  MenuTabs                                         the tabs, their counts, the fallback to All
+  PanelText                                        every word the menu shows, tested with the model
   ConfigurationReader
+    [menu] layout; unknown settings → warnings with "did you mean"
```

What lands where:

```text
Sources/ShipyardCore/         configuration, GitHub, items, menu model + words, state, skill installer, Shipyard
Sources/ShipyardApp/          adapters above; UI/Design.swift + Components.swift shared by both layouts
Tests/ShipyardCoreTests/      332 tests; Harness drives Shipyard end to end over recorded GitHub answers
Makefile, Packaging/          make install / release (ad-hoc signed zip) / icon; origami app icon + sailboat, night, sunset alternates
schema/, skills/shipyard/     published schema; the user-facing agent skill, checked key by key in tests
docs/                         low-level design, configuration.md for maintainers, references (incl. end-to-end testing)
README.md                     install, first launch, everyday use, update, uninstall, configuration
.github/workflows/ci.yml      Ubuntu (core) and macOS (everything) jobs
```

🤖 Generated with [Claude Code](https://claude.com/claude-code)
