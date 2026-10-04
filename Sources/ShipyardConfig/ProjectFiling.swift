import Foundation
import ShipyardCommand
import ShipyardPings

/// The filing on the Mac (ADR 0006): a ping goes under the projects of
/// `config.toml` that watch its repository, one the configuration names as
/// `owner/name` or one in the project's list as the app last resolved it,
/// or under the one `--project` names; one nothing takes is refused, with
/// the projects listed, as is one every project it goes under hides
/// (`pings.show = false`). The configuration is read only when a ping is
/// filed, so `withdraw` and `list` never read it; a file that doesn't read
/// fails the ping with its first problem, since the CLI has no last valid
/// configuration to fall back on. A ping stays until seen, with no default
/// action.
public struct ProjectFiling: PingFiling {
    private let configuration: @Sendable () -> Result<Configuration, CommandResult>
    private let resolved: @Sendable () -> [String: [String]]

    /// Files against `configuration` and `resolved` (each project's
    /// repositories as the app last resolved them, by name), each read when
    /// a ping is filed.
    private init(
        configuration: @escaping @Sendable () -> Result<Configuration, CommandResult>,
        resolved: @escaping @Sendable () -> [String: [String]]
    ) {
        self.configuration = configuration
        self.resolved = resolved
    }

    /// Files against the configuration file at `configURL` (a missing file
    /// is no projects) and the lists in `repositories`.
    public init(configURL: URL, repositories: ResolvedRepositoriesStore) {
        self.init(configuration: { Self.readConfiguration(at: configURL) }, resolved: { repositories.load() })
    }

    public func file(_ target: FilingTarget, whenNoProject: NoProject) -> Result<Filing, CommandResult> {
        let configuration: Configuration
        switch self.configuration() {
        case .success(let read): configuration = read
        case .failure(let failure): return .failure(failure)
        }
        let names = configuration.projects.map(\.name)
        let slug: String
        switch target {
        case .project(let project):
            guard names.contains(project) else {
                return .failure(.failed("shipyard ping: no project is named `\(project)`; \(Self.listing(names))"))
            }
            return shown(Filing(projects: [project], repository: nil), configuration: configuration, whenNoProject: whenNoProject)
        case .none(let why):
            guard whenNoProject == .keepUnfiled else {
                return .failure(.failed("shipyard ping: \(why); pass --repo <owner/name> or --project <name>; \(Self.listing(names))"))
            }
            return .success(Filing(projects: [], repository: nil))
        case .repository(let repository):
            slug = repository
        }
        let watching = Self.watchers(of: slug, configuration: configuration, resolved: resolved())
        if let first = watching.first {
            return shown(Filing(projects: watching.map(\.project), repository: first.spelling), configuration: configuration, whenNoProject: whenNoProject)
        }
        guard whenNoProject == .keepUnfiled else {
            return .failure(.failed("shipyard ping: no project watches `\(slug)`; pass --project <name> to file it under one; \(Self.listing(names))"))
        }
        return .success(Filing(projects: [], repository: slug))
    }

    /// `filing`, unless every project it's under hides pings
    /// (`pings.show = false`) and a ping no project takes is refused: the
    /// agent would believe a ping the user never sees reached them, so it's
    /// refused, naming those projects and the ones that show pings. A ping
    /// that's kept unfiled instead (`herdr-event`'s) is filed as it is,
    /// hidden as the configuration asks, since a refusal would reach no one.
    private func shown(_ filing: Filing, configuration: Configuration, whenNoProject: NoProject) -> Result<Filing, CommandResult> {
        guard whenNoProject == .refuse else { return .success(filing) }
        let showing = configuration.projects.filter { configuration.settings(for: $0).pings.show }.map(\.name)
        let hiding = filing.projects.filter { !showing.contains($0) }
        guard hiding.count == filing.projects.count else { return .success(filing) }
        let named = hiding.map { "`\($0)`" }.joined(separator: ", ")
        let hide = hiding.count == 1 ? "hides" : "hide"
        let wayOut = showing.isEmpty ? "no project shows pings"
            : "pass --project <name> to file it under one that shows them; the projects that show pings are " + showing.map { "`\($0)`" }.joined(separator: ", ")
        return .failure(.failed("shipyard ping: no project shows the ping: \(named) \(hide) pings (pings.show = false); \(wayOut)"))
    }

    public func expiry(sentAt sent: Date) -> Date? { nil }

    public func defaultAction(_ environment: CommandEnvironment) -> PingAction? { nil }

    /// `ping`, sent on a machine without the app and listed by the Mac
    /// (`Ping.machine`), filed as a local one is against `configuration`
    /// and `resolved`: under every project that watches its repository,
    /// with the repository spelled as the first of them knows it. One that
    /// names projects (`--project`) keeps them; a name the configuration
    /// lacks lists it by its machine (`Listing`), as does a repository no
    /// project watches.
    public static func filed(remote ping: Ping, configuration: Configuration, resolved: [String: [String]]) -> Ping {
        guard ping.projects.isEmpty, let slug = ping.repository else { return ping }
        let watching = watchers(of: slug, configuration: configuration, resolved: resolved)
        guard let first = watching.first else { return ping }
        var filed = ping
        filed.projects = watching.map(\.project)
        filed.repository = first.spelling
        return filed
    }

    /// The projects that watch `slug`, in the configuration's order, each
    /// with the repository spelled as that project knows it (GitHub's
    /// spelling once resolved). Repositories match ignoring case, as
    /// GitHub's names do. The app files an agent's notice by it too.
    public static func watchers(
        of slug: String,
        configuration: Configuration,
        resolved: [String: [String]]
    ) -> [(project: String, spelling: String)] {
        configuration.projects.compactMap { project in
            let named = project.repositories.compactMap(\.slug)
            let known = named + (resolved[project.name] ?? [])
            guard let spelling = known.first(where: { $0.caseInsensitiveCompare(slug) == .orderedSame }) else { return nil }
            return (project.name, spelling)
        }
    }

    /// The projects a ping (or the app, a notice) can be filed under, for an error.
    public static func listing(_ names: [String]) -> String {
        names.isEmpty ? "config.toml has no projects yet"
            : "the projects are " + names.map { "`\($0)`" }.joined(separator: ", ")
    }

    /// The configuration file as the app reads it, or why it can't be used:
    /// the app falls back on the last file that read, but the CLI has none,
    /// so it says what to fix. A missing file is no projects.
    static func readConfiguration(at url: URL) -> Result<Configuration, CommandResult> {
        guard let data = try? Data(contentsOf: url) else { return .success(Configuration()) }
        do {
            return .success(try Configuration.decode(data).configuration)
        } catch {
            return .failure(.failed("shipyard: config.toml doesn't read (\(error.issues[0])); fix it, then try again"))
        }
    }
}
