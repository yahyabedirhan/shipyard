import Foundation

/// An executable and its arguments, as a `ShellRunning` runs them: the
/// skill installer's login shell, or `herdr`.
public struct ShellInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

/// What a finished shell printed (standard output and error together) and
/// its exit status.
public struct ShellOutput: Equatable, Sendable {
    public var status: Int32
    public var output: String

    public init(status: Int32, output: String) {
        self.status = status
        self.output = output
    }
}

/// Runs a shell (or any program) and waits for it. The seam between its
/// callers (the skill installer, `HerdrCommand`) and spawning a process,
/// so tests use a fake shell.
public protocol ShellRunning: Sendable {
    /// What the run printed and its status; `nil` when it couldn't be started.
    func run(_ invocation: ShellInvocation) async -> ShellOutput?
}

/// Runs the shell with Foundation's `Process`: standard input empty (so an
/// interactive shell can't wait for it), standard output and error read
/// together before waiting, so a full pipe can't block it.
///
/// Cancelling the task stops the run: it returns `nil` at once, and the shell
/// and every process under it get SIGTERM, then SIGKILL a second later. The
/// shell alone isn't enough: an interactive one ignores SIGTERM and runs the
/// command as a job in its own process group, which outlives it.
public struct ProcessShellRunner: ShellRunning {
    public init() {}

    public func run(_ invocation: ShellInvocation) async -> ShellOutput? {
        let control = ProcessControl(invocation)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard control.whenEnded({ continuation.resume(returning: $0) }) else { return }
                DispatchQueue.global(qos: .userInitiated).async { control.runToEnd() }
            }
        } onCancel: {
            control.terminate()
        }
    }
}

/// One shell run that another thread can stop. It ends once, with whichever
/// comes first: the process's output, or `nil` for a cancel (before or after
/// the launch).
private final class ProcessControl: @unchecked Sendable {
    /// How long the group has after SIGTERM before SIGKILL.
    private static let killDelay: TimeInterval = 1

    private let lock = NSLock()
    private let process = Process()
    private let pipe = Pipe()
    private var cancelled = false
    /// The run's result, once it has ended.
    private var ended: ShellOutput?? = nil
    /// Called once, with the run's output or `nil`.
    private var onEnd: ((ShellOutput?) -> Void)?

    init(_ invocation: ShellInvocation) {
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
    }

    /// Sets what the run calls when it ends. When it has already ended (a
    /// cancel before the start), calls `body` at once and returns false: there
    /// is nothing left to run.
    func whenEnded(_ body: @escaping (ShellOutput?) -> Void) -> Bool {
        let result: ShellOutput?? = locked {
            if ended == nil { onEnd = body }
            return ended
        }
        guard let result else { return true }
        body(result)
        return false
    }

    /// Runs the process and waits for it; ends with `nil` when it couldn't start.
    func runToEnd() {
        guard launch() else { return end(nil) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        end(ShellOutput(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self)))
    }

    /// Stops the run: ends it with `nil` now, and signals the shell and its
    /// descendants.
    func terminate() {
        let shell: pid_t? = locked {
            cancelled = true
            return process.isRunning ? process.processIdentifier : nil
        }
        end(nil)
        guard let shell else { return }
        DispatchQueue.global().async {
            let pids = [shell] + Self.descendants(of: shell)
            for pid in pids { kill(pid, SIGTERM) }
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.killDelay) {
                for pid in pids { kill(pid, SIGKILL) }
            }
        }
    }

    /// Every process under `root`, from `ps` (macOS and Linux alike).
    private static func descendants(of root: pid_t) -> [pid_t] {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-A", "-o", "pid=,ppid="]
        let pipe = Pipe()
        ps.standardOutput = pipe
        ps.standardError = FileHandle.nullDevice
        guard (try? ps.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        var children: [pid_t: [pid_t]] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: " ").compactMap { pid_t($0) }
            guard fields.count == 2 else { continue }
            children[fields[1], default: []].append(fields[0])
        }
        var found: [pid_t] = []
        var queue = children[root] ?? []
        while let pid = queue.popLast() {
            found.append(pid)
            queue += children[pid] ?? []
        }
        return found
    }

    private func launch() -> Bool {
        locked {
            guard !cancelled else { return false }
            do {
                try process.run()
                return true
            } catch {
                return false
            }
        }
    }

    private func end(_ output: ShellOutput?) {
        let onEnd: ((ShellOutput?) -> Void)? = locked {
            guard ended == nil else { return nil }
            ended = .some(output)
            defer { self.onEnd = nil }
            return self.onEnd
        }
        onEnd?(output)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
