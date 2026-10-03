import Foundation

/// What a command run prints and how it exits: the `shipyard` executable
/// writes `output` to standard output and `error` to standard error, then
/// exits with `status`.
public struct CommandResult: Equatable, Sendable {
    public var output: String
    public var error: String
    /// 0 when it worked; `CommandResult.failed` (1) when it was refused,
    /// such as a ping for a project that doesn't exist; `usage` (2) when
    /// the arguments don't read.
    public var status: Int32

    public init(output: String = "", error: String = "", status: Int32 = 0) {
        self.output = output
        self.error = error
        self.status = status
    }

    public static let failedStatus: Int32 = 1
    public static let usageStatus: Int32 = 2

    /// Refused: one line on standard error, exit 1.
    public static func failed(_ message: String) -> CommandResult {
        CommandResult(error: message + "\n", status: failedStatus)
    }

    /// The arguments don't read: one line on standard error, exit 2.
    public static func usage(_ message: String) -> CommandResult {
        CommandResult(error: message + "\n", status: usageStatus)
    }
}

/// So a step that can't go on can hand back the result to print.
extension CommandResult: Error {}
