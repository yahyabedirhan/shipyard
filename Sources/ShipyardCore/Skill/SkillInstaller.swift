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
public struct ProcessShellRunner: ShellRunning {
    public init() {}

    public func run(_ invocation: ShellInvocation) async -> ShellOutput? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: invocation.executable)
                process.arguments = invocation.arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                continuation.resume(returning: ShellOutput(
                    status: process.terminationStatus,
                    output: String(decoding: data, as: UTF8.self)
                ))
            }
        }
    }
}
