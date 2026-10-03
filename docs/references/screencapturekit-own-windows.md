# Capturing the app's own window with ScreenCaptureKit

Checked 2026-10-03 for issue #169, against the sources listed at the end. The question: how `shipyard screenshot` can capture shipyard's own panel window, and whether that needs the Screen Recording permission. Toolchain as checked: Swift 6.3 with the Command Line Tools' macOS 26 SDK, deployment target macOS 14.

## What shipyard does

`Screenshotter` (`Sources/ShipyardApp/Control/Screenshotter.swift`) asks for `SCShareableContent.currentProcess`, finds the panel's window among its `windows` by window number, builds an `SCContentFilter(desktopIndependentWindow:)` on it, and takes one frame with `SCScreenshotManager.captureImage(contentFilter:configuration:)`, sized from the filter's `contentRect` and `pointPixelScale`. If any step fails, it renders the panel itself instead and says so (`captured by rendering: <why>`), so a refusal never blocks a screenshot.

## Facts

- **The current process's content needs no consent.** `+[SCShareableContent getCurrentProcessShareableContentWithCompletionHandler:]`, in Swift `SCShareableContent.currentProcess` (async), is available from macOS 14.4. The SDK header says the content it returns "will contain redacted information about windows, displays and applications that are available to capture by current process without user consent via TCC". TCC is the system behind the Privacy & Security permissions, Screen Recording among them. (`SCShareableContent.h`, macOS 26 SDK; Apple's documentation page for the method gives only its signature.)
- **The other ways to get shareable content need Screen Recording.** `SCShareableContent.excludingDesktopWindows(_:onScreenWindowsOnly:)` and its siblings list every app's windows, and the system asks the user for Screen Recording the first time an app calls them. So on macOS 14.0–14.3 shipyard doesn't capture: it renders, with the reason "capturing the app's own window without Screen Recording needs macOS 14.4".
- **One frame without a stream.** `SCScreenshotManager.captureImage(contentFilter:configuration:completionHandler:)` (macOS 14.0) "takes a screenshot using the filter and configuration passed in and returns it as a CGImage". The image comes in BGRA when the capture's dynamic range is SDR, the default. (`SCScreenshotManager.h`.)
- **A filter on one window.** `SCContentFilter(desktopIndependentWindow:)` captures that window alone, whatever is around or above it. `contentRect` and `pointPixelScale` (macOS 14.0) give its size in points and the display's pixels per point, so `SCStreamConfiguration.width` and `height` are set to the window's size in pixels. `ignoreShadowsSingleWindow` leaves the window's shadow out.
- **No entitlement grants capture.** Outside the current-process path, ScreenCaptureKit is gated only by the user's Screen Recording grant in System Settings. A grant is tied to the app's code signature. Shipyard is ad-hoc signed (`make bundle`), so a reinstalled build may lose a grant given to an earlier one. The current-process path doesn't depend on that grant.
- **The menu bar strip isn't the app's window.** The status item draws in a window the system owns, so `--menu-bar-icon` draws `SailboatImage` itself instead of capturing it.

## Open question

`Packaging/Info.plist` has no `NSScreenCaptureUsageDescription`. Third-party ScreenCaptureKit guides (the `screencapturekit` Rust crate's README) say an app that triggers the Screen Recording prompt without that purpose string may be terminated; this wasn't confirmed in Apple's documentation. Shipyard shouldn't trigger the prompt, since it only uses the current process's content. If the first real capture does show a prompt, or the app quits during a capture, adding the string is the first thing to check.

## First real capture

<!-- The orchestrator fills this in from the first `shipyard screenshot` on the maintainer's Mac. -->

- **First real capture on the maintainer's Mac:** _TO FILL IN: date, macOS version, build (commit), `shipyard screenshot /tmp/x.png` captured or rendered (and the stderr note if rendered), whether a permission prompt appeared, light and dark results._

## Sources

- Apple, ScreenCaptureKit header `SCShareableContent.h`, `getCurrentProcessShareableContentWithCompletionHandler:` (`API_AVAILABLE(macos(14.4))`), in the Command Line Tools' macOS 26 SDK: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/ScreenCaptureKit.framework/Headers/SCShareableContent.h`.
- Apple, ScreenCaptureKit header `SCScreenshotManager.h`, `captureImageWithFilter:configuration:completionHandler:` (`API_AVAILABLE(macos(14.0))`), same SDK.
- Apple Developer Documentation, [getCurrentProcessShareableContent(completionHandler:)](https://developer.apple.com/documentation/screencapturekit/scshareablecontent/getcurrentprocessshareablecontent(completionhandler:)).
- Apple Developer Documentation, [SCShareableContent](https://developer.apple.com/documentation/screencapturekit/scshareablecontent).
- Apple Developer Documentation, [SCScreenshotManager](https://developer.apple.com/documentation/screencapturekit/scscreenshotmanager).
- Apple Developer Documentation, [SCContentFilter init(desktopIndependentWindow:)](https://developer.apple.com/documentation/screencapturekit/sccontentfilter/init(desktopindependentwindow:)).
