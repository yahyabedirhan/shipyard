import AppKit
import ImageIO
import ScreenCaptureKit
import ShipyardControl
import ShipyardCore
import SwiftUI
import UniformTypeIdentifiers

/// How a screenshot was made: written as asked (the panel captured from the
/// screen as drawn, or the menu bar icon, which is always drawn), rendered
/// by the app instead of captured (with why capturing didn't work), or not
/// written at all.
enum ScreenshotOutcome: Equatable {
    case captured
    case rendered(why: String)
    case failed(why: String)
}

/// What the control server asks for a `shipyard screenshot`.
@MainActor
protocol Screenshotting: AnyObject {
    /// The panel, opened when it's closed, written as a PNG at `file`, in
    /// `appearance` when it's set (and back to the app's own afterwards).
    func capturePanel(to file: URL, appearance: ControlRequest.Appearance?) async -> ScreenshotOutcome
    /// The menu bar icon alone, as the menu bar draws it in `appearance`
    /// (the Mac's when nil), written as a PNG at `file`. The real menu bar
    /// strip can't be captured, so this is always rendered.
    func menuBarIcon(to file: URL, appearance: ControlRequest.Appearance?) -> ScreenshotOutcome
}

/// Captures the panel's window through ScreenCaptureKit, limited to this
/// process's own windows (`SCShareableContent.currentProcess`, macOS
/// 14.4), which needs no Screen Recording permission. When that fails or
/// is refused, it renders the panel itself: the open window's view as
/// AppKit draws it, or a fresh panel when the window isn't there.
@MainActor
final class Screenshotter: Screenshotting {
    private let panel: any PanelControlling
    /// A panel to render when its window can't be drawn from, one that
    /// doesn't count as the panel being open.
    private let freshPanel: @MainActor () -> AnyView
    /// How long the panel gets to finish appearing, or redrawing in a new
    /// appearance, before it's captured.
    private static let settle = Duration.milliseconds(350)

    init(panel: any PanelControlling, freshPanel: @escaping @MainActor () -> AnyView) {
        self.panel = panel
        self.freshPanel = freshPanel
    }

    func capturePanel(to file: URL, appearance: ControlRequest.Appearance?) async -> ScreenshotOutcome {
        let previous = NSApp.appearance
        if let appearance { NSApp.appearance = ScreenshotImage.appearance(appearance) }
        defer { NSApp.appearance = previous }

        let image: CGImage
        let captureFailure: String?
        do throws(ScreenshotFailure) {
            image = try await capture()
            captureFailure = nil
        } catch let failure {
            // Rendered with the appearance asked for, or the app's as it is now.
            let drawing = NSApp.effectiveAppearance
            if let window = Self.panelWindow(), let view = window.contentView,
               let drawn = ScreenshotImage.render(view, appearance: drawing) {
                image = drawn
            } else if let drawn = ScreenshotImage.render(freshPanel(), appearance: drawing) {
                image = drawn
            } else {
                return .failed(why: "couldn't capture the panel (\(failure.why)) or render it")
            }
            captureFailure = failure.why
        }
        return Self.write(image, to: file, as: captureFailure.map { .rendered(why: $0) } ?? .captured)
    }

    func menuBarIcon(to file: URL, appearance: ControlRequest.Appearance?) -> ScreenshotOutcome {
        let drawing = appearance.map(ScreenshotImage.appearance) ?? NSApp.effectiveAppearance
        guard let image = ScreenshotImage.menuBarIcon(appearance: drawing) else {
            return .failed(why: "couldn't render the menu bar icon")
        }
        return Self.write(image, to: file, as: .captured)
    }

    /// `outcome` once `image` is written at `file`; failed, naming the
    /// path, when it can't be.
    private static func write(_ image: CGImage, to file: URL, as outcome: ScreenshotOutcome) -> ScreenshotOutcome {
        do throws(ScreenshotFailure) {
            try ScreenshotImage.write(image, to: file)
            return outcome
        } catch {
            return .failed(why: error.why)
        }
    }

    /// Opens the panel, lets it settle, and captures its window as drawn.
    private func capture() async throws(ScreenshotFailure) -> CGImage {
        do throws(PanelRefusal) {
            try await panel.open()
        } catch {
            throw ScreenshotFailure(error.reason)
        }
        try? await Task.sleep(for: Self.settle)
        guard let window = Self.panelWindow() else { throw ScreenshotFailure("the panel's window isn't on screen") }
        guard #available(macOS 14.4, *) else {
            throw ScreenshotFailure("capturing the app's own window without Screen Recording needs macOS 14.4")
        }
        return try await Self.captureOwnWindow(CGWindowID(window.windowNumber))
    }

    /// The window `windowID` names, captured by ScreenCaptureKit from this
    /// process's shareable content only, at its display's scale.
    @available(macOS 14.4, *)
    nonisolated private static func captureOwnWindow(_ windowID: CGWindowID) async throws(ScreenshotFailure) -> CGImage {
        do {
            let content = try await SCShareableContent.currentProcess
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw ScreenshotFailure("ScreenCaptureKit doesn't list the panel's window among this app's")
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()
            let scale = CGFloat(filter.pointPixelScale)
            configuration.width = Int((filter.contentRect.width * scale).rounded())
            configuration.height = Int((filter.contentRect.height * scale).rounded())
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        } catch let failure as ScreenshotFailure {
            throw failure
        } catch {
            throw ScreenshotFailure("ScreenCaptureKit: \(error.localizedDescription)")
        }
    }

    /// The menu bar icon's panel window while it's on screen: SwiftUI's
    /// `MenuBarExtra` window, else the largest visible window that isn't
    /// the status bar's own.
    private static func panelWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter { window in
            window.isVisible && !window.responds(to: NSSelectorFromString("statusItem"))
                && window.frame.width > 0 && window.frame.height > 0
        }
        if let extra = candidates.first(where: { String(describing: type(of: $0)).contains("MenuBarExtra") }) {
            return extra
        }
        return candidates.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }
}

/// Why a screenshot step didn't work, as one line.
struct ScreenshotFailure: Error, Equatable {
    var why: String

    init(_ why: String) {
        self.why = why
    }
}

/// The screenshot's drawing and writing, apart from the app's windows, so
/// it runs in tests: a view rendered in an appearance, the menu bar icon,
/// and a PNG written.
@MainActor
enum ScreenshotImage {
    /// The system appearance a screenshot draws in.
    static func appearance(_ appearance: ControlRequest.Appearance) -> NSAppearance? {
        NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
    }

    /// `view` as AppKit draws it in `appearance`, at the main screen's
    /// scale; nil when it has no size.
    static func render(_ view: NSView, appearance: NSAppearance?) -> CGImage? {
        let previous = view.appearance
        defer { view.appearance = previous }
        view.appearance = appearance
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int((bounds.width * scale).rounded()),
            pixelsHigh: Int((bounds.height * scale).rounded()),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = bounds.size
        var image: CGImage?
        (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: bounds, to: bitmap)
            image = bitmap.cgImage
        }
        return image
    }

    /// A SwiftUI view rendered at its own size (at most `maxHeight` points
    /// tall) in `appearance`, through a hosting view as a window would
    /// draw it, so AppKit-backed controls are drawn too.
    static func render(_ view: AnyView, appearance: NSAppearance?, maxHeight: CGFloat = 900) -> CGImage? {
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        let fitting = host.fittingSize
        guard fitting.width > 0, fitting.height > 0 else { return nil }
        host.frame = CGRect(origin: .zero, size: CGSize(width: fitting.width, height: min(fitting.height, maxHeight)))
        return render(host, appearance: appearance)
    }

    /// The menu bar icon at the menu bar's size, tinted as the menu bar
    /// tints its template image in `appearance`: dark in light, white in dark.
    static func menuBarIcon(appearance: NSAppearance?) -> CGImage? {
        let isDark = appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let side = SailboatImage.menuBarSide
        let icon = Image(nsImage: SailboatImage.menuBar(side: side))
            .renderingMode(.template)
            .foregroundStyle(isDark ? Color.white : Color.black)
            .frame(width: side, height: side)
        return render(AnyView(icon), appearance: appearance)
    }

    /// `image` written as a PNG at `file`, replacing what's there.
    static func write(_ image: CGImage, to file: URL) throws(ScreenshotFailure) {
        guard let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw ScreenshotFailure("couldn't write \(file.path): its folder doesn't exist or can't be written")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotFailure("couldn't write \(file.path)")
        }
    }
}
