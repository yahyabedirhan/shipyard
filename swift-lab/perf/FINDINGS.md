# Tabs layout performance: findings

The tabs layout slows down as the panel holds more projects and items, worst in the All tab. This page records what was measured in the real app and in the lab, and what causes each slowdown. Nothing here is fixed yet: the `perf` session keeps the layout as it ships at commit `54a4e4f`, so each problem can be seen and measured before and after a fix.

## In the real app

Measured on the maintainer's Mac with shipyard 0.6.0 in the tabs layout: 11 projects, the app's state knowing about 1,200 items. The main thread was sampled with `sample` (one stack every millisecond or so) while `shipyard panel` opened the panel and switched tabs.

Every `shipyard panel` command takes app control's lease for a minute, and the lease banner it brings costs the panel a lot (cause 1). So the first table measures the panel while an agent drives it. The second measures a release build on the same configuration whose panel opened itself, as a click opens it, with no command and no lease.

| Opened through `shipyard panel` (lease held) | Main thread busy |
|---|---|
| Panel closed | 0% |
| Panel open on All, untouched | 80–97% |
| Panel open on a project's tab, untouched | 87% |

| Opened as a click opens it (no lease) | Main thread busy |
|---|---|
| Panel open on All, untouched, two runs | 0% and 1% |

- 30 tab switches through `shipyard panel tab` took 12.6 s: about 420 ms each, the command's round trip and the lease banner included. The lab's 411 ms, with no lease, is the cleaner number.
- With the panel open and untouched, the main thread re-renders the window on every display frame: `NSDisplayCycleFlush` → `NSHostingView.layout()` → `ViewGraphRootValueUpdater.render` → `ViewGraph.beginNextUpdate(at:)`, with no shipyard code on the stack. Instruments' Animation Hitches data agrees: 458 frame updates in 4 s (about one per display refresh), 36 of them hitches. No body runs, so SwiftUI is advancing something time-driven (an animation that doesn't settle, or a timeline) rather than reacting to new data.
- While switching tabs, shipyard's own frames on the main thread were `TabsLayout.body`, `MenuModel.tabContent(for:)`, `Arrangement.groups` sorting, copies of `ItemRow`, and `RowBoundsKey.reduce`.

## In the lab

`perf/stress.py` drove each perf variant alone in its runner. Busy is the main thread's share of the CPU; a stall is how late a block posted to the main thread every 8 ms ran; a late frame is a stall over 16.7 ms. Run on an M1 Mac.

| Phase | Tabs, maintainer (~420 rows in All) | Tabs, heavy (~1,500) | Tabs, extreme (~3,400) | List, heavy |
|---|---|---|---|---|
| Idle on All, runs pulsing | 97% busy, 79 late frames/s | 100%, 109/s | 100%, 131/s | 8%, 10/s |
| Idle on All, no running runs | 18%, 18/s | 28%, 35/s | 32%, 181/s | 13%, 3/s |
| Hovering rows | 91%, worst stall 267 ms | 96%, 1,275 ms | 99%, 2,489 ms | 30%, 24 ms |
| Scrolling | 75%, 233 ms | 82%, 582 ms | 91%, 2,249 ms | 20%, 22 ms |
| Switching to All | 411 ms per switch, worst 648 ms | 1.8 s, worst 3.3 s | 7.8 s, worst 10.3 s | (no tabs) |
| Switching to a project | 363 ms, worst 497 ms | 1.8 s, worst 2.8 s | 9.1 s, worst 9.9 s | (no tabs) |

The lab's maintainer volume matches the real app: about 97% busy while idle, and about 400 ms per tab switch. The list layout holds the heavy volume with no trouble, which puts the problem in the tabs layout's own structure, not in the data.

## Causes

1. **While an agent holds app control's lease, its banner keeps the panel redrawing.** Each `shipyard` control command takes the lease for a minute, and the panel shows its banner (`Panel.leaseBanner`): a `TimelineView` ticking every second and a countdown that animates on each tick. With it, the open panel stays 60–90% busy while untouched. Without it, the same panel idles at 0–1%. This was found in a diagnostic build on branch `diag/idle-redraw`, never merged: the panel's parts can be switched off one at a time, and only leaving out the banners stopped it. A screenshot never shows the banner, because captures leave the lease's banners out. It costs only while agents drive the app, but it slows their runs and inflated every real-app number above that was taken through `shipyard panel`. The lab has no app control, so it has no lease banner either.
2. **Running workflow runs re-render the whole list on every frame.** `StateSymbol` gives a running run's icon `.symbolEffect(.pulse, options: .repeating, isActive: row.state == .running)` (`Sources/ShipyardApp/UI/Components.swift:176`). While any running run is in the tab, SwiftUI updates and lays out the hosting view every display frame, and the work grows with the view tree. In the lab, finishing every run takes idle use on All from 97% to about 10%. It shows whenever a run is running, with no agent involved.
3. **The tabs list is eager.** `TabsLayout.list` puts `TabList` in a plain `VStack` inside `MeasuredScrollView`, so every row of the tab is made, laid out and tracked at once, the hundreds below the fold included. The list layout uses a `LazyVStack` (`ListLayout.swift:34`) and stays fast at the same volume. The cost shows most when the tab changes: `.id(tab)` with the slide transition builds the incoming tab's rows from nothing, so switching to All costs 0.4 s at the maintainer's volume and 1.8 s at the heavy one.
4. **The hover highlight lives at the top of the layout.** `TabsLayout` owns `@State highlight`, and every row's `itemRow`/`highlightable` binds to it. Each pointer enter or exit changes it, which evaluates `TabsLayout.body` again: it recomputes the tab's content and hands `TabList` a new binding, so every row's `ItemRow` body runs again, recomputing its hover card's text (`PanelText.rowCard`). The meter counts about 1,400 row bodies a second while the pointer moves over rows, and none while it rests.
5. **The All tab is rebuilt from scratch on each body evaluation.** `MenuModel.tabContent(for: .all)` (`MenuTabs.swift:75`) flattens every project's rows, removes duplicates and runs `Arrangement.groups`, sorting copies of `MenuRow`, every time it's called. In a release build it takes 8.8 ms at ~420 rows, 30 ms at 1,600 and 71 ms at 3,600. `TabsLayout.body` calls it on every evaluation (cause 4 makes that every hover), as do ← and → (`switchTab`), `MenuModel.subsection` and `MenuModel.foldsToKeep`.
6. **Every row reports its geometry and bounds.** Each row's `Highlightable` has an `onGeometryChange` in the list's coordinate space, which fires for every row on every scroll step, and an `anchorPreference` that `RowBoundsKey.reduce` merges into one dictionary of all rows on each layout pass. With the eager list (cause 3) that is every row in the tab, so scrolling costs 75% of the main thread at the maintainer's volume.

One more cost showed up only while measuring, and only affects agents. While an agent holds the control lease, each `shipyard` control command runs `ControlServer.leaseChanged` → `LeaseIndicator.lease.setter` on the main thread: about 3 s of 12 s of main-thread samples during a run of 30 tab switches.

## Seeing it in the lab

- `perf` › `tabs-panel` › `V1`: the panel at the maintainer's volume, the meter red while idle. Untick **Running workflow runs** and it turns green; hover or scroll the rows and it turns red again.
- **Also host it in a menu-bar-style panel** opens a second copy of the panel in a self-sizing window, behind other windows. Self-sizing was one of the idle-loop suspects; it ruled itself out.
- **Switch tabs ×10** times the switches; **Reload** times a refresh that brings back the same rows.
- `V2` and `V3` are the same panel at the heavy and extreme volumes; the volume menu switches any of them.
- `list-panel` › `V1` is the list layout at the heavy volume: the same data, drawn lazily.
- Every meter reading is also a JSON line in the runner's temporary folder (`shipyard-lab-perf.jsonl`), which `stress.py` reads.
