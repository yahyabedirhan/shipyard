# shipyard in Swift Lab

This folder is the `shipyard` project of [Swift Lab](https://github.com/yahyabedirhan/swift-lab): the app's design pulled out into variants that run on fixture data, and a stress window that reproduces the tabs layout's performance problems. Nothing here is compiled into the app: `Package.swift` names its targets' paths, and this folder is not one of them.

## Sessions

| Session | What it shows |
|---|---|
| `brand` | The logo at every size and the menu bar mark, the palette in light and dark, the type scale, the spacing grid, radii and motion springs. |
| `building-blocks` | Count badges, state symbols with check and attention dots, agent marks, buttons, subheaders and Show more, error, note, empty and loading rows, hover cards. |
| `components` | The tab strip (3, 11 and 30 projects), the tabs layout's row, the list layout's row, the list's project header, and a project's tab. |
| `app` | The whole panel in the tabs layout and in the list layout at a light volume, and the tabs layout at about the maintainer's volume, with nothing measuring it. |
| `perf` | The tabs panel under load beside a meter of what drawing it costs: `V1` to `V3` before the performance fix and `V4` to `V6` after it, at the maintainer's, a heavy and an extreme volume, and the list layout at the heavy volume, before (`list-panel` `V1`) and after (`V2`). See [perf/FINDINGS.md](perf/FINDINGS.md). |

Open one from the Swift Lab app's home window, or:

```sh
swiftlab show perf tabs-panel V1 --project shipyard
```

## The kit

Every variant links `kit/` through a `Kit` symlink in its folder, and one of `versions/` through a `Version` symlink, so the extracted code exists once:

- `kit/Brand/`: the app's `Logo`, `Sailboat`, `LogoBadge` and `SailboatImage`, unchanged.
- `kit/UI/`: the app's views from `Sources/ShipyardApp/UI/` (design tokens, components, row keys, hover help), with three kinds of edits, each marked in the code:
  - `// lab probe`: a counter the perf meter reads (`Probe.hit`). It counts; it changes nothing the view does.
  - `// lab id`: a test identifier (`labID`), so `swiftlab interact` can click a tab.
  - `// lab: internal (private in the app), for the gallery`: a `private` view made internal, so a gallery variant can draw it alone.
- `kit/Model/`: the menu model from `Sources/ShipyardCore/` (items, arrangement, tabs, highlight, panel text), trimmed of what reads `config.toml`, GitHub or Notion; `Stubs.swift` stands in for the types the views only pass through; `Fixtures.swift` makes projects with pull requests, issues, runs, pings and notes at any volume, the same for a seed.
- `kit/App/LabPanel.swift`: the panel's frame (header, layout, footer) as `Panel.swift` draws it once ready, on a mock store whose actions change only the fixture model.
- `kit/Perf/`: the probes, the main-thread meter, and the stress window (`PerfLab`).
- `kit/Gallery/`: sample rows of every kind and state, and the specimen frames the galleries use.
- `versions/before/`: the tabs and list layouts as they shipped at commit `54a4e4f`, before the performance fixes. Frozen: the perf session's `V1` to `V3` and `list-panel` `V1` link it, so the problems stay measurable.
- `versions/after/`: the two layouts as the app has them now, with the same marked edits. The perf session's `V4` to `V6`, `list-panel` `V2` and every design session link it.

The kit is a copy of the app, not a dependency: changing the app changes nothing here. When either layout changes in the app, copy it into `versions/after/` with the marked edits, so the design sessions show the app as it is. To compare another fix, add a folder under `versions/` and perf variants that link it, and keep `versions/before/` as it is.

A variant's own file names must differ from the kit's (`Logo.swift` in a variant clashes with `kit/Brand/Logo.swift`).

## Stress run

`perf/stress.py` drives each perf variant through the same phases in background windows (idle with and without pulsing runs, hovering rows, scrolling, switching tabs, a reload) and prints what each cost, from the meter's log:

```sh
swift-lab/perf/stress.py                     # every perf variant
swift-lab/perf/stress.py tabs-panel/V1       # one
```

It closes the session before each variant: one runner draws every window of a session, so a second window would share its main thread.
