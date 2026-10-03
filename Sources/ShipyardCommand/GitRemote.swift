import Foundation

/// Reads a folder's git `origin` remote. The seam between a command and
/// spawning `git`, so tests use a fake working folder.
public protocol GitRemoteLookup: Sendable {
    /// The URL of `origin` for the repository `folder` is in, as git prints
    /// it; `nil` when `folder` isn't in a git repository, has no `origin`,
    /// or git can't be run.
    func origin(in folder: URL) -> String?
}

/// Asks `git` itself (`git -C <folder> remote get-url origin`), found on
/// `PATH` as the agent's terminal has it, so worktrees, submodules and
/// `url.<base>.insteadOf` read as git reads them.
public struct GitCLI: GitRemoteLookup {
    private let run: ProgramRun

    public init(run: @escaping ProgramRun = ProgramRunner.process) {
        self.run = run
    }

    public func origin(in folder: URL) -> String? {
        guard let output = run("/usr/bin/env", ["git", "-C", folder.path, "remote", "get-url", "origin"]),
              output.status == 0
        else { return nil }
        let url = output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        return url.isEmpty ? nil : url
    }
}

/// A git remote's URL as the repository it names, `owner/name`.
public enum GitRemote {
    /// The `owner/name` path of a remote on a host, without a trailing
    /// `.git`: `https://github.com/owner/name.git`,
    /// `git@github.com:owner/name.git` and `ssh://git@github.com/owner/name`
    /// all read `owner/name`. `nil` for a local path or `file://` remote,
    /// and for a path that isn't exactly `owner/name`.
    public static func repository(fromURL url: String) -> String? {
        let text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var path: Substring
        if let scheme = text.range(of: "://") {
            // `scheme://[user@]host[:port]/path`: drop up to the host's end.
            guard text[..<scheme.lowerBound].lowercased() != "file" else { return nil }
            let rest = text[scheme.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            path = rest[rest.index(after: slash)...]
        } else if let colon = text.firstIndex(of: ":"), colon != text.startIndex, !text[..<colon].contains("/") {
            // scp-like `[user@]host:path`.
            path = text[text.index(after: colon)...]
        } else {
            return nil
        }
        while path.hasSuffix("/") { path.removeLast() }
        if path.hasSuffix(".git") { path.removeLast(4) }
        let slug = String(path)
        return isRepositorySlug(slug) ? slug : nil
    }

    /// Whether `slug` is a repository as `owner/name`: a GitHub login
    /// (letters, digits, hyphens) and a repository name (letters, digits,
    /// `-`, `_`, `.`). The configuration's selectors and `--repo` both read
    /// repositories by it.
    public static func isRepositorySlug(_ slug: String) -> Bool {
        let parts = slug.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        let owner = parts[0], name = parts[1]
        let ownerOK = !owner.isEmpty && owner.unicodeScalars.allSatisfy { $0.isASCIIAlphanumeric || $0 == "-" }
        let nameOK = !name.isEmpty && name != "." && name != ".."
            && name.unicodeScalars.allSatisfy { $0.isASCIIAlphanumeric || $0 == "-" || $0 == "_" || $0 == "." }
        return ownerOK && nameOK
    }

    /// Why a working folder names no repository, as the error line says it.
    public struct NoRepository: Error, Equatable, Sendable {
        public var message: String
    }

    /// The repository of the working folder `url`: its git remote
    /// `origin`, as `owner/name`, read through `git`. When there's none,
    /// why, naming what was to be filed by it (`subject`: "ping", "notice").
    public static func workingRepository(folder url: URL, git: any GitRemoteLookup, filing subject: String) -> Result<String, NoRepository> {
        guard let origin = git.origin(in: url) else {
            return .failure(NoRepository(message: "the working folder (\(url.path)) isn't a git repository with a remote `origin` to file the \(subject) by"))
        }
        guard let slug = repository(fromURL: origin) else {
            return .failure(NoRepository(message: "the working folder's remote `origin` (\(origin)) doesn't name a repository as owner/name"))
        }
        return .success(slug)
    }
}

private extension Unicode.Scalar {
    var isASCIIAlphanumeric: Bool {
        switch self {
        case "A"..."Z", "a"..."z", "0"..."9": true
        default: false
        }
    }
}
