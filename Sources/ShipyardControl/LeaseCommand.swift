import Foundation
import ShipyardCommand

/// `shipyard control …`: holding and giving up the lease on purpose, its
/// arguments read into the `ControlRequest` the app answers and the holder
/// key the command is sent as, when `--key` names one.
public enum LeaseCommand {
    /// What a command line asks for.
    public struct Invocation: Equatable, Sendable {
        public var request: ControlRequest
        /// `--key <k>`: the holder key for this command only, in place of
        /// the one `Holder.find` works out (`SHIPYARD_CONTROL_KEY`'s included).
        public var key: String?

        public init(_ request: ControlRequest, key: String? = nil) {
            self.request = request
            self.key = key
        }
    }

    public static let usageText = """
        usage: shipyard control take [--wait <seconds>] [--for <purpose>] [--key <k>]
                                | release [--key <k>]

          take      hold shipyard until 5 minutes after you took it, so other
                    agents' app, panel and screenshot commands are refused
                    meanwhile; prints "you hold shipyard until <HH:mm:ss>"
                    --wait <seconds>: while another agent holds it, wait in
                    line, first come first served, up to that long (0 to
                    3600)
                    --for <purpose>: why, in a few words, shown to the user on
                    the panel's banner ("checking the header icons"); one
                    line, at most 80 characters
          release   give shipyard up, so the next agent in line gets it; does
                    nothing when you don't hold it
          --key <k> hold or give it up as <k>, for this command only, in place
                    of the agent shipyard works out; pass the same key to
                    release

        To send every app, panel, screenshot and control command as <k>,
        export SHIPYARD_CONTROL_KEY=<k> for the run; --key still wins.

        Each exits 1 when shipyard isn't running; take also when another agent
        holds it, or still holds it once the wait runs out.

        """

    /// Reads the arguments after `control`. `--help` is the usage on
    /// standard output; anything that doesn't read is the usage on standard
    /// error, exit 2.
    public static func parse(_ arguments: [String]) -> Result<Invocation, CommandResult> {
        if arguments.contains("--help") || arguments.contains("-h") {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        let options: Set<String>
        switch subcommand {
        case "take": options = ["--wait", "--for", "--key"]
        case "release": options = ["--key"]
        default: return .failure(misread("shipyard control: unknown command `\(subcommand)`"))
        }
        var values: [String: String] = [:]
        var rest = arguments.dropFirst()
        while let option = rest.popFirst() {
            guard options.contains(option), values[option] == nil else {
                return .failure(misread("shipyard control \(subcommand): unexpected `\(option)`"))
            }
            guard let value = rest.popFirst() else {
                let what = option == "--wait" ? "a number of seconds" : option == "--for" ? "a purpose" : "a key"
                return .failure(misread("shipyard control \(subcommand): \(option) needs \(what)"))
            }
            values[option] = value
        }
        if let key = values["--key"], key.isEmpty {
            return .failure(misread("shipyard control \(subcommand): --key needs a key"))
        }
        guard subcommand == "take" else { return .success(Invocation(.controlRelease, key: values["--key"])) }
        var wait: Int?
        if let seconds = values["--wait"] {
            guard let whole = Int(seconds), (0...ControlRequest.longestWait).contains(whole) else {
                return .failure(misread(
                    "shipyard control take: --wait takes whole seconds from 0 to \(ControlRequest.longestWait), not `\(seconds)`"
                ))
            }
            wait = whole
        }
        if let purpose = values["--for"], !ControlLease.readsAsPurpose(purpose) {
            return .failure(misread(
                "shipyard control take: --for takes one line of at most \(ControlLease.longestPurpose) characters"
            ))
        }
        return .success(Invocation(.controlTake(waitSeconds: wait, purpose: values["--for"]), key: values["--key"]))
    }

    /// `line`, then the usage, on standard error: exit 2.
    private static func misread(_ line: String) -> CommandResult {
        CommandResult(error: line + "\n" + usageText, status: CommandResult.usageStatus)
    }
}
