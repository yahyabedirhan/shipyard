import Foundation
import Observation

/// What the CLI link finds at a path, without following a symbolic link.
public enum LinkEntry: Equatable, Sendable {
    case none
    case link(destination: String)
    case other
}

/// The few file operations the CLI link needs, so tests can fail one (no
/// permission) without changing a real folder's permissions.
public protocol LinkFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func entry(at url: URL) -> LinkEntry
    func createDirectory(at url: URL) throws
    func createSymbolicLink(at url: URL, to destination: URL) throws
}

/// The real file system, through `FileManager`.
public struct FileManagerLinkFileSystem: LinkFileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func entry(at url: URL) -> LinkEntry {
        let manager = FileManager.default
        guard let attributes = try? manager.attributesOfItem(atPath: url.path) else { return .none }
        guard attributes[.type] as? FileAttributeType == .typeSymbolicLink,
              let destination = try? manager.destinationOfSymbolicLink(atPath: url.path)
        else { return .other }
        return .link(destination: destination)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func createSymbolicLink(at url: URL, to destination: URL) throws {
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
    }
}

/// Puts the app's bundled `shipyard` CLI on the user's PATH by linking
/// `~/.local/bin/shipyard` to it, as the panel offers in onboarding and from
/// its menu. It never replaces anything: a link already pointing at this
/// app's CLI is left alone, and anything else at that path, or a folder it
/// can't write to, leaves the link to the user, with `command` to run. A
/// link that's left pointing at a CLI that's gone (an older copy of the
/// app, moved or deleted) is in the way too, so the user sees the command
/// that fixes it. A translocated copy of the app links nothing.
@MainActor
@Observable
public final class CLILink {
    /// What the link looks like now.
    public enum State: Equatable, Sendable {
        case unlinked
        case linked
        case occupied(destination: String?)
        case failed(String)
        case missingCLI
        /// macOS runs this copy from a temporary, read-only path (App
        /// Translocation: the app was opened where it was downloaded, not
        /// moved to Applications), so a link would point at a path that's
        /// gone after it quits. Moving the app fixes it.
        case translocated
    }

    nonisolated public static let displayPath = "~/.local/bin/shipyard"

    nonisolated public static func bundledCLI(in bundle: URL) -> URL {
        bundle.appendingPathComponent("Contents/Helpers/shipyard", isDirectory: false)
    }

    /// Where things are now; the panel draws it. `check()` refreshes it.
    public private(set) var state: State = .unlinked

    /// The app's CLI, the link's destination.
    public let cli: URL
    /// `~/.local/bin/shipyard` under `home`.
    public let link: URL
    private let fileSystem: LinkFileSystem

    public init(cli: URL, home: URL, fileSystem: LinkFileSystem = FileManagerLinkFileSystem()) {
        self.cli = cli
        self.link = home.appendingPathComponent(".local/bin/shipyard", isDirectory: false)
        self.fileSystem = fileSystem
        state = inspect()
    }

    /// The command that makes the link by hand, replacing whatever is there.
    public var command: String {
        "mkdir -p ~/.local/bin && ln -sf \(Self.shellQuoted(cli.path)) \(Self.displayPath)"
    }

    /// Looks again: the user may have made or removed the link by hand.
    public func check() {
        state = inspect()
    }

    /// Makes the link when nothing is in the way; otherwise just says what's there.
    public func makeLink() {
        let found = inspect()
        guard found == .unlinked else {
            state = found
            return
        }
        do {
            try fileSystem.createDirectory(at: link.deletingLastPathComponent())
            try fileSystem.createSymbolicLink(at: link, to: cli)
            state = inspect()
        } catch {
            let now = inspect()
            state = now == .unlinked ? .failed(error.localizedDescription) : now
        }
    }

    /// Whether `cli` is inside a translocated copy of the app, which macOS
    /// runs from a temporary path under `/AppTranslocation/`.
    nonisolated public static func isTranslocated(_ cli: URL) -> Bool {
        cli.standardizedFileURL.path.contains("/AppTranslocation/")
    }

    private func inspect() -> State {
        guard !Self.isTranslocated(cli) else { return .translocated }
        guard fileSystem.fileExists(at: cli) else { return .missingCLI }
        switch fileSystem.entry(at: link) {
        case .none:
            return .unlinked
        case .other:
            return .occupied(destination: nil)
        case .link(let destination):
            let directory = link.deletingLastPathComponent()
            let target = URL(fileURLWithPath: destination, relativeTo: directory).standardizedFileURL
            return target.path == cli.standardizedFileURL.path ? .linked : .occupied(destination: destination)
        }
    }

    nonisolated static func shellQuoted(_ path: String) -> String {
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+")
        if !path.isEmpty, path.unicodeScalars.allSatisfy(plain.contains) { return path }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
