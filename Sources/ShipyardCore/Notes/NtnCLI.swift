import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Notion's CLI, `ntn`, as the HTTP transport the notes are read and
/// written through (ADR 0012): each request `NotionClient` sends runs
/// `ntn api` once, with ntn's own login, so the app keeps no Notion token.
/// ntn's exit code and error line come back as the status Notion gave:
/// exit 4 (logged out, no workspace, a token Notion stopped taking) is a
/// 401, exit 5 carries the API's status and code. No `ntn` to run throws
/// `NotionError.ntnMissing`.
///
/// An `.app` starts with an almost empty `PATH`, so the places ntn's
/// installer and Homebrew put it are tried first, `PATH` only after them.
public struct NtnCLI: HTTPTransport {
    /// What a finished run printed, and its exit status.
    public struct Output: Equatable, Sendable {
        public var status: Int32
        public var standardOutput: Data
        public var standardError: String

        public init(status: Int32, standardOutput: Data, standardError: String) {
            self.status = status
            self.standardOutput = standardOutput
            self.standardError = standardError
        }
    }

    /// Runs an executable with arguments and waits for it; `nil` when it
    /// couldn't be started.
    public typealias Run = @Sendable (_ executable: String, _ arguments: [String]) async -> Output?

    /// Where ntn is looked for, in order: its installer's `~/.local/bin`,
    /// then Homebrew's (Apple Silicon, then Intel).
    public static func knownPaths(home: String) -> [String] {
        ["\(home)/.local/bin/ntn", "/opt/homebrew/bin/ntn", "/usr/local/bin/ntn"]
    }

    private let home: String
    private let isExecutable: @Sendable (String) -> Bool
    private let pathEnvironment: String?
    private let run: Run

    public init(
        home: String = NSHomeDirectory(),
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        run: @escaping Run = NtnCLI.runProcess
    ) {
        self.home = home
        self.isExecutable = isExecutable
        self.pathEnvironment = pathEnvironment
        self.run = run
    }

    /// The first `ntn` found: the known paths, then each `PATH` directory.
    public static func locate(home: String, isExecutable: (String) -> Bool, pathEnvironment: String?) -> String? {
        if let known = knownPaths(home: home).first(where: isExecutable) { return known }
        guard let pathEnvironment else { return nil }
        for directory in pathEnvironment.split(separator: ":") {
            let candidate = directory.hasSuffix("/") ? "\(directory)ntn" : "\(directory)/ntn"
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url,
              let executable = Self.locate(home: home, isExecutable: isExecutable, pathEnvironment: pathEnvironment)
        else { throw NotionError.ntnMissing }
        guard let output = await run(executable, Self.arguments(for: request)) else {
            try Task.checkCancellation()
            throw NotionError.ntnMissing
        }
        try Task.checkCancellation()
        return Self.response(to: url, output)
    }

    static func arguments(for request: URLRequest) -> [String] {
        let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let path = String((components?.path ?? "").drop { $0 == "/" })
        var arguments = ["api", path]
        arguments += (components?.queryItems ?? []).map { "\($0.name)==\($0.value ?? "")" }
        arguments += ["-X", request.httpMethod ?? "GET"]
        arguments += ["--notion-version", request.value(forHTTPHeaderField: "Notion-Version") ?? NotionClient.version]
        if let body = request.httpBody {
            arguments += ["-d", String(decoding: body, as: UTF8.self)]
        }
        return arguments
    }

    static func response(to url: URL, _ output: Output) -> (Data, HTTPURLResponse) {
        let lines = output.standardError
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let status: Int
        var body = Data()
        switch output.status {
        case 0:
            status = 200
            body = output.standardOutput
        case 4:
            status = 401
        default:
            if output.status == 5, let failure = lines.lazy.compactMap(APIFailure.init).first {
                status = failure.status
                body = (try? JSONSerialization.data(withJSONObject: ["code": failure.code, "message": failure.message])) ?? Data()
            } else {
                let error = lines.first { $0.hasPrefix("error:") } ?? lines.first ?? "exit \(output.status)"
                status = runFailed
                body = (try? JSONSerialization.data(withJSONObject: ["message": "ntn: \(error)"])) ?? Data()
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }

    static let runFailed = 599

    private struct APIFailure {
        var status: Int
        var code: String
        var message: String

        init?(_ line: String) {
            guard let open = line.firstIndex(of: "("), let close = line[open...].firstIndex(of: ")") else { return nil }
            let words = line[line.index(after: open)..<close].split(separator: " ")
            guard let first = words.first, let status = Int(first), let last = words.last, words.count > 1 else { return nil }
            self.status = status
            code = String(last)
            message = line[line.index(after: close)...]
                .drop { $0 == ":" || $0 == " " }
                .trimmingCharacters(in: .whitespaces)
        }
    }

    /// How long one run may take before it's stopped: a request is a
    /// second or two, so this is ntn stuck (a prompt of its own, a stalled
    /// network), and the notes read moves on rather than waiting for good.
    public static let timeout: TimeInterval = 30

    static let timedOut: Int32 = 124

    /// Runs `ntn` with Foundation's `Process` (`processRunner`), stopped
    /// after `timeout`.
    public static let runProcess: Run = processRunner(timeout: timeout)

    /// Runs a program with Foundation's `Process`: standard input empty,
    /// since `ntn api` reads a request body from any standard input it's
    /// given and would wait for it; both outputs read before waiting, so a
    /// full pipe can't block it. A run past `timeout` is stopped and ends
    /// with exit `timedOut` and "error: didn't answer within …" at once,
    /// without waiting for its outputs to close, which a program it started
    /// may hold open. Cancelling the task stops the run, before or after
    /// its launch, and it ends with `nil`. A stopped run gets SIGTERM, then
    /// SIGKILL a second later, sent to its process group when it leads one,
    /// so a program it started stops with it.
    static func processRunner(timeout: TimeInterval) -> Run {
        { executable, arguments in
            let run = NtnRun(executable: executable, arguments: arguments)
            return await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    let answer = OneAnswer(continuation)
                    DispatchQueue.global(qos: .userInitiated).async {
                        answer.give(run.toEnd())
                    }
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        guard run.stop(.timedOut(after: timeout)) else { return }
                        answer.give(NtnRun.timedOutOutput(after: timeout))
                    }
                }
            } onCancel: {
                run.stop(.cancelled)
            }
        }
    }
}

/// A continuation resumed by the first of the run's end and its timeout.
private final class OneAnswer: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NtnCLI.Output?, Never>?

    init(_ continuation: CheckedContinuation<NtnCLI.Output?, Never>) {
        self.continuation = continuation
    }

    func give(_ output: NtnCLI.Output?) {
        lock.lock()
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume(returning: output)
    }
}

private final class NtnRun: @unchecked Sendable {
    enum Stop {
        case cancelled
        case timedOut(after: TimeInterval)
    }

    private static let killDelay: TimeInterval = 1

    private let lock = NSLock()
    private let process = Process()
    private let output = Pipe()
    private let error = Pipe()
    private var stopped: Stop?
    private var errorData = Data()
    private var ended = false

    init(executable: String, arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = error
        // Linux's Foundation closes a child's other descriptors only up to
        // the highest one open when it starts the launch, so a pipe made
        // meanwhile would leak into a program another run launches.
        for pipe in [output, error] {
            for handle in [pipe.fileHandleForReading, pipe.fileHandleForWriting] {
                _ = fcntl(handle.fileDescriptor, F_SETFD, FD_CLOEXEC)
            }
        }
    }

    func toEnd() -> NtnCLI.Output? {
        guard launch() else { return nil }
        let errorRead = DispatchGroup()
        errorRead.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            self.errorData = self.error.fileHandleForReading.readDataToEndOfFile()
            errorRead.leave()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        errorRead.wait()
        process.waitUntilExit()
        let stopped = locked {
            ended = true
            return self.stopped
        }
        switch stopped {
        case .cancelled:
            return nil
        case .timedOut(let seconds):
            return Self.timedOutOutput(after: seconds)
        case nil:
            return NtnCLI.Output(status: process.terminationStatus, standardOutput: data, standardError: String(decoding: errorData, as: UTF8.self))
        }
    }

    static func timedOutOutput(after seconds: TimeInterval) -> NtnCLI.Output {
        NtnCLI.Output(status: NtnCLI.timedOut, standardOutput: Data(), standardError: "error: didn't answer within \(Int(seconds)) seconds")
    }

    /// Stops the run for `reason`; false when it had already ended or
    /// been stopped.
    @discardableResult
    func stop(_ reason: Stop) -> Bool {
        let pid: pid_t?? = locked {
            guard stopped == nil, !ended else { return nil }
            stopped = reason
            return .some(process.isRunning ? process.processIdentifier : nil)
        }
        guard let pid else { return false }
        if let pid {
            let target = getpgid(pid) == pid ? -pid : pid
            kill(target, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + Self.killDelay) {
                kill(target, SIGKILL)
            }
        }
        return true
    }

    private func launch() -> Bool {
        locked {
            guard stopped == nil else { return false }
            do {
                try process.run()
                return true
            } catch {
                return false
            }
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
