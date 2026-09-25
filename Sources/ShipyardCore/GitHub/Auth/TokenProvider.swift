import Foundation

/// Where the token shipyard signed in with came from.
public enum TokenSource: Equatable, Sendable {
    /// The token store (the Keychain in the app): the user signed in with the
    /// device flow.
    case tokenStore
    /// `gh auth token`: the user is signed in to the GitHub CLI.
    case gh
}

/// A token and where it came from.
public struct FoundToken: Equatable, Sendable {
    public var value: String
    public var source: TokenSource

    public init(value: String, source: TokenSource) {
        self.value = value
        self.source = source
    }
}

/// Finds the token to sign in with: the token store first (the user signed
/// in explicitly), then the GitHub CLI, else none.
public struct TokenProvider: Sendable {
    private let store: any TokenStore
    private let gh: any GhTokenLookup

    public init(store: any TokenStore, gh: any GhTokenLookup) {
        self.store = store
        self.gh = gh
    }

    /// The token to use, or `nil` when neither source has one. A token store
    /// that can't be read counts as empty, so `gh` still gets its turn.
    public func current() -> FoundToken? {
        if let token = try? store.token(), !token.isEmpty {
            return FoundToken(value: token, source: .tokenStore)
        }
        if let token = gh.token(), !token.isEmpty {
            return FoundToken(value: token, source: .gh)
        }
        return nil
    }
}

/// Asks the GitHub CLI for its token. The seam between the core and spawning
/// `gh`, so tests use a fake lookup.
public protocol GhTokenLookup: Sendable {
    /// `gh`'s token, or `nil` when `gh` isn't installed or isn't signed in.
    func token() -> String?
}

/// The output of a finished command.
public struct CommandOutput: Equatable, Sendable {
    public var status: Int32
    public var standardOutput: String

    public init(status: Int32, standardOutput: String) {
        self.status = status
        self.standardOutput = standardOutput
    }
}

/// Finds `gh` and runs `gh auth token`.
///
/// An `.app` starts with an almost empty `PATH`, so the Homebrew locations
/// are tried first (Apple Silicon, then Intel) and `PATH` only after them.
public struct GhCLI: GhTokenLookup {
    /// Runs an executable with arguments and waits for it; `nil` when it
    /// couldn't be started.
    public typealias Run = @Sendable (_ executable: String, _ arguments: [String]) -> CommandOutput?

    /// Where Homebrew installs `gh`, in the order they're tried.
    public static let knownPaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
    ]

    private let isExecutable: @Sendable (String) -> Bool
    private let pathEnvironment: String?
    private let run: Run

    public init(
        isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        pathEnvironment: String? = ProcessInfo.processInfo.environment["PATH"],
        run: @escaping Run = GhCLI.runProcess
    ) {
        self.isExecutable = isExecutable
        self.pathEnvironment = pathEnvironment
        self.run = run
    }

    /// The first `gh` found: the known paths, then each `PATH` directory.
    public static func locate(isExecutable: (String) -> Bool, pathEnvironment: String?) -> String? {
        if let known = knownPaths.first(where: isExecutable) { return known }
        guard let pathEnvironment else { return nil }
        for directory in pathEnvironment.split(separator: ":") {
            let candidate = directory.hasSuffix("/") ? "\(directory)gh" : "\(directory)/gh"
            if isExecutable(candidate) { return candidate }
        }
        return nil
    }

    public func token() -> String? {
        guard let executable = Self.locate(isExecutable: isExecutable, pathEnvironment: pathEnvironment),
              let output = run(executable, ["auth", "token"]),
              output.status == 0
        else { return nil }
        let token = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    /// Runs the command with Foundation's `Process`, reading its output
    /// before waiting so a full pipe can't block it.
    public static let runProcess: Run = { executable, arguments in
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
