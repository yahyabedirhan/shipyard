import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Starts the app, which `shipyard app open` can't ask through the socket
/// since the app isn't running yet. Tests record the launch.
public protocol AppLaunching: Sendable {
    /// Launches the app `bundleID` in the background, with `environment`
    /// (empty for a normal launch) set for it. Throws a line saying why it
    /// couldn't.
    func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure)
}

/// Why the app couldn't be launched, in words.
public struct AppLaunchFailure: Error, Equatable, Sendable {
    public var reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

/// The app's bundle id, which `app open` launches.
public enum ShipyardBundle {
    public static let identifier = "com.yahyabedirhan.shipyard"
}

#if canImport(AppKit)
/// Launches through Launch Services (`NSWorkspace`), without bringing the
/// app forward: the menu bar app has no window to show, and the agent's
/// terminal keeps the focus.
public struct WorkspaceLauncher: AppLaunching {
    /// How long to wait for Launch Services to say the app started.
    var timeout: TimeInterval = 10

    public init() {}

    public func launch(bundleID: String, environment: [String: String]) throws(AppLaunchFailure) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw AppLaunchFailure("no app with the bundle id \(bundleID) is installed")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        if !environment.isEmpty { configuration.environment = environment }
        let outcome = LaunchOutcome()
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            outcome.error = error.map(\.localizedDescription)
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else {
            throw AppLaunchFailure("Launch Services didn't start \(url.path) within \(Int(timeout)) seconds")
        }
        if let error = outcome.error {
            throw AppLaunchFailure("couldn't launch \(url.path): \(error)")
        }
    }

    /// The completion handler's answer, read after the semaphore.
    private final class LaunchOutcome: @unchecked Sendable {
        var error: String?
    }
}
#endif
