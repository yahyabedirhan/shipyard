# Panel performance

How the panel's tabs and list layouts perform as the app has them now (`versions/after/`), measured in the lab's perf session on generated data. Each variant ran alone in its runner, through `perf/stress.py`.

## Volumes

`Fixtures.swift` makes the same projects for a seed at each volume:

| Volume | Projects | Rows in All | Variant |
|---|---|---|---|
| Maintainer | 11 | ~420 | `tabs-panel` `V4` |
| Heavy | 20 | ~1,500 | `tabs-panel` `V5`, `list-panel` `V2` |
| Extreme | 30 | ~3,400 | `tabs-panel` `V6` |

## Tabs layout

| Phase | Maintainer | Heavy | Extreme |
|---|---|---|---|
| Idle on All, runs pulsing | 2% of the main thread | 9% | 3% |
| Hovering rows: worst stall | 8 ms | 5 ms | 9 ms |
| Scrolling: worst stall | 6 ms | 8 ms | 11 ms |
| Switching to All: average | 103 ms | 132 ms | 154 ms |
| Switching to a project: average | 113 ms | 85 ms | 129 ms |

The lab builds variants in debug, so these switch times are slower than a release build's. A frame at 60 Hz is 16.7 ms, so no hover or scroll stall skips a frame.

## List layout

At the heavy volume, two runs:

| Phase | Result |
|---|---|
| Hovering: late frames | 0 per second |
| Hovering: worst stall | 11 to 14 ms |
| Scrolling: late frames | 0 per second |
| Row bodies run while hovering | 0 per second |

## What keeps it fast

Both layouts follow two rules in `Sources/ShipyardApp/UI/`:

- **Rows are built lazily.** Each tab's rows, and the list's, are a `LazyVStack`, so only the rows in view are made, laid out and tracked. A running workflow run's pulsing icon redraws only those rows.
- **Only the highlight layer reads the highlight.** `HighlightLayer` in `Components.swift` draws the row highlight, and the list layout reads it in a small view around each project header (`HighlightedSectionHeader`). A hover redraws that layer and the rows it touches. The layout's body does not run again, so the All tab is sorted only when the data or the tab changes.

Keep both when either layout changes. Measure late frames as well as the main thread's share: a layout can use little of the main thread and still skip frames.

## What's left

- **The lease banner.** It redraws every second while an agent holds app control. It costs agents' runs, not the maintainer's use.
- **Tab switches over 100 ms** at the heavy and extreme volumes, in the lab's debug build. They are the visible rows being made during the slide.

## Run it yourself

```sh
$LAB_CLI show perf tabs-panel V4 --project shipyard   # the maintainer's volume
lab/perf/stress.py                                    # every phase of every perf variant, as a table
```

In the meter, untick **Running workflow runs** to remove the pulse, and use **Switch tabs ×10** and **Reload**. Every reading is also a JSON line in the runner's temporary folder, `shipyard-lab-perf.jsonl`.
