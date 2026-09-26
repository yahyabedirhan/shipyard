import ShipyardCore

/// A `ShellRunning` whose command never finishes on its own, like an `npx`
/// stuck on the network: it waits until its task is cancelled, and records
/// that it was.
final class HangingShell: ShellRunning {
    private let log = Locked<(started: Int, cancelled: Int)>((0, 0))

    var started: Int { log.current.started }
    var cancelled: Int { log.current.cancelled }

    func run(_ invocation: ShellInvocation) async -> ShellOutput? {
        log.withValue { $0.started += 1 }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        log.withValue { $0.cancelled += 1 }
        return ShellOutput(status: 143, output: "Terminated")
    }
}
