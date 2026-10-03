import Foundation
import ShipyardCommand

/// `shipyard app …`: its arguments read into an `Invocation`, and an
/// invocation run against the app (through `ControlClient`) or, for
/// `open`, launched first (through `AppLaunching`). Exit codes follow the
/// command line's rule: 0 done, 1 refused (the app isn't running, or it
/// refused the request), 2 for arguments that don't read.
public enum ControlCommand {
    /// What a command line asks for.
    public enum Invocation: Equatable, Sendable {
        /// `app open`: launch the app unless it runs, then wait until it answers.
        case open
        /// `app quit`: ask the app to quit, then wait until it's gone.
        case quit
        /// Any other request, answered by the app.
        case send(ControlRequest)
    }

    /// What running an invocation needs.
    public struct Context: Sendable {
        public var client: ControlClient
        public var launcher: any AppLaunching
        /// Waits between two looks at the app while it starts or quits.
        public var pause: @Sendable (TimeInterval) -> Void

        public init(client: ControlClient, launcher: any AppLaunching, pause: @escaping @Sendable (TimeInterval) -> Void) {
            self.client = client
            self.launcher = launcher
            self.pause = pause
        }
    }

    /// How long `open` waits for a launched app to answer, and `quit` for
    /// the app to go, in looks a quarter second apart.
    static let wait: TimeInterval = 10
    static let interval: TimeInterval = 0.25
    /// How long one look at a starting or quitting app waits for an
    /// answer: such an app may accept a connection before (or after) it
    /// can answer, and the looks must fit in `wait`.
    static let lookTimeout: TimeInterval = 1

    public static let usageText = """
        usage: shipyard app open | quit | status [--json]

          open     launch shipyard in the background, unless it runs, and wait
                   until it answers (about 10 seconds at most)
          quit     quit shipyard, and wait until it's gone
          status   whether shipyard runs: its version, whether the panel is
                   open, its layout and its projects (--json: one JSON object)

        Every command but open exits 1 when shipyard isn't running.

        """

    static let notRunning = "shipyard isn't running; `shipyard app open`"

    /// Reads the arguments after `app`. `--help` is the usage on standard
    /// output; anything that doesn't read is the usage on standard error,
    /// exit 2.
    public static func parse(_ arguments: [String]) -> Result<Invocation, CommandResult> {
        if arguments.contains("--help") || arguments.contains("-h") {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        let rest = Array(arguments.dropFirst())
        switch (subcommand, rest) {
        case ("open", []):
            return .success(.open)
        case ("quit", []):
            return .success(.quit)
        case ("status", []):
            return .success(.send(.appStatus(json: false)))
        case ("status", ["--json"]):
            return .success(.send(.appStatus(json: true)))
        case ("open", _), ("quit", _), ("status", _):
            let extra = subcommand == "status" && rest.first == "--json" ? rest[1] : rest[0]
            return .failure(misread("shipyard app \(subcommand): unexpected `\(extra)`"))
        default:
            return .failure(misread("shipyard app: unknown command `\(subcommand)`"))
        }
    }

    /// `line`, then the usage, on standard error: exit 2.
    private static func misread(_ line: String) -> CommandResult {
        CommandResult(error: line + "\n" + usageText, status: CommandResult.usageStatus)
    }

    /// Runs `invocation` in `context`.
    public static func run(_ invocation: Invocation, context: Context) -> CommandResult {
        switch invocation {
        case .send(let request):
            return result(of: context.client.send(request))
        case .open:
            return open(context)
        case .quit:
            return quit(context)
        }
    }

    /// The app's status when it runs. Otherwise it's launched, then asked
    /// for its status every quarter second until it answers, or exit 1
    /// after about 10 seconds.
    private static func open(_ context: Context) -> CommandResult {
        let status = ControlRequest.appStatus(json: false)
        switch context.client.send(status) {
        case .failure(.notRunning):
            break
        case let answer:
            // It runs (or is there but failing): no second launch.
            return result(of: answer)
        }
        do throws(AppLaunchFailure) {
            try context.launcher.launch(bundleID: ShipyardBundle.identifier, environment: [:])
        } catch {
            return .failed("shipyard app open: \(error.reason)")
        }
        // A starting app may accept a connection before it can answer, so
        // each look waits briefly and a slow one is looked at again.
        var look = context.client
        look.timeout = lookTimeout
        for _ in 0..<looks {
            context.pause(interval)
            switch look.send(status) {
            case .failure(.notRunning), .failure(.timedOut):
                continue
            case let answer:
                return result(of: answer)
            }
        }
        return .failed("shipyard didn't answer within \(Int(wait)) seconds of launching")
    }

    /// Asks the app to quit; once it said it will, waits until nothing
    /// answers on the socket, so a following `app open` launches a new app
    /// instead of finding the old one.
    private static func quit(_ context: Context) -> CommandResult {
        let answer = context.client.send(.appQuit)
        guard case .success(let reply) = answer, reply.ok else { return result(of: answer) }
        var look = context.client
        look.timeout = lookTimeout
        for _ in 0..<looks {
            if case .failure(.notRunning) = look.send(.appStatus(json: false)) {
                return CommandResult(output: reply.output, error: reply.error)
            }
            context.pause(interval)
        }
        return .failed("shipyard said it would quit, but it still answers after \(Int(wait)) seconds")
    }

    private static var looks: Int { Int(wait / interval) }

    /// What a reply, or the failure to get one, prints and how it exits.
    static func result(of answer: Result<ControlReply, ControlClient.Failure>) -> CommandResult {
        switch answer {
        case .success(let reply) where reply.ok:
            return CommandResult(output: reply.output, error: reply.error)
        case .success(let reply):
            return .failed(reply.error.isEmpty ? "shipyard refused without saying why" : reply.error)
        case .failure(.notRunning):
            return .failed(notRunning)
        case .failure(.timedOut(let seconds)):
            return .failed("shipyard didn't answer within \(Int(seconds)) seconds")
        case .failure(.failed(let why)):
            return .failed("couldn't ask shipyard: \(why)")
        }
    }
}
