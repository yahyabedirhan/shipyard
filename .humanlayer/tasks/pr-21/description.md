[Spec #1](https://github.com/yahyabedirhan/shipyard/issues/1) | Phase 1: #2–#12 | Phase 2: #13, #15–#20, #24–#27, #29–#32, #35–#40 | Follow-ups: #33, #42, #44–#52 | [Design](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-core-0.0.x/docs/low-level-design.md) | [Install](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-core-0.0.x/README.md#install) | [Configuration docs](https://github.com/yahyabedirhan/shipyard/blob/build/shipyard-core-0.0.x/docs/configuration.md)

## Why the change

This delivers shipyard 0.0.1: a macOS menu bar app, built over a tested Foundation-only core, that shows the pull requests, issues and workflow runs on your chosen projects, says which need you, notifies on the events you pick, and stays within a share of your GitHub rate limit.

## Special things to note

- **0.0.x connects through `gh` only.** Sign-in without `gh` (the device flow, which needs an OAuth App client ID, plus the Keychain) moved to its own effort, #22, with #23 and #14. The device-flow code stays in the core, switched off. With a `gh` token, Sign out only lasts until Try again or the next launch; that is deferred to #22 too.
- **QA passed:** the maintainer tried the interactive features on the installed build (`7221483`) and closed #44, #45, #51 and #33. #42 (seen once, never reproduced) and #20 were closed without further hand checks, at the maintainer's decision. The checks never walked are listed on #20. Two commits say "closes #45" and "closes #33"; both are already closed.
- **What was checked in the real menu:**
  - **The keys (#45), in the list layout:**
    - Press ↓ as soon as the menu opens, with no click. Do it again after closing and reopening.
    - Hold ↓ through several projects: it should scroll at key-repeat speed, clear of the pinned header.
    - ↑/↓ wrap at both ends.
    - ← goes to the project header, then collapses it; → expands it, then goes to its first item.
    - Return on a header opens its repository; Return opens an item; ⌥Return only marks it seen.
  - **The keys in the tabs layout:** ←/→ switch tabs, and the new tab starts at the top with its first row highlighted. ↑/↓ scroll correctly straight after a switch.
  - **The layout button (#51):** it shows the current layout; a click switches to the next and writes only `[menu] layout` in `config.toml`.
  - **A look, no QA:** your avatar and @handle in the header (a click opens your profile); the refresh button shows the native spinner while refreshing; a missing `config.toml` comes back with commented examples on launch.
  - **Other checks:**
    - The tabs tooltip now reads like the list's: state, then details.
    - A `[rate-limit]` edit shows in the footer at once.
    - From the first pass: install from the zip through the README's `xattr` step, launch at login after a reboot, refresh on wake, offline, and typing in the picker with a real click.

  The hover fix (#44) has already been confirmed in the real menu. #42 (extra clicks to reopen, seen once) is diagnosed but not fixed: the likely causes and the steps to try are on the issue.
- **Choices worth a look:**
  - opening the menu never refreshes (#26);
  - the menu closes after opening an item through the status item's own click, with a guarded private fallback on newer macOS, because SwiftUI can't dismiss a `.window` `MenuBarExtra` (#39);
  - unknown settings warn instead of failing (#38);
  - the layout is a setting, `[menu] layout = "list" | "tabs"` (#35, #36).

  - the keyboard navigation fixes our own SwiftUI list rather than moving to `NSOutlineView`, SwiftUI `List` or a real `NSMenu` (reasons on #45); `NSOutlineView` is the fallback if it doesn't feel native.

  Phase 1's choices still hold: only a first launch or a newly added project, repository or kind is silent; sign-out keeps seen state; running workflow runs never need attention.

## Change outline

The app on a real Mac, build cbd2c86 (`[menu] layout = "list"` on the left, `"tabs"` on the right):

| list | tabs |
|---|---|
| ![List layout, light](https://raw.githubusercontent.com/yahyabedirhan/shipyard/d0edc8a2c44bc26dc47b22ecee55e7df4c296c35/final/list-light.png) | ![Tabs layout, light](https://raw.githubusercontent.com/yahyabedirhan/shipyard/d0edc8a2c44bc26dc47b22ecee55e7df4c296c35/final/tabs-light.png) |
| ![List layout, dark](https://raw.githubusercontent.com/yahyabedirhan/shipyard/d0edc8a2c44bc26dc47b22ecee55e7df4c296c35/final/list-dark.png) | ![Tabs layout, dark](https://raw.githubusercontent.com/yahyabedirhan/shipyard/d0edc8a2c44bc26dc47b22ecee55e7df4c296c35/final/tabs-dark.png) |

The app icon is origami; sailboat, night and sunset are kept as alternates:

![App icons](https://raw.githubusercontent.com/yahyabedirhan/shipyard/d0edc8a2c44bc26dc47b22ecee55e7df4c296c35/final/icons-final.png)

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

The follow-ups put the row highlight, and the keys that move it, under one tested model. The pointer and the keys share it, and each layout draws it as a single shape:

```diff
 ListLayout / TabsLayout
-  per-row hovered + matchedGeometryEffect + a spring per row
+  @State highlight: RowHighlight                  (ShipyardCore, tested)
+    pointerEntered / pointerExited / pointerLeftRows / keep(in:)
+    moveUp / moveDown (wrap) · left / right (header ↔ items, fold) · Return target
+  rowHighlight(_:)                                 one shape at the highlighted row's bounds
+  rowKeys(…)          (UI/RowKeys.swift)           focus when the panel window becomes key; ↑↓←→ Return ⌥Return
+    RowScroll.reveal                               (ShipyardCore) scroll just enough, clear of the pinned header
+  itemRow(…)                                       one row behaviour for both layouts: click, ⌥-click, tooltip, highlight
   ListLayout: a project header is a row: highlightable, ←/→ fold, Return opens its first repository
   TabsLayout: ←/→ switch tabs, scroll to a stable top anchor
```

The last round made the configuration friendlier for users and agents:

```diff
 ConfigStore
+  createIfMissing() on every start and on Refresh      starter header: common settings commented out at their defaults
+  setLayout(_:)                                        the layout button's one targeted edit
 Shipyard
+  publishConfigStatus()     → Application Support/Shipyard/config-status.json   the app's verdict, for agents
+  viewer: name, avatar, profile URL (from the existing /user call) → header account, AvatarCache on disk
 skills/shipyard           reads the verdict after saving; written for users only
 AGENTS.md                 "change my shipyard" means config.toml; no issue numbers in code
```

What lands where:

```text
Sources/ShipyardCore/         configuration, GitHub, items, menu model + words, state, skill installer, Shipyard
Sources/ShipyardApp/          adapters above; UI/Design.swift, Components.swift and RowKeys.swift shared by both layouts
Tests/ShipyardCoreTests/      424 tests; Harness drives Shipyard end to end over recorded GitHub answers
Makefile, Packaging/          make install / release (ad-hoc signed zip) / icon; origami app icon + sailboat, night, sunset alternates
schema/, skills/shipyard/     published schema; the user-facing agent skill, checked key by key in tests
docs/                         low-level design, configuration.md for maintainers, references (incl. end-to-end testing)
README.md                     install, first launch, everyday use, update, uninstall, configuration
.github/workflows/ci.yml      Ubuntu (core) and macOS (everything) jobs
```

🤖 Generated with [Claude Code](https://claude.com/claude-code)
