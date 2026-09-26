import AppKit

/// Calls `onWake` a few seconds after the Mac wakes from sleep, once the
/// network has had a moment to come back.
@MainActor
final class WakeObserver {
    // Only written in `init`; read by `deinit`, which is nonisolated.
    nonisolated(unsafe) private var observer: (any NSObjectProtocol)?

    init(delay: TimeInterval = 5, onWake: @escaping @MainActor () -> Void) {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                onWake()
            }
        }
    }

    deinit {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
