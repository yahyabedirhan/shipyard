import Foundation

/// What `shipyard notes check` found in the notes workspace: each
/// project's line, and every problem with the layout the app reads (the
/// shipyard skill's notes reference and the workspace's Agent guide define
/// it). An error is something that hides notes from the app or breaks
/// their numbers; a warning is something agents keep tidy.
public struct NotesCheckReport: Equatable, Sendable {
    public enum Severity: String, Equatable, Sendable { case error, warning }

    public struct Problem: Equatable, Sendable {
        public var severity: Severity
        public var message: String

        public init(_ severity: Severity, _ message: String) {
            self.severity = severity
            self.message = message
        }
    }

    /// One configured project that shows notes: its database's prefix and
    /// how many open notes the menu lists, or why there are none.
    public struct ProjectLine: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case listed(prefix: String?, open: Int)
            case noDatabase
            case unreadable(String)
        }

        public var project: String
        public var state: State
    }

    public var projects: [ProjectLine] = []
    public var problems: [Problem] = []

    /// Whether any problem is an error.
    public var hasErrors: Bool { problems.contains { $0.severity == .error } }

    /// The report as `shipyard notes check` prints it: one line per
    /// project, then each problem, then a verdict.
    public var text: String {
        var lines: [String] = []
        let width = (projects.map(\.project.count).max() ?? 0) + 2
        for line in projects {
            let name = line.project.padding(toLength: width, withPad: " ", startingAt: 0)
            switch line.state {
            case .listed(let prefix, let open):
                let prefix = (prefix ?? "-").padding(toLength: 6, withPad: " ", startingAt: 0)
                lines.append("\(name)\(prefix)\(open) open note\(open == 1 ? "" : "s")")
            case .noDatabase:
                lines.append("\(name)no database yet (the first note creates it)")
            case .unreadable(let why):
                lines.append("\(name)can't read its notes: \(why)")
            }
        }
        if !problems.isEmpty {
            if !lines.isEmpty { lines.append("") }
            for problem in problems { lines.append("\(problem.severity.rawValue): \(problem.message)") }
        }
        if !lines.isEmpty { lines.append("") }
        let errors = problems.count { $0.severity == .error }
        let warnings = problems.count - errors
        lines.append(problems.isEmpty
            ? "the notes workspace is in order"
            : "\(errors) error\(errors == 1 ? "" : "s"), \(warnings) warning\(warnings == 1 ? "" : "s")")
        return lines.joined(separator: "\n") + "\n"
    }
}

/// Checks the notes workspace through `client`, reading it the way the
/// app does: the entry page by search, its Projects page, each project's
/// database there, and each one's open notes; then the rest of the layout
/// (the Agent guide, the home page's Projects index, each database's
/// properties and prefix).
public enum NotesCheck {
    static let agentGuideTitle = "Agent guide"

    /// `projects` are the configured projects that show notes, in order.
    public static func run(projects: [String], client: NotionClient) async -> NotesCheckReport {
        var report = NotesCheckReport()
        do {
            try await check(projects: projects, client: client, into: &report)
        } catch {
            report.problems.append(.init(.error, "Notion: \(describe(error))"))
        }
        return report
    }

    private static func check(projects: [String], client: NotionClient, into report: inout NotesCheckReport) async throws {
        let entries = try await client.searchPages(titled: NotesReader.entryPageTitle)
        guard let entry = entries.first else {
            report.problems.append(.init(.error, "ntn's workspace has no page titled \"\(NotesReader.entryPageTitle)\": run ntn doctor and check that its default workspace is the notes workspace"))
            return
        }
        if entries.count > 1 {
            report.problems.append(.init(.error, "\(entries.count) pages are titled \"\(NotesReader.entryPageTitle)\"; the app reads only one of them, so keep one"))
        }

        let pages = try await client.childPages(of: entry)
        for database in try await client.childDatabases(of: entry) {
            report.problems.append(.init(.error, "the database \"\(database.title)\" is directly under \(NotesReader.entryPageTitle), where the app doesn't look: move it under Projects"))
        }
        if !pages.contains(where: { $0.title == agentGuideTitle }) {
            report.problems.append(.init(.warning, "\(NotesReader.entryPageTitle) has no \"\(agentGuideTitle)\" page for agents"))
        }
        let projectsPages = pages.filter { $0.title == NotesReader.projectsPageTitle }
        if projectsPages.count > 1 {
            report.problems.append(.init(.error, "\(projectsPages.count) pages under \(NotesReader.entryPageTitle) are titled \"Projects\"; the app reads only the first"))
        }
        guard let projectsPage = projectsPages.first?.id else {
            report.problems.append(.init(.warning, "\(NotesReader.entryPageTitle) has no Projects page yet; the first note creates it"))
            report.projects = projects.map { .init(project: $0, state: .noDatabase) }
            return
        }

        let databases = try await client.childDatabases(of: projectsPage)
        var prefixes: [String: [String]] = [:]
        var found: [String: String?] = [:]
        for database in databases {
            let sameTitle = databases.filter { $0.title == database.title }
            if sameTitle.first?.id != database.id { continue }
            if sameTitle.count > 1 {
                report.problems.append(.init(.error, "\(sameTitle.count) databases are titled \"\(database.title)\"; the app reads only the first"))
            }
            if !projects.contains(database.title) {
                report.problems.append(.init(.warning, "the database \"\(database.title)\" matches no project that shows notes, so the menu doesn't list it"))
            }
            guard let source = try await client.dataSources(ofDatabase: database.id).first else {
                report.problems.append(.init(.error, "the database \"\(database.title)\" has no data source"))
                continue
            }
            let schema = try await client.schema(ofDataSource: source)
            report.problems += schemaProblems(schema, database: database.title)
            let prefix = schema[NoteProperty.number]?.prefix
            found[database.title] = prefix
            if let prefix { prefixes[prefix.uppercased(), default: []].append(database.title) }
        }
        for (prefix, owners) in prefixes.sorted(by: { $0.key < $1.key }) where owners.count > 1 {
            report.problems.append(.init(.error, "the prefix \(prefix) is used by \(owners.joined(separator: " and ")); each project needs its own"))
        }

        for project in projects {
            guard let database = databases.first(where: { $0.title == project }) else {
                report.projects.append(.init(project: project, state: .noDatabase))
                continue
            }
            do {
                guard let source = try await client.dataSources(ofDatabase: database.id).first else {
                    report.projects.append(.init(project: project, state: .unreadable("no data source")))
                    continue
                }
                let open = try await client.openNotes(in: source).count
                report.projects.append(.init(project: project, state: .listed(prefix: found[project] ?? nil, open: open)))
            } catch {
                report.projects.append(.init(project: project, state: .unreadable(describe(error))))
                report.problems.append(.init(.error, "\(project)'s notes can't be read: \(describe(error))"))
            }
        }

        report.problems += try await indexProblems(entry: entry, databases: found, client: client)
    }

    /// What's wrong with a notes database's properties: the four the app
    /// reads, with their types, a prefix, and Status's two options.
    static func schemaProblems(_ schema: [String: NotesSchemaProperty], database: String) -> [NotesCheckReport.Problem] {
        var problems: [NotesCheckReport.Problem] = []
        let expected: [(String, String)] = [
            (NoteProperty.name, "title"),
            (NoteProperty.number, "unique_id"),
            (NoteProperty.labels, "multi_select"),
            (NoteProperty.status, "select"),
        ]
        for (name, type) in expected {
            guard let property = schema[name] else {
                problems.append(.init(.error, "\"\(database)\" has no \(name) property (\(type))"))
                continue
            }
            if property.type != type {
                problems.append(.init(.error, "\"\(database)\"'s \(name) is a \(property.type), not a \(type)"))
            }
        }
        if let number = schema[NoteProperty.number], number.type == "unique_id", (number.prefix ?? "").isEmpty {
            problems.append(.init(.error, "\"\(database)\"'s No. has no prefix, so its notes have no NAME-7 numbers"))
        }
        if let status = schema[NoteProperty.status], status.type == "select" {
            for option in [Note.open, Note.archived] where !status.options.contains(option) {
                problems.append(.init(.error, "\"\(database)\"'s Status has no \(option) option"))
            }
        }
        return problems
    }

    /// What the home page's Projects index is missing or has wrong: a row
    /// (project, prefix, …) for each database, with its prefix.
    private static func indexProblems(entry: String, databases: [String: String?], client: NotionClient) async throws -> [NotesCheckReport.Problem] {
        let rows = try await client.firstTableRows(onPage: entry).dropFirst()
        var listed: [String: String] = [:]
        for row in rows where row.count >= 2 {
            listed[row[0].trimmingCharacters(in: .whitespaces)] = row[1].trimmingCharacters(in: .whitespaces)
        }
        var problems: [NotesCheckReport.Problem] = []
        for (database, prefix) in databases.sorted(by: { $0.key < $1.key }) {
            guard let row = listed[database] else {
                problems.append(.init(.warning, "the Projects index on \(NotesReader.entryPageTitle) has no row for \"\(database)\""))
                continue
            }
            if let prefix, row != prefix {
                problems.append(.init(.warning, "the Projects index lists \"\(database)\" with \(row.isEmpty ? "no prefix" : row), but its prefix is \(prefix)"))
            }
        }
        for name in listed.keys.sorted() where databases[name] == nil {
            problems.append(.init(.warning, "the Projects index lists \"\(name)\", which has no database under Projects"))
        }
        return problems
    }

    private static func describe(_ error: any Error) -> String {
        (error as? NotionError).map(PanelText.noteError) ?? error.localizedDescription
    }
}
