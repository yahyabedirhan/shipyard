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

    /// `ntn api`'s arguments for `request`: its path under the API host
    /// (`v1/search`), each query item as `name==value`, the method, the
    /// `Notion-Version` and the JSON body as `-d`.
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

    /// The HTTP answer a run stands for: exit 0 is a 200 with what ntn
    /// printed; exit 4 a 401; exit 5 the status and code in ntn's error
    /// line, with its message as Notion's error body. Any other exit, or an
    /// error line without a status, is a 599 `NotionClient` reads as the
    /// run's own failure.
    static func response(to url: URL, _ output: Output) -> (Data, HTTPURLResponse) {
        let error = output.standardError
            .split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? "exit \(output.status)"
        let status: Int
        var body = Data()
        switch output.status {
        case 0:
            status = 200
            body = output.standardOutput
        case 4:
            status = 401
        default:
            if output.status == 5, let failure = APIFailure(error) {
                status = failure.status
                body = (try? JSONSerialization.data(withJSONObject: ["code": failure.code, "message": failure.message])) ?? Data()
            } else {
                status = runFailed
                body = (try? JSONSerialization.data(withJSONObject: ["message": "ntn: \(error)"])) ?? Data()
            }
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
        return (body, response)
    }

    /// The status `response` gives a run that failed before Notion
    /// answered (offline, ntn's own error): `NotionClient` reads it as
    /// `NotionError.network`.
    static let runFailed = 599

    /// ntn's line for an API error: "error: Public API request failed
    /// (404 Not Found object_not_found): Could not find page …".
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

    /// Runs `ntn` with Foundation's `Process`: standard input empty, since
    /// `ntn api` reads a request body from any standard input it's given
    /// and would wait for it; both outputs read before waiting, so a full
    /// pipe can't block it. Cancelling the task stops the run.
    public static let runProcess: Run = { executable, arguments in
        let run = NtnRun(executable: executable, arguments: arguments)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: run.toEnd())
                }
            }
        } onCancel: {
            run.terminate()
        }
    }
}

/// One `ntn` run that another thread can stop.
private final class NtnRun: @unchecked Sendable {
    private let process = Process()
    private let output = Pipe()
    private let error = Pipe()
    /// What ntn printed on standard error, read on a thread of its own.
    private var errorData = Data()

    init(executable: String, arguments: [String]) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = error
    }

    /// Runs ntn and waits for it; `nil` when it couldn't start.
    func toEnd() -> NtnCLI.Output? {
        do {
            try process.run()
        } catch {
            return nil
        }
        // Standard error is read on its own thread, so neither pipe can fill while the other is read.
        let errorRead = DispatchGroup()
        errorRead.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            self.errorData = self.error.fileHandleForReading.readDataToEndOfFile()
            errorRead.leave()
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        errorRead.wait()
        process.waitUntilExit()
        return NtnCLI.Output(status: process.terminationStatus, standardOutput: data, standardError: String(decoding: errorData, as: UTF8.self))
    }

    func terminate() {
        if process.isRunning { process.terminate() }
    }
}
