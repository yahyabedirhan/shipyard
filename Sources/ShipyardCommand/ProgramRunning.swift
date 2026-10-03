import Foundation

/// The output of a finished program.
public struct CommandOutput: Equatable, Sendable {
    public var status: Int32
    public var standardOutput: String

    public init(status: Int32, standardOutput: String) {
        self.status = status
        self.standardOutput = standardOutput
    }
}

/// Runs an executable with arguments and waits for it; `nil` when it
/// couldn't be started. The seam between a command and spawning `git`,
/// `herdr` or `gh`, so tests answer for them.
public typealias ProgramRun = @Sendable (_ executable: String, _ arguments: [String]) -> CommandOutput?

/// The real way to run a program.
public enum ProgramRunner {
    /// Runs the program with Foundation's `Process`, reading its standard
    /// output before waiting so a full pipe can't block it; its standard
    /// error is dropped.
    public static let process: ProgramRun = { executable, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandOutput(status: process.terminationStatus, standardOutput: String(decoding: data, as: UTF8.self))
    }
}
