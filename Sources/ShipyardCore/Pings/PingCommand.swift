import Foundation

/// `shipyard ping`: reads its arguments, files the ping under a project of
/// the configuration, saves it to the ping store and prints its id. Pure
/// apart from the store, so tests call it as a function; the `shipyard`
/// executable only prints what it returns.
///
/// Its arguments are read as a subcommand first (so `withdraw` can join),
/// then as a title and flags, in any order.
public enum PingCommand {
    /// What `shipyard ping --help` prints.
    public static let usageText = """
        usage: shipyard ping "<title>" --project <name>

        Sends the user a ping: it's listed under the project, needs their
        attention until they click it, and prints its id.

          --project <name>  the project (its name in config.toml) to file it under

        """

    /// The usage line errors point at.
    static let usageLine = "shipyard ping \"<title>\" --project <name>"

    /// Sends a ping with `arguments` (those after `ping`), filed under a
    /// project of `configuration`, sent at `now`. `newID` makes the id;
    /// one already stored is drawn again.
    public static func run(
        _ arguments: [String],
        environment: CommandEnvironment,
        configuration: Configuration,
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
        guard let project = request.project else {
            return .usage("shipyard ping: name the project to file it under with --project <name>; \(listing(names))")
        }
        guard names.contains(project) else {
            return .failed("shipyard ping: no project is named `\(project)`; \(listing(names))")
        }
        var id = newID()
        while store.ping(id: id) != nil { id = newID() }
        do {
            try store.save(Ping(id: id, title: request.title, projects: [project], sent: now))
        } catch {
            return .failed("shipyard ping: couldn't save the ping in \(store.directory.path) (\(error.localizedDescription))")
        }
        return CommandResult(output: id + "\n")
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

        /// Reads `arguments`: one title and `--project <name>`, in any order.
        static func parse(_ arguments: [String]) -> Result<Request, ParseError> {
            var titles: [String] = []
            var project: String?
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
                default:
                    return .failure(ParseError("unknown option `\(argument)`"))
                }
            }
            if titles.count > 1 {
                return .failure(ParseError("one title only; quote it: shipyard ping \"\(titles.joined(separator: " "))\""))
            }
            let title = titles.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return .failure(ParseError("give the ping a title: \(usageLine)")) }
            return .success(Request(title: title, project: project))
        }
    }

    /// Why the arguments don't read, as the error line says it.
    struct ParseError: Error, Equatable {
        var message: String
        init(_ message: String) { self.message = message }
    }
}

