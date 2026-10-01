import Foundation

/// `shipyard ping`: reads its arguments, files the ping under the projects
/// that watch its repository (or under the one `--project` names), saves it
/// to the ping store and prints its id. Pure apart from the store and the
/// git remote it reads through `CommandEnvironment`, so tests call it as a
/// function; the `shipyard` executable only prints what it returns.
///
/// Its arguments are read as a subcommand first (so `withdraw` can join),
/// then as a title and flags, in any order.
public enum PingCommand {
    /// What `shipyard ping --help` prints.
    public static let usageText = """
        usage: shipyard ping "<title>" [--repo <owner/name> | --project <name>]

        Sends the user a ping: it's listed under the projects that watch the
        repository of the working folder (its git remote `origin`), needs
        their attention until they click it, and prints its id.

          --repo <owner/name>  file it by this repository instead of the working folder's
          --project <name>     file it under this project (its name in config.toml) only

        """

    /// The usage line errors point at.
    static let usageLine = "shipyard ping \"<title>\" [--repo <owner/name> | --project <name>]"

    /// Sends a ping with `arguments` (those after `ping`), sent at `now`.
    /// Without `--project` it's filed under every project of `configuration`
    /// that watches its repository: one the configuration names as
    /// `owner/name`, or one in the project's list in `resolved` (each
    /// project's repositories as the app last resolved them, by name).
    /// `newID` makes the id; one already stored is drawn again.
    public static func run(
        _ arguments: [String],
        environment: CommandEnvironment,
        configuration: Configuration,
        resolved: [String: [String]] = [:],
        store: PingStore,
        now: Date,
        newID: () -> String = Ping.newID
    ) -> CommandResult {
        let request: Request
        switch Request.parse(arguments) {
        case .success(let parsed): request = parsed
        case .failure(let error): return .usage("shipyard ping: \(error.message)")
        }
        let names = configuration.projects.map(\.name)
        let projects: [String]
        var repository: String?
        if let project = request.project {
            guard names.contains(project) else {
                return .failed("shipyard ping: no project is named `\(project)`; \(listing(names))")
            }
            projects = [project]
        } else {
            let slug: String
            if let named = request.repository {
                slug = named
            } else {
                switch workingRepository(environment) {
                case .success(let found): slug = found
                case .failure(let reason): return .failed("shipyard ping: \(reason.message); pass --repo <owner/name> or --project <name>; \(listing(names))")
                }
            }
            let watching = watchers(of: slug, configuration: configuration, resolved: resolved)
            guard !watching.isEmpty else {
                return .failed("shipyard ping: no project watches `\(slug)`; pass --project <name> to file it under one; \(listing(names))")
            }
            projects = watching.map(\.project)
            repository = watching[0].spelling
        }
        var id = newID()
        while store.ping(id: id) != nil { id = newID() }
        do {
            try store.save(Ping(id: id, title: request.title, projects: projects, sent: now, repository: repository))
        } catch {
            return .failed("shipyard ping: couldn't save the ping in \(store.directory.path) (\(error.localizedDescription))")
        }
        return CommandResult(output: id + "\n")
    }

    /// Why the working folder names no repository, as the error line says it.
    struct NoRepository: Error, Equatable {
        var message: String
    }

    /// The repository of the working folder: its git remote `origin`, as `owner/name`.
    static func workingRepository(_ environment: CommandEnvironment) -> Result<String, NoRepository> {
        let folder = environment.workingDirectory.path
        guard let origin = environment.git.origin(in: environment.workingDirectory) else {
            return .failure(NoRepository(message: "the working folder (\(folder)) isn't a git repository with a remote `origin` to file the ping by"))
        }
        guard let slug = GitRemote.repository(fromURL: origin) else {
            return .failure(NoRepository(message: "the working folder's remote `origin` (\(origin)) doesn't name a repository as owner/name"))
        }
        return .success(slug)
    }

    /// The projects that watch `slug`, in the configuration's order, each
    /// with the repository spelled as that project knows it (GitHub's
    /// spelling once resolved). Repositories match ignoring case, as
    /// GitHub's names do.
    static func watchers(
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

    /// The projects a ping can be filed under, for an error.
    private static func listing(_ names: [String]) -> String {
        names.isEmpty ? "config.toml has no projects yet"
            : "the projects are " + names.map { "`\($0)`" }.joined(separator: ", ")
    }

    /// A ping's arguments, read.
    struct Request: Equatable {
        var title: String
        var project: String?
        /// `--repo`'s `owner/name`.
        var repository: String?

        /// Reads `arguments`: one title, and `--repo <owner/name>` or
        /// `--project <name>`, in any order.
        static func parse(_ arguments: [String]) -> Result<Request, ParseError> {
            var titles: [String] = []
            var project: String?
            var repository: String?
            var index = 0
            while index < arguments.count {
                let argument = arguments[index]
                index += 1
                guard argument.hasPrefix("--") else {
                    titles.append(argument)
                    continue
                }
                switch argument {
                case "--project":
                    guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
                    project = arguments[index]
                    index += 1
                case "--repo":
                    guard index < arguments.count else { return .failure(ParseError("`\(argument)` needs a value")) }
                    let value = arguments[index]
                    index += 1
                    guard ConfigurationReader.isRepositorySlug(value) else {
                        return .failure(ParseError("`--repo` takes a repository as owner/name, not `\(value)`"))
                    }
                    repository = value
                default:
                    return .failure(ParseError("unknown option `\(argument)`"))
                }
            }
            if titles.count > 1 {
                return .failure(ParseError("one title only; quote it: shipyard ping \"\(titles.joined(separator: " "))\""))
            }
            let title = titles.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return .failure(ParseError("give the ping a title: \(usageLine)")) }
            if project != nil, repository != nil {
                return .failure(ParseError("pass --repo or --project, not both"))
            }
            return .success(Request(title: title, project: project, repository: repository))
        }
    }

    /// Why the arguments don't read, as the error line says it.
    struct ParseError: Error, Equatable {
        var message: String
        init(_ message: String) { self.message = message }
    }
}

