import Foundation

/// What a project's repository selectors stand for right now.
public struct ResolvedRepositories: Equatable, Sendable {
    /// `owner/name`, each once (ignoring case), in the order the selectors
    /// bring them in: a single repository as the file spells it, a looked-up
    /// one as GitHub does.
    public var repositories: [String]
    /// One per selector that couldn't be resolved, named after the selector
    /// (`ghost-org/*`): an owner that doesn't exist or can't be seen, or a
    /// failed lookup with no earlier list to fall back on.
    public var errors: [RepositoryError]

    public init(repositories: [String] = [], errors: [RepositoryError] = []) {
        self.repositories = repositories
        self.errors = errors
    }
}

/// Turns repository selectors into repositories: looks each group and
/// `owner/*` up on GitHub at most once an hour (or at once, when forced),
/// leaves out archived repositories and forks as each project says, and
/// merges them with the single repositories, each once.
///
/// The lists are memory, not app state: a relaunch looks everything up again.
@MainActor
public final class RepositoryResolver {
    /// How long a looked-up list is used before it's looked up again.
    public static let interval: TimeInterval = 3600

    /// One lookup's latest result.
    private struct Entry {
        /// The last list GitHub gave; `nil` before one arrived, or when the
        /// owner can't be seen.
        var repositories: [RepoSummary]?
        /// When that answer arrived; `nil` before any did.
        var answeredAt: Date?
        /// Why the latest lookup failed, or that the owner can't be seen.
        var error: RepositoryError.Kind?
        var message = ""

        /// Whether a failed lookup is tried again at the next refresh rather
        /// than an hour later: an owner that can't be seen was an answer.
        var retries: Bool { error != nil && error != .notFound }
    }

    private var entries: [RepositoryLookup: Entry] = [:]

    public init() {}

    /// Forgets every list, as a relaunch does (after signing out: another
    /// account sees other repositories).
    public func reset() {
        entries = [:]
    }

    /// Each project's repositories, by project name. Looks up every group
    /// and `owner/*` the projects use that wasn't answered within the hour,
    /// or failed last time, or all of them when `force`; each lookup once,
    /// however many projects share it.
    ///
    /// A failed lookup keeps the last list; with none, the selector gets an
    /// error. A rejected token (`.unauthorized`) and cancellation are thrown,
    /// so the refresh stops.
    public func resolve(
        _ projects: [ProjectSettings],
        force: Bool,
        at now: Date,
        lookup: (RepositoryLookup) async throws -> [RepoSummary]?
    ) async throws -> [String: ResolvedRepositories] {
        var used: [RepositoryLookup] = []
        for project in projects {
            for selector in project.repositories {
                if let wanted = selector.lookup, !used.contains(wanted) { used.append(wanted) }
            }
        }
        entries = entries.filter { used.contains($0.key) }

        for wanted in used {
            var entry = entries[wanted] ?? Entry()
            let fresh = entry.answeredAt.map { now.timeIntervalSince($0) < Self.interval } ?? false
            guard force || !fresh || entry.retries else { continue }
            do {
                if let found = try await lookup(wanted) {
                    entry = Entry(repositories: found, answeredAt: now)
                } else {
                    entry = Entry(repositories: nil, answeredAt: now, error: .notFound)
                }
            } catch GitHubError.unauthorized {
                throw GitHubError.unauthorized
            } catch let error as CancellationError {
                throw error
            } catch {
                entry.error = .other
                entry.message = Self.reason(error)
            }
            entries[wanted] = entry
        }

        var resolved: [String: ResolvedRepositories] = [:]
        for project in projects {
            resolved[project.name] = resolution(of: project)
        }
        return resolved
    }

    /// The project's selectors with the lists at hand.
    private func resolution(of project: ProjectSettings) -> ResolvedRepositories {
        var result = ResolvedRepositories()
        var seen = Set<String>()
        func add(_ slug: String) {
            if seen.insert(slug.lowercased()).inserted { result.repositories.append(slug) }
        }
        for selector in project.repositories {
            guard let wanted = selector.lookup else {
                // Named on its own: always listed, archived or a fork.
                selector.slug.map(add)
                continue
            }
            guard let entry = entries[wanted] else { continue }
            if let repositories = entry.repositories {
                for repository in repositories
                where (project.archived || !repository.isArchived) && (project.forks || !repository.isFork) {
                    add(repository.slug)
                }
            } else if let kind = entry.error {
                let name = selector.description
                result.errors.append(RepositoryError(
                    repository: name,
                    kind: kind,
                    message: kind == .notFound ? "GitHub has no owner `\(name.dropLast(2))`, or it can't be seen"
                        : "couldn't list its repositories (\(entry.message))"
                ))
            }
        }
        return result
    }

    /// A lookup's failure in a few words, for its error row.
    private static func reason(_ error: any Error) -> String {
        switch error as? GitHubError {
        case .rateLimited: "the rate limit ran out"
        case .secondaryLimit: "GitHub asked to slow down"
        case .network: "GitHub can't be reached"
        case .http(let status): "HTTP \(status)"
        case .graphQL(let message): message
        default: "GitHub's answer couldn't be read"
        }
    }
}
