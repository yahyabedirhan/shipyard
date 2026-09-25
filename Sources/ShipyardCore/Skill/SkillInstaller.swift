import Foundation

/// How installing the shipyard agent skill ended, for onboarding and the
/// panel's "Install agent skill…".
public enum SkillInstallResult: Equatable, Sendable {
    /// The command succeeded; its output, for a details line.
    case installed(output: String)
    /// The command ran and failed, or the shell couldn't be started; what it
    /// printed (or why it didn't run), to show the user.
    case failed(output: String)
    /// The login shell has no `npx`: show `command` with a Copy button.
    case npxNotFound(command: String)
}

/// An executable and its arguments, as the installer runs them.
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

/// Runs a shell and waits for it. The seam between the installer and
/// spawning a process, so tests use a fake shell.
public protocol ShellRunning: Sendable {
    /// What the run printed and its status; `nil` when it couldn't be started.
    func run(_ invocation: ShellInvocation) async -> ShellOutput?
}

/// Installs the shipyard agent skill by running
/// `npx -y skills add yahyabedirhan/shipyard -g -y` for the user.
///
/// An `.app` starts with an almost empty `PATH`, and `npx` usually comes from
/// nvm, asdf or Homebrew set up in the user's shell profile, so the command
/// runs through the user's login shell as an interactive one
/// (`$SHELL -l -i -c '…'`), which reads those profiles.
public struct SkillInstaller: Sendable {
    /// The command the installer runs, and the one to copy when it can't.
    public static let command = "npx -y skills add yahyabedirhan/shipyard -g -y"
    /// The shell used when `$SHELL` isn't set to an absolute path: macOS's
    /// default login shell.
    public static let fallbackShell = "/bin/zsh"
    /// The status a shell exits with when it can't find a command (zsh, bash,
    /// sh and fish alike): here, `npx`.
    public static let commandNotFoundStatus: Int32 = 127

    /// The shell and arguments the install runs.
    public let invocation: ShellInvocation
    private let runner: any ShellRunning

    public init(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        runner: any ShellRunning = ProcessShellRunner()
    ) {
        let shell = environment["SHELL"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? Self.fallbackShell
        invocation = ShellInvocation(executable: shell, arguments: ["-l", "-i", "-c", Self.command])
        self.runner = runner
    }

    /// Runs the command and reports how it went.
    public func install() async -> SkillInstallResult {
        guard let result = await runner.run(invocation) else {
            return .failed(output: "couldn't start \(invocation.executable)")
        }
        let output = Self.clean(result.output)
        switch result.status {
        case 0:
            return .installed(output: output)
        case Self.commandNotFoundStatus:
            return .npxNotFound(command: Self.command)
        default:
            return .failed(output: output.isEmpty ? "`\(Self.command)` exited with status \(result.status)" : output)
        }
    }

    /// The output without terminal colour codes and surrounding blank space,
    /// so the panel can show it as plain text.
    static func clean(_ output: String) -> String {
        output
            .replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
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
                control.onEnd = { continuation.resume(returning: $0) }
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
    private var ended = false
    /// Called once, with the run's output or `nil`. Set before `runToEnd()`.
    var onEnd: ((ShellOutput?) -> Void)?

    init(_ invocation: ShellInvocation) {
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
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
            guard !ended else { return nil }
            ended = true
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
