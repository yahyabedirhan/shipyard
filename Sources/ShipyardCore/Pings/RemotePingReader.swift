import Foundation

/// Asks one machine for its pings, through the Mac's Herdr and its saved
/// machine connection (ADR 0005): never `ssh`, never an address.
///
/// The herdr-shipyard plugin on the machine declares a `list` action that
/// prints `shipyard ping list --json` (`PingList`). Plugin actions take no
/// arguments and answer through Herdr's command log, so a read is two
/// steps, each `herdr --machine <label> …` run through `HerdrCommand`:
///
/// 1. `plugin action invoke list --plugin yahyabedirhan.herdr-shipyard`
///    starts the action and answers with its log record's `log_id`;
/// 2. `plugin log list --plugin yahyabedirhan.herdr-shipyard` lists the
///    plugin's recent records; the one with that `log_id` holds the list
///    on its `stdout` once its `status` is no longer `running`. While it is,
///    the reader waits `waitInterval` and asks again, up to `waitAttempts` times.
///
/// The whole read races `timeout`, so a machine that doesn't answer
/// never holds up another, or the menu.
public struct RemotePingReader: Sendable {
    /// The herdr-shipyard plugin's id.
    public static let pluginID = "yahyabedirhan.herdr-shipyard"
    /// Its action that lists the machine's pings.
    public static let actionID = "list"
    /// How long one machine's whole read may take.
    public static let defaultTimeout: TimeInterval = 15

    /// Why a machine's pings couldn't be read, as a short reason the
    /// panel can show.
    public struct Failure: Error, Equatable, Sendable {
        public var reason: String
        public init(_ reason: String) { self.reason = reason }
    }

    private let herdr: HerdrCommand
    private let timeout: TimeInterval
    private let sleep: Sleep
    private let wait: Sleep
    private let waitInterval: TimeInterval
    private let waitAttempts: Int

    /// `sleep` times the whole read out; `wait` paces the asks while the
    /// action is still running.
    public init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        runner: any ShellRunning = ProcessShellRunner(),
        timeout: TimeInterval = RemotePingReader.defaultTimeout,
        sleep: @escaping Sleep = systemSleep,
        wait: @escaping Sleep = systemSleep,
        waitInterval: TimeInterval = 0.25,
        waitAttempts: Int = 20
    ) {
        herdr = HerdrCommand(
            home: home,
            pathEnvironment: pathEnvironment,
            isExecutable: isExecutable,
            runner: runner,
            timeout: timeout,
            sleep: sleep
        )
        self.timeout = timeout
        self.sleep = sleep
        self.wait = wait
        self.waitInterval = waitInterval
        self.waitAttempts = waitAttempts
    }

    /// The pings the machine `label` lists, each marked with its machine
    /// (`Ping.machine`), or why they couldn't be read.
    public func list(machine label: String) async -> Result<PingList, Failure> {
        let timeout = timeout, sleep = sleep
        return await withTaskGroup(of: Result<PingList, Failure>?.self) { group in
            group.addTask { await self.read(label) }
            group.addTask {
                guard (try? await sleep(timeout)) != nil else { return nil }
                return .failure(Failure("\(label) didn't answer in time"))
            }
            var first: Result<PingList, Failure>?
            for await result in group where first == nil {
                first = result
                if result != nil { group.cancelAll() }
            }
            return first ?? .failure(Failure("\(label) didn't answer in time"))
        }
    }

    private func read(_ label: String) async -> Result<PingList, Failure> {
        let invoked: [String: Any]
        switch await run(["plugin", "action", "invoke", Self.actionID, "--plugin", Self.pluginID], on: label) {
        case .failure(let failure): return .failure(failure)
        case .success(let result): invoked = result
        }
        guard let logID = (invoked["log"] as? [String: Any])?["log_id"] as? String else {
            return .failure(Failure("Herdr didn't say where \(label)'s ping list went"))
        }
        for attempt in 0..<max(1, waitAttempts) {
            if attempt > 0 {
                guard (try? await wait(waitInterval)) != nil else { return .failure(Failure("\(label) didn't answer in time")) }
            }
            let listed: [String: Any]
            switch await run(["plugin", "log", "list", "--plugin", Self.pluginID], on: label) {
            case .failure(let failure): return .failure(failure)
            case .success(let result): listed = result
            }
            let logs = listed["logs"] as? [[String: Any]] ?? []
            guard let record = logs.first(where: { $0["log_id"] as? String == logID }) else {
                return .failure(Failure("Herdr lost \(label)'s ping list"))
            }
            switch record["status"] as? String {
            case "running":
                continue
            case "succeeded":
                return decode(record["stdout"] as? String ?? "", machine: label)
            default:
                return .failure(Failure("shipyard on \(label) couldn't list its pings"))
            }
        }
        return .failure(Failure("\(label) is still listing its pings"))
    }

    /// The list `stdout` holds, its pings marked with `label`.
    private func decode(_ stdout: String, machine label: String) -> Result<PingList, Failure> {
        do {
            var list = try PingList.decode(stdout)
            list.pings = list.pings.map { ping in
                var ping = ping
                ping.machine = label
                return ping
            }
            return .success(list)
        } catch {
            return .failure(Failure(error.message(machine: label)))
        }
    }

    /// Runs `herdr --machine <label>` with `arguments`: its `result`, or
    /// why not. Every reason names the machine, as the panel shows it alone.
    private func run(_ arguments: [String], on label: String) async -> Result<[String: Any], Failure> {
        switch await herdr.run(arguments, on: label) {
        case .notFound: return .failure(Failure("Couldn't find herdr to reach \(label)"))
        case .couldNotRun: return .failure(Failure("Couldn't run herdr to reach \(label)"))
        case .timedOut: return .failure(Failure("\(label) didn't answer in time"))
        case .finished(let output):
            if output.status != 0, let refusal = HerdrCommand.refusal(output.output, machine: label) {
                return .failure(Failure(refusal))
            }
            return HerdrCommand.answer(output).mapError { error in
                switch error.code {
                case "server_not_running": Failure("Herdr isn't running, so \(label) can't be reached")
                default: Failure("Couldn't reach \(label) through Herdr" + (error.message.map { ": \($0)" } ?? ""))
                }
            }
        }
    }
}
