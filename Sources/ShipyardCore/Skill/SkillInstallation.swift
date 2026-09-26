import Foundation
import Observation

/// One install of the agent skill as the panel shows it: offered, running
/// (with Cancel), or how it ended. `SkillInstaller` has no timeout, so this
/// stops an install that runs longer than `timeout` (an `npx` stuck on the
/// network), and Cancel stops it sooner. The app keeps one for the whole run,
/// so an install keeps going, and its result stays, while the panel is closed.
@MainActor
@Observable
public final class SkillInstallation {
    /// Where an install is.
    public enum State: Equatable, Sendable {
        /// Not started, or cancelled: the offer to install.
        case idle
        /// The command is running.
        case running
        /// The command ended: installed, failed, or no `npx`.
        case finished(SkillInstallResult)
        /// Stopped after running `seconds`.
        case timedOut(seconds: TimeInterval)
    }

    /// How long an install may run before it's stopped: `npx` downloads the
    /// `skills` package first, which can take a while on a slow network.
    public static let defaultTimeout: TimeInterval = 180

    /// Where the install is; the panel draws it.
    public private(set) var state: State = .idle

    private let installer: SkillInstaller
    private let timeout: TimeInterval
    private let sleep: Sleep
    private var task: Task<Void, Never>?
    /// Counts installs, so one that was cancelled (and still winds down)
    /// never writes over the state of a later one.
    private var generation = 0

    public init(
        installer: SkillInstaller = SkillInstaller(),
        timeout: TimeInterval = SkillInstallation.defaultTimeout,
        sleep: @escaping Sleep = systemSleep
    ) {
        self.installer = installer
        self.timeout = timeout
        self.sleep = sleep
    }

    /// Starts the install, unless one is running; returns the running one,
    /// which ends when the install has.
    @discardableResult
    public func start() -> Task<Void, Never> {
        if state == .running, let task { return task }
        state = .running
        generation += 1
        let current = generation
        let task = Task { await run(current) }
        self.task = task
        return task
    }

    /// Stops a running install and goes back to the offer at once; a result
    /// that arrives after is dropped.
    public func cancel() {
        guard state == .running else { return }
        generation += 1
        state = .idle
        task?.cancel()
    }

    private enum Outcome: Sendable {
        case finished(SkillInstallResult)
        case timedOut
    }

    private func run(_ current: Int) async {
        let installer = installer, timeout = timeout, sleep = sleep
        let outcome = await withTaskGroup(of: Outcome?.self) { group in
            group.addTask { .finished(await installer.install()) }
            group.addTask {
                // `nil` when the sleep is cancelled: the install finished first.
                guard (try? await sleep(timeout)) != nil else { return nil }
                return .timedOut
            }
            var first: Outcome?
            for await outcome in group where first == nil {
                first = outcome
                // The other one stops: the timer, or the shell (whose runner
                // returns at once when cancelled).
                if outcome != nil { group.cancelAll() }
            }
            return first
        }
        guard current == generation, let outcome else { return }
        switch outcome {
        case .finished(let result): state = .finished(result)
        case .timedOut: state = .timedOut(seconds: timeout)
        }
    }
}
