# App icon

`make-icon.swift` draws shipyard's app icon in one of eight variants. Every variant is built on the menu bar's sailboat, and each one has a simpler drawing below 64 pixels so it still reads at 16.

The app's icon is shipyard's logo, `graphite`: the sailboat folded like paper, white on graphite (`#222529` to `#131417`) with a double rim, in the style of the skills repository's logo. Each sail folds along a crease from its head to its foot, its forward face shaded (`#B9BEC4`) and its aft face white. It replaced `khaki-green`, the logo from 0.0.3 to 0.6.0. It's drawn from two files the app compiles too, `Sources/ShipyardApp/Brand/Sailboat.swift` (the figure) and `Brand/Logo.swift` (the squircle, the colours, the folds, the rims and the figure's size), so the icon, the menu bar item and the welcome screens' badge can't drift apart.

| Variant | What it is | Where it lives |
| --- | --- | --- |
| `graphite` | The folded white sailboat on graphite: shipyard's logo. **This is the app's icon.** | `AppIcon.icns` |
| `green-graphite` | The same on graphite with a trace of green (`#252A1E` to `#13160F`), tried before `graphite` and never released. | `alternates/green-graphite.icns`, `alternates/green-graphite.png` |
| `khaki-green` | The sailboat in cream on khaki green (`#72873A`), the logo from 0.0.3 to 0.6.0. | `alternates/khaki-green.icns`, `alternates/khaki-green.png` |
| `olive-khaki` | The sailboat in cream on olive khaki, the logo in 0.0.2. | `alternates/olive-khaki.icns`, `alternates/olive-khaki.png` |
| `origami` | The sailboat folded from paper, on amber, the app's icon until #80. | `alternates/origami.icns`, `alternates/origami.png` |
| `sailboat` | The sailboat on a sea-blue squircle, the app's first icon. | `alternates/sailboat.icns`, `alternates/sailboat.png` |
| `night` | The sailboat under a crescent moon and stars. | `alternates/night.icns`, `alternates/night.png` |
| `sunset` | The sailboat in silhouette against a low sun. | `alternates/sunset.icns`, `alternates/sunset.png` |

The alternates aren't shipped. They're kept so the icon can be switched later, and each `.png` is a 512-point preview.

## Switch the app's icon

```sh
make icon ICON=night      # or graphite, green-graphite, khaki-green, olive-khaki, origami, sailboat, sunset
make bundle               # the bundle copies AppIcon.icns; Info.plist doesn't change
```

`make icon` redraws `AppIcon.icns` from the variant named by `ICON`, which defaults to `graphite`. To make a switch permanent, change the `ICON ?=` default in the `Makefile` and move the old variant into `ICON`'s place in `ALTERNATES`, so `make icon-alternates` builds it instead.

## Regenerate

After changing `make-icon.swift`, run both targets and commit what they write:

```sh
make icon              # AppIcon.icns
make icon-alternates   # alternates/*.icns and alternates/*.png
```

To review every variant at 16, 32, 128 and 512 on light and dark:

```sh
make build/make-icon/make-icon && build/make-icon/make-icon --sheet /tmp/icons.png
```

The minimal sailboat options (#80), kept as the record of how the logo was chosen, draw shipyard's sailboat from `Sources/ShipyardApp/Brand/Sailboat.swift`, the one path the menu bar item and the connect screen's badge draw too. The Makefile compiles `make-icon.swift` with that file, so the script can't run alone with `swift`. The options come in two families (`solid-*`, a white figure on colour, and `white-*`, the figure in colour on white) and aren't app variants yet. To redraw their previews and comparison sheet:

```sh
make icon-exploration
```

The script needs the Command Line Tools only (AppKit and CoreGraphics), and its output is the same on every run.
