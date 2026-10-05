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

/// What the control server asks for a `shipyard screenshot`. Both leave
/// the lease's dot and banner out unless `withIndicator` keeps them.
@MainActor
protocol Screenshotting: AnyObject {
    /// The panel, captured while it's open and rendered off screen while
    /// it's closed (never opened for it), written as a PNG at `file`, in
    /// `appearance` when it's set (and back to the app's own afterwards).
    func capturePanel(to file: URL, appearance: ControlRequest.Appearance?, withIndicator: Bool) async -> ScreenshotOutcome
    /// The menu bar icon alone, as the menu bar draws it in `appearance`
    /// (the Mac's when nil), written as a PNG at `file`. The real menu bar
    /// strip can't be captured, so this is always rendered.
    func menuBarIcon(to file: URL, appearance: ControlRequest.Appearance?, withIndicator: Bool) async -> ScreenshotOutcome
}

/// Captures the panel's window through ScreenCaptureKit, limited to this
/// process's own windows (`SCShareableContent.currentProcess`, macOS
/// 14.4), which needs no Screen Recording permission. When that fails or
/// is refused, it renders a fresh panel itself, off screen. Unless asked
/// to keep them, it hides the lease's dot and banner for the capture
/// (`LeaseIndicator.hideForCapture()`) and shows them again afterwards
/// (`showAfterCapture()`), once no other capture still hides them.
@MainActor
final class Screenshotter: Screenshotting {
    private let panel: any PanelControlling
    private let indicator: LeaseIndicator
    /// A panel to render when the window can't be captured, one that
    /// doesn't count as the panel being open.
    private let freshPanel: @MainActor () -> AnyView
    /// How long the panel gets to finish appearing, or redrawing in a new
    /// appearance, before it's captured.
    private static let settle = Duration.milliseconds(350)

    init(panel: any PanelControlling, indicator: LeaseIndicator, freshPanel: @escaping @MainActor () -> AnyView) {
        self.panel = panel
        self.indicator = indicator
        self.freshPanel = freshPanel
    }

    func capturePanel(to file: URL, appearance: ControlRequest.Appearance?, withIndicator: Bool) async -> ScreenshotOutcome {
        let previous = NSApp.appearance
        if let appearance { NSApp.appearance = ScreenshotImage.appearance(appearance) }
        defer { NSApp.appearance = previous }
        // Counted, not saved and restored: overlapping captures each end
        // their own hiding. One asking for the indicator while another
        // hides it captures without the banner.
        if !withIndicator { Self.withoutAnimation { indicator.hideForCapture() } }
        defer { if !withIndicator { Self.withoutAnimation { indicator.showAfterCapture() } } }

        let image: CGImage
        let captureFailure: String?
        do throws(ScreenshotFailure) {
            image = try await capture()
            captureFailure = nil
        } catch let failure {
            // A panel of its own, in the appearance asked for (or the app's
            // as it is now): the open window's view drawn alone loses its
            // vibrant colours and symbols, a fresh panel keeps them.
            if let drawn = await ScreenshotImage.render(freshPanel(), appearance: NSApp.effectiveAppearance, opaque: true) {
                image = drawn
            } else {
                return .failed(why: "couldn't capture the panel (\(failure.why)) or render it")
            }
            captureFailure = failure.why
        }
        return Self.write(image, to: file, as: captureFailure.map { .rendered(why: $0) } ?? .captured)
    }

    func menuBarIcon(to file: URL, appearance: ControlRequest.Appearance?, withIndicator: Bool) async -> ScreenshotOutcome {
        let drawing = appearance.map(ScreenshotImage.appearance) ?? NSApp.effectiveAppearance
        // Rendered, not captured: the live icon keeps its dot meanwhile,
        // and another capture hiding the indicator doesn't drop it here.
        let dot = withIndicator && indicator.lease.status(at: Date()) != nil
        guard let image = await ScreenshotImage.menuBarIcon(appearance: drawing, leaseDot: dot) else {
            return .failed(why: "couldn't render the menu bar icon")
        }
        return Self.write(image, to: file, as: .captured)
    }

    /// Runs `change` with the panel's animations off, so the banner is gone
    /// (or back) at once rather than sliding while the panel is captured.
    private static func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
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

    /// Captures the open panel's window as drawn, after a moment for a new
    /// appearance to settle. A closed panel isn't opened: a screenshot
    /// never puts the panel in front of the user, who may have just closed
    /// it, so it's rendered instead.
    private func capture() async throws(ScreenshotFailure) -> CGImage {
        guard panel.status().panelOpen else { throw ScreenshotFailure("the panel is closed") }
        try? await Task.sleep(for: Self.settle)
        guard let window = MenuBarWindow.panelWindow else { throw ScreenshotFailure("the panel's window isn't on screen") }
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
    /// scale; nil when it has no size. `opaque` lays it on the window
    /// background colour: a panel's own background is the window's
    /// material, which a view drawn alone leaves transparent (and white
    /// text on it unreadable).
    static func render(_ view: NSView, appearance: NSAppearance?, opaque: Bool) -> CGImage? {
        let previous = view.appearance
        defer { view.appearance = previous }
        view.appearance = appearance
        view.layoutSubtreeIfNeeded()
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let width = Int((bounds.width * scale).rounded()), height = Int((bounds.height * scale).rounded())
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }
        bitmap.size = bounds.size
        var image: CGImage?
        (appearance ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: bounds, to: bitmap)
            guard let drawn = bitmap.cgImage else { return }
            guard opaque else { image = drawn; return }
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
            context.fill(rect)
            context.draw(drawn, in: rect)
            image = context.makeImage()
        }
        return image
    }

    /// A SwiftUI view rendered at its own size (at most `maxHeight` points
    /// tall) in `appearance`. It's laid out in a window of its own, off
    /// screen and invisible, for a moment, so views that measure
    /// themselves (the panel's lists) settle before it's drawn.
    static func render(_ view: AnyView, appearance: NSAppearance?, opaque: Bool, maxHeight: CGFloat = 900) async -> CGImage? {
        let host = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 1, height: 1),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.ignoresMouseEvents = true
        window.appearance = appearance
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        // Each pass fits the window to what the view now asks for.
        for _ in 0..<3 {
            let fitting = host.fittingSize
            window.setContentSize(CGSize(width: fitting.width, height: min(fitting.height, maxHeight)))
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(100))
        }
        return render(host, appearance: appearance, opaque: opaque)
    }

    /// The menu bar icon at the menu bar's size, tinted as the menu bar
    /// tints its template image in `appearance`: dark in light, white in
    /// dark; with the lease's yellow dot beside it when `leaseDot` asks.
    static func menuBarIcon(appearance: NSAppearance?, leaseDot: Bool = false) async -> CGImage? {
        let isDark = appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let side = SailboatImage.menuBarSide
        let icon: AnyView
        if leaseDot {
            // In its own colours, the sailboat tinted for the appearance it's drawn in.
            let image = LeaseDot.image(on: .sailboat)
            icon = AnyView(Image(nsImage: image).frame(width: image.size.width, height: image.size.height))
        } else {
            icon = AnyView(Image(nsImage: SailboatImage.menuBar(side: side))
                .renderingMode(.template)
                .foregroundStyle(isDark ? Color.white : Color.black)
                .frame(width: side, height: side))
        }
        return await render(icon, appearance: appearance, opaque: false)
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
