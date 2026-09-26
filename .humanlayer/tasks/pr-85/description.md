[#80 Explore app icons from the menu bar's minimal sailboat](https://github.com/yahyabedirhan/shipyard/issues/80)

## Why the change

A user said the olive khaki logo looked like a muddy green, so this PR changes it to a clearer khaki green (`#72873A`) everywhere the logo appears: the app icon, the welcome screen's badge and the README.

| Before: `olive-khaki` | After: `khaki-green` |
| --- | --- |
| <img src="https://raw.githubusercontent.com/yahyabedirhan/shipyard/aaf87593a297cd7113983769aa9b11fab97d9f86/Packaging/Icon/alternates/olive-khaki.png" width="160" alt="The old logo: a cream sailboat on an olive khaki tile"> | <img src="https://raw.githubusercontent.com/yahyabedirhan/shipyard/aaf87593a297cd7113983769aa9b11fab97d9f86/docs/assets/logo/shipyard.png" width="160" alt="The new logo: a cream sailboat on a khaki green tile"> |

## Special things to note

- `#72873A` is the middle of the logo's gradient, which runs from `#809741` at the top to `#637532` at the bottom, like the old logo's did. The sailboat stays cream.
- The old logo is kept as the `olive-khaki` alternate with its own colours, so the #80 options and comparison sheets redraw byte for byte. Only `AppIcon.icns`, the README's logo and the new alternate files change.
- The tests check the badge's colours but no one has looked at it on screen yet. Check the welcome screen in the real app: it should be khaki green with a cream sailboat. Finder may keep showing the old icon until its icon cache refreshes.

## Change outline

The logo's colours live in one file, which the app and the icon script both compile:

```diff
 enum Logo {
-    static let top: UInt32 = 0x8C8660
-    static let bottom: UInt32 = 0x6A6541
+    static let top: UInt32 = 0x809741     // either side of 0x72873A
+    static let bottom: UInt32 = 0x637532
     static let figure: UInt32 = 0xFBF6EA  // cream, unchanged
```

The logo becomes its own icon variant, and olive khaki takes its colours back as an alternate. `Minimal.draw` gets a static form so the logo can be drawn without joining the #80 options:

```diff
 Variant
+  khaki-green  → Minimal.draw(hue: Logo.top…Logo.bottom, figure: Logo.figure)   # the app's icon
   olive-khaki  → Minimal.solidOliveKhaki
-                   hue: Logo.top…Logo.bottom
+                   hue: 0x8C8660…0x6A6541
   origami, sailboat, night, sunset
```

```diff
-ICON        ?= olive-khaki
-ALTERNATES  := origami sailboat night sunset
+ICON        ?= khaki-green
+ALTERNATES  := olive-khaki origami sailboat night sunset
```

```diff
 Packaging/Icon/
 ├── AppIcon.icns              # redrawn in khaki green
 ├── alternates/
+│   ├── olive-khaki.icns      # the 0.0.2 logo
+│   └── olive-khaki.png
 └── README.md                 # names khaki-green as the app's icon
 docs/assets/logo/shipyard.png # the README's logo, re-exported at 256 px
```

🤖 Generated with [Claude Code](https://claude.com/claude-code)
