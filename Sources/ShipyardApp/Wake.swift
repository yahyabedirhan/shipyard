import AppKit

@MainActor
final class WakeObserver {
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
