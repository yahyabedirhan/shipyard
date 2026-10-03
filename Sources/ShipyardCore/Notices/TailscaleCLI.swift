import Foundation
import ShipyardCommand

/// Learns the Mac's own Tailscale login from `tailscale status --json`:
/// the login of the user its own device (`Self`) belongs to, while
/// Tailscale runs. Asked for each notice from the tailnet, so a change of
/// account is followed and a Tailscale that stopped refuses them.
///
/// An `.app` starts with an almost empty `PATH`, so the places Tailscale's
/// variants put their command are tried first: the Standalone and App Store
/// apps' `/usr/local/bin/tailscale` (once the user installs it from the
/// app's settings) and the app's own binary, which acts as the command, and
/// Homebrew's open-source build; `PATH` only after them.
public struct TailscaleCLI: TailnetIdentity {
    public static let knownPaths = [
        "/usr/local/bin/tailscale",
        "/Applications/Tailscale.app/Contents/MacOS/Tailscale",
        "/opt/homebrew/bin/tailscale",
    ]

    /// How long `tailscale status` may take before the notice is refused.
    public static let timeout: Duration = .seconds(2)

    private let isExecutable: @Sendable (String) -> Bool
    private let pathEnvironment: String?
    private let run: ProgramRun

    public init(
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        run: @escaping ProgramRun = ProgramRunner.process
    ) {
        self.isExecutable = isExecutable
        self.pathEnvironment = pathEnvironment
        self.run = run
    }

    public func ownLogin() async -> Result<String, TailnetLoginUnknown> {
        guard let executable = locate() else { return .failure(TailnetLoginUnknown("the tailscale command wasn't found")) }
        let run = run
        // Off the main actor, and never waited on past the timeout: a
        // Tailscale that hangs refuses the notice rather than holding it.
        let output = await Self.firstOf(
            { run(executable, ["status", "--json"]) },
            orAfter: Self.timeout
        )
        guard let output else {
            return .failure(TailnetLoginUnknown("`tailscale status` didn't answer, or couldn't be run"))
        }
        guard output.status == 0 else {
            return .failure(TailnetLoginUnknown("`tailscale status` failed (exit \(output.status))"))
        }
        return Self.login(fromStatus: Data(output.standardOutput.utf8))
    }

    /// The first `tailscale` found: the known paths, then each `PATH` directory.
    func locate() -> String? {
        if let known = Self.knownPaths.first(where: isExecutable) { return known }
        for directory in (pathEnvironment ?? "").split(separator: ":") {
            let candidate = directory.hasSuffix("/") ? "\(directory)tailscale" : "\(directory)/tailscale"
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    /// The login in `tailscale status --json`'s output: `User[Self.UserID].LoginName`,
    /// when `BackendState` is `Running`.
    static func login(fromStatus data: Data) -> Result<String, TailnetLoginUnknown> {
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else {
            return .failure(TailnetLoginUnknown("`tailscale status --json` printed something it couldn't read"))
        }
        switch status.backendState {
        case "Running": break
        case "Stopped": return .failure(TailnetLoginUnknown("Tailscale is stopped"))
        case "NeedsLogin": return .failure(TailnetLoginUnknown("Tailscale needs you to log in"))
        case let state: return .failure(TailnetLoginUnknown("Tailscale isn't running (\(state ?? "no state"))"))
        }
        guard let id = status.selfNode?.userID,
              let login = status.users?[String(id)]?.loginName,
              !login.isEmpty
        else { return .failure(TailnetLoginUnknown("`tailscale status` named no login for this Mac")) }
        return .success(login)
    }

    /// The part of `tailscale status --json` the login is in.
    private struct Status: Decodable {
        var backendState: String?
        var selfNode: Node?
        var users: [String: User]?

        struct Node: Decodable {
            var userID: Int64?
            enum CodingKeys: String, CodingKey { case userID = "UserID" }
        }

        struct User: Decodable {
            var loginName: String?
            enum CodingKeys: String, CodingKey { case loginName = "LoginName" }
        }

        enum CodingKeys: String, CodingKey {
            case backendState = "BackendState"
            case selfNode = "Self"
            case users = "User"
        }
    }

    /// `body`'s result, run off the caller's actor, or `nil` once `limit`
    /// passes first; `body` is then left to finish on its own.
    private static func firstOf(
        _ body: @escaping @Sendable () -> CommandOutput?,
        orAfter limit: Duration
    ) async -> CommandOutput? {
        let once = Once()
        return await withCheckedContinuation { continuation in
            once.set(continuation)
            Task.detached { once.resume(body()) }
            Task.detached {
                try? await Task.sleep(for: limit)
                once.resume(nil)
            }
        }
    }

    /// A continuation resumed by whichever comes first, once.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<CommandOutput?, Never>?
        private var result: CommandOutput??

        func set(_ continuation: CheckedContinuation<CommandOutput?, Never>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func resume(_ value: CommandOutput?) {
            lock.lock()
            guard result == nil else { return lock.unlock() }
            result = .some(value)
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
        }
    }
}
