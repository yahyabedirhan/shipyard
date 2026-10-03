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
        /// `app open`: launch the app unless it runs, then wait until it
        /// answers. With a demo, the running app is quit first and the
        /// demo's launched; without one, a demo that runs is quit and the
        /// normal app launched.
        case open(demo: Demo?)
        /// `app quit`: ask the app to quit, then wait until it's gone.
        case quit
        /// Any other request, answered by the app.
        case send(ControlRequest)
    }

    /// `app open --demo <folder>`: the app run on the folder's
    /// configuration (`<folder>/shipyard/config.toml`) and support folder
    /// (`<folder>/support`), leaving the user's own alone.
    public struct Demo: Equatable, Sendable {
        /// The demo folder, absolute.
        public var folder: URL
        /// What the launched app reads `gh auth token` with: the GitHub
        /// CLI's own folder, which moving `XDG_CONFIG_HOME` would otherwise
        /// move into the demo folder, signing the demo out.
        public var ghConfig: URL

        public init(folder: URL, ghConfig: URL) {
            self.folder = folder
            self.ghConfig = ghConfig
        }

        /// The demo run's support folder: state, resolved repositories, the
        /// avatar, pings and the socket.
        public var support: URL { folder.appendingPathComponent("support", isDirectory: true) }

        /// The environment the demo app is launched with.
        public var environment: [String: String] {
            [
                "XDG_CONFIG_HOME": folder.path,
                SupportFolder.overrideVariable: support.path,
                "GH_CONFIG_DIR": ghConfig.path,
            ]
        }

        /// The GitHub CLI's folder as `gh` finds it with `variables`:
        /// `GH_CONFIG_DIR`, else `$XDG_CONFIG_HOME/gh`, else
        /// `~/.config/gh`, `~` from `HOME`, else the user's home. A relative
        /// one is taken against `workingDirectory`, as `gh` would.
        static func ghFolder(variables: [String: String], workingDirectory: URL) -> URL {
            if let dir = variables["GH_CONFIG_DIR"], !dir.isEmpty {
                return absolute(dir, in: workingDirectory)
            }
            if let xdg = variables["XDG_CONFIG_HOME"], !xdg.isEmpty {
                return absolute(xdg, in: workingDirectory).appendingPathComponent("gh", isDirectory: true)
            }
            let home = variables["HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0, isDirectory: true) : nil }
                ?? FileManager.default.homeDirectoryForCurrentUser
            return home.appendingPathComponent(".config/gh", isDirectory: true)
        }
    }

    /// What running an invocation needs.
    public struct Context: Sendable {
        /// The app's normal support folder, where `app open --demo` leaves
        /// its `DemoPointer`.
        public var support: URL
        /// The client asking the app at the socket `ControlSocket.locate`
        /// found.
        public var client: ControlClient
        public var launcher: any AppLaunching
        /// Waits between two looks at the app while it starts or quits.
        public var pause: @Sendable (TimeInterval) -> Void

        public init(support: URL, client: ControlClient, launcher: any AppLaunching, pause: @escaping @Sendable (TimeInterval) -> Void) {
            self.support = support
            self.client = client
            self.launcher = launcher
            self.pause = pause
        }

        /// The same client, asking at `socket`.
        func client(at socket: URL) -> ControlClient {
            var client = client
            client.socket = socket
            return client
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
        usage: shipyard app open [--demo <folder>] | quit | status [--json]

          open     launch shipyard in the background, unless it runs, and wait
                   until it answers (about 10 seconds at most)
                   --demo <folder>: quit shipyard and run it on the folder's
                   shipyard/config.toml, keeping its state in <folder>/support
                   and leaving yours alone; plain open brings yours back
          quit     quit shipyard, and wait until it's gone
          status   whether shipyard runs: its version, whether the panel is
                   open, its layout and its projects (--json: one JSON object)

        Every command but open exits 1 when shipyard isn't running.

        """

    static let notRunning = "shipyard isn't running; `shipyard app open`"

    /// Reads the arguments after `app`, a demo folder against `environment`'s
    /// working folder. `--help` is the usage on standard output; anything
    /// that doesn't read is the usage on standard error, exit 2.
    public static func parse(_ arguments: [String], environment: CommandEnvironment) -> Result<Invocation, CommandResult> {
        if arguments.contains("--help") || arguments.contains("-h") {
            return .failure(CommandResult(output: usageText))
        }
        guard let subcommand = arguments.first else {
            return .failure(CommandResult(error: usageText, status: CommandResult.usageStatus))
        }
        let rest = Array(arguments.dropFirst())
        switch (subcommand, rest) {
        case ("open", []):
            return .success(.open(demo: nil))
        case ("open", ["--demo"]):
            return .failure(misread("shipyard app open: --demo needs a folder"))
        case ("open", let rest) where rest.count == 2 && rest[0] == "--demo":
            return demo(rest[1], environment: environment).map { .open(demo: $0) }
        case ("quit", []):
            return .success(.quit)
        case ("status", []):
            return .success(.send(.appStatus(json: false)))
        case ("status", ["--json"]):
            return .success(.send(.appStatus(json: true)))
        case ("open", _), ("quit", _), ("status", _):
            // The first word past the option this subcommand takes, if it led.
            let option = switch (subcommand, rest.first) {
            case ("status", "--json"): 1
            case ("open", "--demo"): 2
            default: 0
            }
            let extra = rest[option]
            return .failure(misread("shipyard app \(subcommand): unexpected `\(extra)`"))
        default:
            return .failure(misread("shipyard app: unknown command `\(subcommand)`"))
        }
    }

    /// The demo folder `path` names, made absolute against the working
    /// folder: it must be a folder, and its socket's path short enough for
    /// a socket's address.
    private static func demo(_ path: String, environment: CommandEnvironment) -> Result<Demo, CommandResult> {
        let folder = absolute(path, in: environment.workingDirectory).standardizedFileURL
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            return .failure(misread("shipyard app open: no folder at \(folder.path)"))
        }
        let demo = Demo(
            folder: folder,
            ghConfig: Demo.ghFolder(variables: environment.variables, workingDirectory: environment.workingDirectory)
        )
        let socket = ControlSocket.url(in: demo.support).path
        guard socket.utf8.count <= UnixSocket.maximumPathLength else {
            return .failure(misread("shipyard app open: \(UnixSocket.tooLong(socket)); use a folder with a shorter path"))
        }
        return .success(demo)
    }

    /// `path` as a folder, taken against `directory` when it's relative.
    private static func absolute(_ path: String, in directory: URL) -> URL {
        path.hasPrefix("/")
            ? URL(fileURLWithPath: path, isDirectory: true)
            : directory.appendingPathComponent(path, isDirectory: true)
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
        case .open(let demo?):
            return openDemo(demo, context)
        case .open(nil):
            return open(context)
        case .quit:
            return quit(context.client, context)
        }
    }

    /// The normal app's status when it runs. Otherwise it's launched, then
    /// asked for its status every quarter second until it answers, or exit
    /// 1 after about 10 seconds. A demo left running is quit first, and its
    /// pointer removed.
    private static func open(_ context: Context) -> CommandResult {
        let normal = context.client(at: ControlSocket.url(in: context.support))
        if let demo = DemoPointer.recorded(in: context.support) {
            if let refused = quitIfRunning(context.client(at: ControlSocket.url(in: demo)), context) { return refused }
            do {
                try DemoPointer.remove(in: context.support)
            } catch {
                return .failed("shipyard app open: couldn't remove \(DemoPointer.url(in: context.support).path): \(error.localizedDescription)")
            }
        }
        switch normal.send(.appStatus(json: false)) {
        case .failure(.notRunning):
            break
        case let answer:
            // It runs (or is there but failing): no second launch.
            return result(of: answer)
        }
        return launch(environment: [:], answeringAt: normal, context)
    }

    /// Points the command at the demo's support folder, quits whatever app
    /// answers (the normal one, or a demo the pointer named), launches the
    /// app on the demo, and waits for it as `open` does. The pointer is
    /// written first, so nothing is quit when it can't be, and removed again
    /// when no demo comes to run.
    private static func openDemo(_ demo: Demo, _ context: Context) -> CommandResult {
        let normal = ControlSocket.url(in: context.support)
        do {
            try DemoPointer.record(demo.support, in: context.support)
        } catch {
            return .failed("shipyard app open: couldn't write \(DemoPointer.url(in: context.support).path): \(error.localizedDescription)")
        }
        var result: CommandResult?
        for socket in Set([context.client.socket, normal]).sorted(by: { $0.path < $1.path }) where result == nil {
            result = quitIfRunning(context.client(at: socket), context)
        }
        let outcome = result
            ?? launch(environment: demo.environment, answeringAt: context.client(at: ControlSocket.url(in: demo.support)), context)
        if outcome.status != 0 {
            // No demo runs: later commands look for the normal app again.
            try? DemoPointer.remove(in: context.support)
        }
        return outcome
    }

    /// Quits the app answering `client`, waiting until it's gone; nil when
    /// it's gone or never ran, else what to exit with.
    private static func quitIfRunning(_ client: ControlClient, _ context: Context) -> CommandResult? {
        if case .failure(.notRunning) = client.send(.appStatus(json: false)) { return nil }
        let result = quit(client, context)
        return result.status == 0 ? nil : result
    }

    /// Launches the app with `environment`, then asks `client` for its
    /// status every quarter second until it answers, or exit 1 after about
    /// 10 seconds.
    private static func launch(environment: [String: String], answeringAt client: ControlClient, _ context: Context) -> CommandResult {
        let status = ControlRequest.appStatus(json: false)
        do throws(AppLaunchFailure) {
            try context.launcher.launch(bundleID: ShipyardBundle.identifier, environment: environment)
        } catch {
            return .failed("shipyard app open: \(error.reason)")
        }
        // A starting app may accept a connection before it can answer, so
        // each look waits briefly and a slow one is looked at again.
        var look = client
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
    private static func quit(_ client: ControlClient, _ context: Context) -> CommandResult {
        let answer = client.send(.appQuit)
        guard case .success(let reply) = answer, reply.ok else { return result(of: answer) }
        var look = client
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
