# Tabs layout performance: a case study

The tabs layout became slow as the maintainer's projects grew, worst in the All tab. This page is the whole investigation: how the slowness was reproduced, measured, isolated and fixed, with the numbers before and after, and the wrong turns on the way. It follows the two modes of the `/swift-performance` skill: diagnosis mode to find the causes, then build mode for the fix. Read it as a worked example when another macOS app is slow.

## Result

At the maintainer's volume (11 projects, about 420 rows in All), in the lab, on the same data before and after:

| | Before | After |
|---|---|---|
| Idle on All, a workflow run running | 98% of the main thread | 2% |
| Hovering over rows: worst stall | 281 ms | 8 ms |
| Scrolling: worst stall | 232 ms | 6 ms |
| Switching to All: average | 428 ms | 103 ms |

At ten times the volume, a switch to All went from 9.9 s to 154 ms, and hovering from 3.3 s stalls to 9 ms. The fix is two small changes in `TabsLayout.swift`. The maintainer then used the installed build on their own projects, and found it fast. That made a smaller problem in the list layout noticeable, and the same fix removed it (see [The list layout](#the-list-layout)).

## 1. Symptom

The maintainer reported a slow tabs layout, worst in the All tab, with 11 projects. The All tab merges every project's rows, so it is the largest view: about 420 rows that day, from some 1,200 items the app knew about.

## 2. Reproduction

The app's views and model were copied into a Swift Lab project, `swift-lab/`, to run on generated data with no GitHub, no configuration file and no risk to the maintainer's app. `swift-lab/README.md` describes the copy (the kit).

- **Volumes.** `Fixtures.swift` makes projects with pull requests, issues, workflow runs, pings and notes, the same for a seed, at four volumes: light, the maintainer's (~420 rows in All), heavy (~1,500) and extreme (~3,400).
- **A meter beside the panel.** The perf session's window shows the panel and, next to it, the main thread's CPU share, its worst stall and late frames, and counters of how often each body runs. The counters are lines marked `// lab probe` in the copied views.
- **A script that drives it.** `perf/stress.py` runs every variant through the same phases with `swiftlab interact`: idle with and without running workflow runs, hovering rows, scrolling, ten tab switches, and a reload.

## 3. Measurement

In the lab at the maintainer's volume, the replica was as slow as the app: 97% of the main thread with the panel idle, and about 400 ms per tab switch. The real app, sampled with `sample` while `shipyard panel tab` switched tabs, took about 420 ms per switch. Its main thread showed `TabsLayout.body`, `MenuModel.tabContent(for:)`, `Arrangement.groups` sorting rows, and `RowBoundsKey.reduce`.

The full table before the fix, each variant alone in its runner:

| Phase | Maintainer (~420 rows) | Heavy (~1,500) | Extreme (~3,400) | List layout, heavy |
|---|---|---|---|---|
| Idle on All, runs pulsing | 98% busy | 99% | 100% | 5% |
| Hovering rows | 90%, worst stall 281 ms | 94%, 1,529 ms | 89%, 3,318 ms | 23%, 28 ms |
| Scrolling | 56%, 232 ms | 81%, 802 ms | 86%, 849 ms | 18%, 27 ms |
| Switching to All | 428 ms average, 520 ms worst | 2,853 ms, 4,711 ms | 9,882 ms, 11,567 ms | (no tabs) |
| Switching to a project | 330 ms, 579 ms | 2,679 ms, 4,248 ms | 7,837 ms, 11,103 ms | (no tabs) |

The list layout is the fast comparison case: the same data at the heavy volume costs it almost nothing. So the problem is in how the tabs layout is built, not in the data.

## 4. Isolation

- **The running-runs box.** Unticking **Running workflow runs** in the meter took the idle panel from 97% to about 10%. A pulsing icon was redrawing the whole list.
- **The counters.** Moving the pointer over rows ran about 1,400 row bodies a second, and `TabsLayout.body` with `tabContent(for:)` on each move. Resting, they ran none.
- **The list layout.** It differs from the tabs layout in one structural way: a `LazyVStack` in place of a `VStack`.

## 5. Root causes

Each cause breaks one rule of `/swift-performance`'s build mode.

1. **Every row of a tab was built at once** (work bounding). `TabList` was a plain `VStack`, so a tab made, laid out and tracked all of its rows, the hundreds out of view too. A tab switch built the incoming tab's rows from nothing, because `.id(tab)` gives each tab's list its own identity for the slide.
2. **A repeating pulse redrew all of them every frame** (work bounding). A running workflow run's icon pulses (`.symbolEffect(.pulse, options: .repeating)`). The pulse keeps the window rendering every frame, and with every row built, each frame costs the whole list.
3. **The hover highlight was read at the top of the layout** (reuse and invalidation). `TabsLayout` read its highlight state in its own body. Each row the pointer crossed changed it, so the layout's body ran again, and so did everything that body computes.
4. **The All tab was sorted on every body run** (reuse and invalidation). `tabContent(for: .all)` merges and sorts every project's rows: 8.8 ms at ~420 rows in a release build, 71 ms at 3,600. Cause 3 made that every hover.
5. **Every row reported its position on every scroll step** (reuse and invalidation). Each row reads its frame in the list's visible area, which moves when the list scrolls. Cause 1 made that every row in the tab.

## 6. The fix

Build mode, run on the causes, gave two changes, both in `Sources/ShipyardApp/UI/Layouts/TabsLayout.swift`:

```diff
 TabsLayout.body
   let content = model.tabContent(for: tab)
   MeasuredScrollView
-    ZStack { TabList … }.rowHighlight(highlight, in: tab)     // body reads highlight: every hover re-runs it
+    HighlightLayer(highlight: $highlight, list: tab) {        // only this layer reads highlight
+      ZStack { TabList … }
+    }

 TabList.body
-  VStack(alignment: .leading, spacing: 0) {                   // builds every row
+  LazyVStack(alignment: .leading, spacing: 0) {               // builds the rows in view
```

- **Rows built lazily** removes cause 1, and bounds causes 2 and 5 to the rows in view.
- **The highlight in its own layer** removes cause 3: a hover redraws that layer and the visible rows, and the layout's body no longer runs. That removes cause 4 on hover too: the All tab is sorted when the data or the tab changes, not on each pointer move.
- **A third change was tried and reverted.** Caching the All tab's content per model measured no gain: switching to a project, which sorts nothing, cost as much as switching to All. A tab switch's remaining cost is making the visible rows during the slide.
- **The pulse stays.** With only the visible rows built, a running run costs the idle panel 2 to 9% instead of 98%.

## 7. Verification

The same stress run on the fixed layout (`versions/after`), each variant alone in its runner:

| Phase | Maintainer: before → after | Heavy: before → after | Extreme: before → after |
|---|---|---|---|
| Idle on All, runs pulsing | 98% → 2% | 99% → 9% | 100% → 3% |
| Hovering rows: worst stall | 281 → 8 ms | 1,529 → 5 ms | 3,318 → 9 ms |
| Scrolling: worst stall | 232 → 6 ms | 802 → 8 ms | 849 → 11 ms |
| Switching to All: average | 428 → 103 ms | 2,853 → 132 ms | 9,882 → 154 ms |
| Switching to a project: average | 330 → 113 ms | 2,679 → 85 ms | 7,837 → 129 ms |

The lab builds variants in debug, so these switch times are slower than a release build's. The 1,232 tests pass.

On the maintainer's own configuration, in a release build that switched tabs itself, with no lease, the old layout took about 350 ms per switch to All. A clean run of the new one couldn't be taken while the maintainer used the Mac (see the wrong turns). Instead the maintainer installed the fixed build and used it on their projects, and found it fast.

## The list layout

The maintainer tried the fixed build and found the tabs layout smooth. The list layout then felt "like a game with its graphics turned down", though it had never been slow.

- **Measurement.** The list layout builds its rows lazily already, so it was never slow at any volume. But at the heavy volume, hovering ran 400 to 460 row bodies a second, with stalls of 24 to 27 ms and 8 to 11 late frames a second. A 27 ms stall skips about three frames at 120 Hz. The eye reads that as a lower frame rate, next to a tabs layout that now skips none.
- **Root cause.** Cause 3 again (reuse and invalidation). `ListLayout` read its highlight state in its own body: in each project header's `isHighlighted`, and in `.rowHighlight(highlight)`. Each row the pointer crossed ran the layout's body again, with every header and row in view.
- **The fix.** `HighlightLayer` moved to `Components.swift`, and both layouts use it. The list layout also reads the highlight in a small view around each project header (`HighlightedSectionHeader`), so a hover redraws the highlight and the two headers it touches.
- **Verification.** Two runs each, at the heavy volume (`list-panel` `V1` before, `V2` after):

| List layout, heavy | Before | After |
|---|---|---|
| Hovering: late frames | 8 to 11 per second | 0 |
| Hovering: worst stall | 24 to 27 ms | 11 to 14 ms |
| Scrolling: late frames | 7 per second | 0 |
| Row bodies run while hovering | 400 to 460 per second | 0 |

The lesson: after a big fix, users notice smaller costs they used to accept. Measure late frames, not only the main thread's share. The list layout used less than 30% of the main thread, and still skipped frames.

## Wrong turns

These cost time, and each one is now a rule in `/swift-performance`.

- **The measuring tool caused the cost.** Each `shipyard panel` command takes app control's lease for a minute, and the panel shows the lease's banner, a countdown that redraws every second. Opened that way, the real panel looked 80–97% busy while idle. Opened as a click opens it, it was 0–1%. A diagnostic build that switches parts of the panel off one at a time found the banner (branch `diag/idle-redraw`, never merged). Screenshots leave the banner out, so it never showed in one.
- **One process, several windows.** All of a session's windows run in one Swift Lab runner, so a pulsing window loaded the main thread for the window being measured. `stress.py` now closes the session before each variant.
- **The state wasn't what it seemed.** Some samples were taken after the panel had quietly closed, and some test copies showed an empty panel after GitHub returned an error. Each run now checks that the panel is open and loaded.
- **Test copies on the maintainer's screen.** Release copies with their own data ran beside the installed app, and their panels closed whenever the maintainer clicked elsewhere. Their menu bar icons also confused. Run such copies when the screen is free, or let the maintainer try the installed build.
- **The meter needed macOS 15.** The skill's `MainThreadMeter.swift` used `Mutex`, which shipyard's macOS 14 target can't use. `OSAllocatedUnfairLock` works from macOS 13.

## What's left

- **The lease banner.** It still redraws every second while an agent holds app control. It costs agents' runs, not the maintainer's use, and it is a separate change.
- **Tab switches over 100 ms** at the heavy and extreme volumes, in the lab's debug build. They are the visible rows being made during the slide.

## Run it yourself

```sh
swiftlab show perf tabs-panel V1 --project shipyard   # before, maintainer volume
swiftlab show perf tabs-panel V4 --project shipyard   # after, the same data
swift-lab/perf/stress.py                              # every phase, before and after, as a table
```

`V1` to `V3` and `list-panel` `V1` link `versions/before/`, the layouts as they shipped at `54a4e4f`. `V4` to `V6` and `list-panel` `V2` link `versions/after/`, the layouts as the app has them now. Untick **Running workflow runs** to remove the pulse, and use **Switch tabs ×10** and **Reload** in the meter. Every reading is also a JSON line in the runner's temporary folder, `shipyard-lab-perf.jsonl`.
