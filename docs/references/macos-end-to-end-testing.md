# End-to-end testing a macOS menu bar app

Checked 2026-09-25 for issue #34, against the sources listed at the end (each with its date). Toolchain as checked: Swift 6.3.2 with Command Line Tools only (`xcode-select -p` is `/Library/Developer/CommandLineTools`), macOS 26.

## Recommendation

**Adopt a small launch smoke test now. Don't adopt XCUITest, Appium or pixel snapshots.**

1. **Release zip check (no permissions, runs everywhere).** A `make` step that unzips `build/Shipyard-<version>-macos.zip`, runs `codesign --verify --strict`, checks the bundle's version against `Version.swift`, and launches the unzipped app to check it's still running a few seconds later. This catches a broken bundle, a bad signature or a crash at launch, which no current test sees.
2. **One Accessibility (AX) smoke test in Swift.** A test built with SwiftPM that launches the bundled app, finds its status item through the Accessibility API (`AXUIElementCreateApplication` → `AXExtrasMenuBar`), presses it (`AXPress`), checks that the panel window opens on the expected screen, and quits the app. It's the non-hacky form of today's `osascript` clicks: the same API System Events uses underneath, typed Swift, no screen coordinates, no Xcode. It proves the wiring the core harness can't see (the `.app` launches, the `MenuBarExtra` is inserted, the label shows the model's text, the panel opens). Every rule stays in the core harness.
   - Verified read-only on the maintainer's Mac on 2026-09-25: a `swiftc`-built binary run from the terminal reported `AXIsProcessTrusted() == true` and found shipyard's item as `AXMenuBarItem` / subrole `AXMenuExtra`, title `50 PRs · 1 run` (the model's `menuBarLabel` text), with the action `AXPress`. Nothing was pressed.
   - Keep it opt-in (`make e2e`), because it needs a GUI session and the Accessibility grant, and it launches a real copy of the app.

What the AX test needs from the app first, so it doesn't touch the maintainer's real data:
- **Isolated configuration and `gh` login:** already there. `ConfigStore` honours `XDG_CONFIG_HOME`, and so does `gh` (`$XDG_CONFIG_HOME/gh` unless `GH_CONFIG_DIR` is set), so launching with `open -n --env XDG_CONFIG_HOME=<temp dir>` gives an app with no projects and no `gh` login: a deterministic connect screen without the network. (Unless `GH_TOKEN`/`GITHUB_TOKEN` is set in the environment, which `gh` prefers over stored logins; the test must unset them.)
- **An isolated state directory:** missing. `state.json` always lives in `~/Library/Application Support/Shipyard/`. A launch-environment override (for example `SHIPYARD_STATE_DIR`) is the one small app change needed.
- **Stable accessibility identifiers** on the few elements the test reads (`.accessibilityIdentifier(...)` on the panel's header and connect screen), so the test doesn't match on copy.
- **One running copy:** the test quits any running shipyard first (two instances would show two status items), so it's not something to run while an agent is using the real menu bar.

**Not yet:** data scenarios end to end (a fixture PR appearing, the count rising, a notification firing). They need a fixture HTTP mode inside the shipped app, which is test-only machinery in the product, and they would re-check rules the core harness already covers through `Shipyard` with stubbed HTTP, an injectable clock and a recording notifier. Revisit if a bug slips through between the model and the SwiftUI views; at that point render-for-review attachments (below) are the cheaper next step.

**CI:** add the release-zip check to the macOS job now. The AX smoke test should work on GitHub's hosted macOS runners (their image pre-grants Accessibility to the runner agent, see below), but that's inferred from the image scripts, not yet run: try it in a separate, non-required job first.

## Comparison

| Option | Setup cost | Xcode needed | CI fit (GitHub-hosted macOS) | Reliability | Fit for a menu-bar-only app |
|---|---|---|---|---|---|
| Core harness (today) | none, exists | no | yes, Ubuntu and macOS | high: no UI, stubbed HTTP and clock | covers every rule; never sees the `.app`, the status item or the views |
| XCUITest | high: Xcode (full install), an `.xcodeproj` (or XcodeGen/Tuist) with the app and a UI-test bundle target, since SwiftPM has no UI-test target type | yes | good: runners have Xcode, Xcode Helper has Accessibility, automation mode needs no password | medium: known "not hittable" status items when the menu bar is hidden | can reach status items (`statusItems`, `menuBars`); XCTest-only, not Swift Testing |
| AX API from a Swift test/tool | low: a test or small executable target, `ApplicationServices` only | no | likely: the runner agent (the responsible process) has Accessibility; unverified | medium-high: no coordinates; timing needs polling | good: `AXExtrasMenuBar` exposes the item with `AXPress` (verified locally) |
| AppleScript/JXA via System Events | none | no | yes: `osascript` and `bash` have Accessibility and Apple Events to System Events on runners | low-medium: stringly typed, UI-path based, errors are opaque | works (it's what's used today), but it's the same AX tree with less structure |
| Appium mac2 driver | high: Node, Appium 3, the driver, WebDriverAgentMac (XCTest) built and signed | yes (13+) | possible but heavy | medium; extra moving parts (WDA, WebDriver) | reaches whatever XCTest reaches; no gain over XCUITest for one app |
| swift-snapshot-testing | low in Xcode | **effectively yes**: it `import XCTest` unconditionally, and Command Line Tools ship no `XCTest` module | yes with Xcode | medium: pixel output differs across macOS versions (its docs: compare on the same OS) | renders `NSView`s (wrap SwiftUI in `NSHostingView`), not the live menu bar |
| `ImageRenderer` + Swift Testing image attachments | low | no | yes | high as an artifact, poor as an assertion | good for reviewing panel states; `ImageRenderer` shows placeholders for AppKit-backed controls |
| Release-zip script | very low | no | yes, no permissions | high | checks the shipped artifact, not the UI |

## XCUITest on macOS

- UI tests are XCTest's `XCUIAutomation` framework: "Use XCTest to write tests that control your app using XCUIAutomation" (XCUIAutomation docs, framework split out in Xcode 16.3). "When you import XCTest, a framework called XCUIAutomation is automatically included", and "UI automation is supported on all Apple platforms", macOS included (WWDC25 *Record, replay, and review*, June 2025).
- Still XCTest-only in 2026: "UI automation and performance testing APIs are only available in XCTest" (WWDC26 *Migrate to Swift Testing*, June 2026). WWDC26's other testing session, *AppIntentsTesting*, also runs inside a UI-test bundle.
- `XCUIElementTypeQueryProvider` has `statusItems`, `menuBars` and `menuBarItems` on macOS, so a `MenuBarExtra` is reachable in principle. A developer-forums thread (Feb 2025) reports `Element StatusItem ... is not hittable` for an agent app when Xcode is full screen and the menu bar is hidden; the answer is to move the pointer to the top edge first.
- Recording UI tests prompts to give **Xcode Helper** Accessibility (Recording UI automation for testing).
- **Cost for shipyard:** installing Xcode locally (today only CI has it, via `setup-xcode`); an Xcode project with an app target and a UI-testing bundle target (SwiftPM `Package.swift` targets are libraries, executables, tests, plugins, macros; there's no UI-test or app-host kind), which duplicates the Makefile's bundling; signing the test runner (the app is ad-hoc signed today); tests written in XCTest while the rest are Swift Testing. That's a second build system for one smoke test.

## The Accessibility API from a test process

- `AXUIElementCreateApplication(pid)` returns an app's top-level accessibility object; the application element has `kAXExtrasMenuBarAttribute` (`"AXExtrasMenuBar"`) next to `kAXMenuBarAttribute` and `kAXWindowsAttribute` (`AXUIElement.h`, `AXAttributeConstants.h`, macOS 26.5 SDK in Command Line Tools). `AXUIElementPerformAction` performs `AXPress`. All in `ApplicationServices`, which builds with Command Line Tools (checked: `import ApplicationServices` type-checks, `import XCTest` doesn't).
- The caller must be a trusted accessibility client: `AXIsProcessTrustedWithOptions` "Returns whether the current process is a trusted accessibility client", with `kAXTrustedCheckOptionPrompt` to ask. A process started from a terminal is judged by its responsible process, the terminal app (runner-images' TCC script describes the same rule for the runner agent: approvals are "keyed by the *responsible* process"). So `swift test` from the maintainer's terminal inherits the grant `osascript` already uses; confirmed with the probe above.
- SwiftUI's `.accessibilityIdentifier(_:)` is exposed to assistive clients as the element's `AXIdentifier` (the probe read it as absent today: shipyard sets none), which is what a test should match on rather than visible text.
- This is what System Events UI scripting uses underneath ("User interface scripting relies upon the OS X accessibility frameworks", Mac Automation Scripting Guide), without the AppleScript layer.

## AppleScript and JXA

- UI scripting "simulates user interaction, such as mouse clicks and keystrokes"; "accessibility control of apps is disabled" by default and "the user must manually enable it on an app-by-app ... basis" (Mac Automation Scripting Guide, updated 2016-06-13, archived).
- Also needs Automation (Apple Events) consent for the sender to control System Events.
- It works today, but it's scripts addressing `menu bar item 1 of menu bar 2 of process "Shipyard"` with string errors, and no test report. The Swift AX test replaces it with the same capability in the test runner.

## Appium mac2 driver

- "Under the hood, the driver relies on Apple's XCTest framework", through the bundled WebDriverAgentMac (overview). Requirements: macOS 11.3+, Appium 3 (driver 3.0+), **Xcode 13 or later**, Xcode Helper added to Accessibility by hand, and possibly `automationmodetool enable-automationmode-without-authentication` (getting started). Unsigned WDA can trigger "WebDriverAgentRunner-Runner is from unidentified developer", fixed only by signing it (troubleshooting). Latest release v4.3.5, 2026-09-10.
- Everything XCUITest costs, plus Node and a WebDriver server. It pays off for cross-language suites over many apps, not for one menu.

## Snapshot testing

- pointfreeco/swift-snapshot-testing 1.19.6 (2026-09-21) supports Swift Testing (`@Suite(.snapshots(record: .failed))`) and macOS `NSView`/`NSViewController` image strategies; SwiftUI views on macOS go through `NSHostingView` (the `SwiftUIView` strategy is iOS/tvOS only). Its `NSView` strategy notes: "Snapshots must be compared on the same OS as the device that originally took the reference."
- `Sources/SnapshotTesting/AssertSnapshot.swift` has `import XCTest` unconditionally. Command Line Tools on this Mac have no `XCTest` module (`error: no such module 'XCTest'`), so it doesn't build here without Xcode.
- References taken on the maintainer's macOS and compared on the runner's macOS 26 image would drift with each OS update (fonts, materials, SF Symbols).
- **Without Xcode:** Swift Testing's `Attachment` (ST-0009, Swift 6.2) and image attachments (ST-0014, ST-0017, Swift 6.3) accept `NSImage`; `_Testing_AppKit.framework` in Command Line Tools declares `extension NSImage: AttachableAsImage`, and `swift test --attachments-path <dir>` writes them out. That's a render-for-review artifact (the panel in each phase, light and dark), not a pixel assertion.
- `ImageRenderer` "only includes views that SwiftUI rasterizes directly ... It does not include views whose contents are composited by Core Animation layers, such as more complex controls and containers ... and most types of UIKit and AppKit views", which get a placeholder. For the panel (scroll view, buttons), `NSHostingView` + `cacheDisplay(in:to:)` (what swift-snapshot-testing does) is closer to real. The views live in the `ShipyardApp` executable target, so such a test target would depend on it (macOS-only in `Package.swift`).

## GitHub-hosted macOS runners and permissions

- `macos-latest` points to **macOS 26 Arm64** (runner-images README). The macOS 15 Arm64 image (20260907.0337.1) ships Xcode 16.0–26.3, default 16.4; shipyard's CI selects `latest-stable`.
- The image's `configure-tccdb-macos.sh` (last changed 2026-08-03) writes TCC rows at build time. Relevant ones:
  - **Accessibility:** `/bin/bash`, `/usr/bin/osascript`, `/opt/hca/hosted-compute-agent` (the runner agent), `com.apple.dt.Xcode-Helper`, `com.apple.Terminal`.
  - **Apple Events:** `bash` and `osascript` → System Events and Finder.
  - **Screen Recording:** `bash`, `osascript`, the agent; and since 2026-08-03 a far-future `replayd` approval for the agent, because on macOS 15+ legacy capture otherwise "raises a recurring ... alert, which takes focus and breaks headed UI tests" (#14474).
- `configure-machine.sh` runs `automationmodetool enable-automationmode-without-authentication` and sets display sleep to never. `automationmodetool` "can be used to configure a device such that Automation Mode for UI testing can be enabled without user authentication. This is useful for ... continuous integration (CI) environments" (man page, 2021-03-18).
- So on a hosted runner, a job's process tree (responsible process: the agent) is expected to be a trusted accessibility client, and XCUITest's Xcode Helper is pre-approved. Outside GitHub's image you can't grant Accessibility from a script: SIP protects the TCC database, and the supported route, a Privacy Preferences Policy Control profile, needs MDM with supervision (Apple Platform Deployment). Screen Recording can't be pre-allowed by that profile at all, only denied or left for a standard user to approve.
- History: issues #3286 (2021) and #1567 show earlier images without these rows, with the `universalAccessAuthWarn` window interrupting UI tests; #11874 (2025) was an intermittent test-runner failure on macOS 15 that went away on retry. Treat hosted UI jobs as occasionally flaky and keep them out of the required checks until they've proven stable.
- The menu bar can be hidden (Menu Bar settings: automatically hide "Always", "On Desktop Only", "In Full Screen Only", "Never"), and a user can switch an app's item off under "Allow in the Menu Bar" (Apple Support, macOS 26/27). An AX test should read the item's attributes and use `AXPress` rather than clicking coordinates, and fail with a clear message if the extras menu bar is empty.

## Notifications, login items and the release zip

- **Notifications:** the first `requestAuthorization` "prompts the person"; later calls don't (UserNotifications). A fresh CI user has never answered it, and a delivered banner can only be checked from outside by scripting Notification Center's own UI, which is Apple's private UI and changes per release. The core's recording notifier already asserts what is posted and when. Keep delivery a manual check per release (post one, click it, see the item open).
- **Launch at login:** `SMAppService` registers the main app as a login item (macOS 13+); `.requiresApproval` means "the user needs to take action in System Settings", also when they revoked it. `sfltool dumpbtm` "prints the current status of login and background items" and `sfltool resetbtm` resets them, with Apple recommending a restart between tests (Apple Platform Deployment). The core's recording `LoginItem` covers when it's told; the real registration stays a manual check (or an assertion on `SMAppService.mainApp.status` from inside the app, not worth a hook today).
- **Release zip:** fully scriptable without permissions: `ditto -x -k` into a temp dir, `codesign --verify --strict` on the bundle, `plutil -extract CFBundleShortVersionString raw` equals the version, `LSUIElement` is true, then `open -n` it (with the isolated `XDG_CONFIG_HOME`), check it's running after a few seconds, and quit it. Gatekeeper (`spctl --assess`) rejects an ad-hoc signature; that's expected until the Developer ID launch, and a downloaded (quarantined) copy then needs the user's approval in System Settings.

## Sources

- Apple, [XCUIAutomation](https://developer.apple.com/documentation/xcuiautomation) and [XCUIElementTypeQueryProvider.statusItems](https://developer.apple.com/documentation/xcuiautomation/xcuielementtypequeryprovider/statusitems) (Xcode 16.3+), [Recording UI automation for testing](https://developer.apple.com/documentation/xcuiautomation/recording-ui-automation-for-testing): checked 2026-09-25.
- Apple, WWDC25 session 344, [Record, replay, and review: UI automation with Xcode](https://developer.apple.com/videos/play/wwdc2025/344/) (June 2025).
- Apple, WWDC26 session 267, [Migrate to Swift Testing](https://developer.apple.com/videos/play/wwdc2026/267/), and session 295, [Validate your App Intents adoption with AppIntentsTesting](https://developer.apple.com/videos/play/wwdc2026/295/) (June 2026). WWDC24's [Meet Swift Testing](https://developer.apple.com/videos/play/wwdc2024/10179/) (June 2024) introduced the framework; no WWDC24–26 session adds UI automation outside XCTest.
- Apple, Developer Forums, [XCTEST a bit trouble on not seeing the statusbar](https://developer.apple.com/forums/thread/773715) (Feb 2025).
- Apple, `HIServices` headers `AXUIElement.h` and `AXAttributeConstants.h` in the Command Line Tools macOS 26.5 SDK; [kAXExtrasMenuBarAttribute](https://developer.apple.com/documentation/applicationservices/kaxextrasmenubarattribute) (macOS 10.8+): checked 2026-09-25.
- Apple, [Mac Automation Scripting Guide: Automating the User Interface](https://developer.apple.com/library/archive/documentation/LanguagesUtilities/Conceptual/MacAutomationScriptingGuide/AutomatetheUserInterface.html) (updated 2016-06-13).
- Apple, [ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer), [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [SMAppService.Status.requiresApproval](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval), [requestAuthorization(options:completionHandler:)](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)): checked 2026-09-25.
- Apple Platform Deployment, [Privacy Preferences Policy Control payload](https://support.apple.com/guide/deployment/privacy-preferences-policy-control-payload-dep38df53c2a/web) and [Manage login items and background tasks on Mac](https://support.apple.com/guide/deployment/manage-login-items-background-tasks-mac-depdca572563/web): checked 2026-09-25.
- Apple Support, [Change Menu Bar settings on Mac](https://support.apple.com/guide/mac-help/mchlad96d366/mac): checked 2026-09-25.
- `man automationmodetool` (2021-03-18), `man open` (`--env`, `-n`), `gh help environment` (gh 2.92.0): read on the maintainer's Mac 2026-09-25.
- Swift evolution, [ST-0009 Attachments](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0009-attachments.md) (Swift 6.2), [ST-0014 Image attachments (Apple platforms)](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0014-image-attachments-in-swift-testing-apple-platforms.md) and [ST-0017](https://github.com/swiftlang/swift-evolution/blob/main/proposals/testing/0017-image-attachment-consolidation.md) (Swift 6.3): checked 2026-09-25.
- [pointfreeco/swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) 1.19.6 (2026-09-21): README, `Package.swift`, `AssertSnapshot.swift`, `Snapshotting/NSView.swift`, `Snapshotting/SwiftUIView.swift`.
- [appium/appium-mac2-driver](https://github.com/appium/appium-mac2-driver) v4.3.5 (2026-09-10): `docs/overview.md`, `docs/getting-started/index.md`, `docs/troubleshooting/index.md`.
- [actions/runner-images](https://github.com/actions/runner-images): README (`macos-latest` = macOS 26 Arm64), [macOS 15 Arm64 image readme](https://github.com/actions/runner-images/blob/main/images/macos/macos-15-arm64-Readme.md) (20260907.0337.1), `images/macos/scripts/build/configure-tccdb-macos.sh` (last commit 2026-08-03, PR #14489; PR #12728 2025-08-11 added the `osascript` rows), `images/macos/scripts/build/configure-machine.sh`; issues [#14474](https://github.com/actions/runner-images/issues/14474) (2026-07-30), [#11874](https://github.com/actions/runner-images/issues/11874) (2025-03-25), [#3286](https://github.com/actions/runner-images/issues/3286) (2021), [#1567](https://github.com/actions/runner-images/issues/1567).
