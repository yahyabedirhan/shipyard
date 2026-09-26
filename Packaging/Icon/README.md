# App icon

`make-icon.swift` draws shipyard's app icon in one of four variants. Every variant is built on the menu bar's sailboat, and each one has a simpler drawing below 64 pixels so it still reads at 16.

| Variant | What it is | Where it lives |
| --- | --- | --- |
| `origami` | The sailboat folded from paper, on amber. **This is the app's icon.** | `AppIcon.icns` |
| `sailboat` | The sailboat on a sea-blue squircle, the app's first icon. | `alternates/sailboat.icns`, `alternates/sailboat.png` |
| `night` | The sailboat under a crescent moon and stars. | `alternates/night.icns`, `alternates/night.png` |
| `sunset` | The sailboat in silhouette against a low sun. | `alternates/sunset.icns`, `alternates/sunset.png` |

The alternates aren't shipped. They're kept so the icon can be switched later, and each `.png` is a 512-point preview.

## Switch the app's icon

```sh
make icon ICON=night      # or sailboat, sunset, origami
make bundle               # the bundle copies AppIcon.icns; Info.plist doesn't change
```

`make icon` redraws `AppIcon.icns` from the variant named by `ICON`, which defaults to `origami`. To make a switch permanent, change the `ICON ?=` default in the `Makefile` and move the old variant into `ICON`'s place in `ALTERNATES`, so `make icon-alternates` builds it instead.

## Regenerate

After changing `make-icon.swift`, run both targets and commit what they write:

```sh
make icon              # AppIcon.icns
make icon-alternates   # alternates/*.icns and alternates/*.png
```

To review every variant at 16, 32, 128 and 512 on light and dark:

```sh
swift Packaging/Icon/make-icon.swift --sheet /tmp/icons.png
```

The script needs the Command Line Tools only (AppKit and CoreGraphics), and its output is the same on every run.
