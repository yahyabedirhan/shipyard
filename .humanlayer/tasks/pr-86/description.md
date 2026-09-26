[#85 the khaki green logo](https://github.com/yahyabedirhan/shipyard/pull/85)

## Why the change

The khaki green logo (#85) changed the app after 0.0.2 was released, so this PR bumps the version to 0.0.3 so that the release, its zip and the app's Info.plist all say which build has the new logo.

## Special things to note

- The effort that was named `shipyard-0-0-3` (#77, #83, #84) moves to `shipyard-0-0-4`, since 0.0.3 is now this release.
- Nothing else changes: `make release` builds `Shipyard-0.0.3-macos.zip` from the same code as `main`.

## Change outline

The version lives in one place, and packaging stamps it into the bundle and the zip's name:

```diff
 public enum ShipyardVersion {
-    public static let current = "0.0.2"
+    public static let current = "0.0.3"
 }
```

```diff
 README.md                              # "this README describes 0.0.3"
 Sources/ShipyardCore/Version.swift     # 0.0.3
 Tests/ShipyardCoreTests/PortsTests.swift  # expects 0.0.3
```

🤖 Generated with [Claude Code](https://claude.com/claude-code)
