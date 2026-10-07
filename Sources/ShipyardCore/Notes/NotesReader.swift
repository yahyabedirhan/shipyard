import Foundation

/// What one read of the notes came to.
public enum NotesReading: Equatable, Sendable {
    /// Each project that has a notes database, by name: its open notes, or
    /// why its query failed. A project without a database isn't there.
    case read([String: Result<[Note], NotionError>])
    /// No page in ntn's workspace is titled "Shipyard Notes": ntn's
    /// default workspace isn't the notes workspace, or the page is gone.
    case noEntryPage
    /// Nothing could be read (no ntn, ntn logged out, Notion out of
    /// reach): every project's notes are unknown.
    case failed(NotionError)
}

/// Reads each project's open notes from Notion: finds the entry page
/// ("Shipyard Notes") by search, then its child page "Projects", lists
/// that page's child databases, matches each project to the one titled
/// exactly its name, and queries that database's data source. The entry
/// page, the Projects page, each database's data source and each untitled
/// note's first line are remembered between reads, so a read costs one
/// children listing and one query per project with a database; a page or
/// database that went away is looked up again.
@MainActor
final class NotesReader {
    /// The page every notes database hangs under, found by its exact title.
    nonisolated static let entryPageTitle = "Shipyard Notes"
    /// The entry page's child page every project's database hangs under.
    nonisolated static let projectsPageTitle = "Projects"

    /// The entry page's id, once search found it.
    private var entryPage: String?
    /// The Projects page's id, once found under the entry page.
    private var projectsPage: String?
    /// Each project's database, by project name, as the last read matched them.
    private(set) var databases: [String: String] = [:]
    /// Each database's data source, by database id.
    private var dataSources: [String: String] = [:]
    /// Each untitled note's first line, by page id, with the edit it was read at.
    private var firstLines: [String: (edited: Date, line: String?)] = [:]

    /// Forgets everything found.
    func reset() {
        entryPage = nil
        projectsPage = nil
        databases = [:]
        dataSources = [:]
        firstLines = [:]
    }

    /// The open notes of each of `projects` that has a database, through
    /// `client`.
    func read(projects: [String], client: NotionClient) async -> NotesReading {
        do {
            guard let databases = try await databases(client) else {
                self.databases = [:]
                return .noEntryPage
            }
            var results: [String: Result<[Note], NotionError>] = [:]
            var used: Set<String> = []
            var matched: [String: String] = [:]
            for project in projects {
                // The first database titled exactly the project's name.
                guard let database = databases.first(where: { $0.title == project })?.id else { continue }
                used.insert(database)
                matched[project] = database
                results[project] = await notes(in: database, client: client)
            }
            self.databases = matched
            dataSources = dataSources.filter { used.contains($0.key) }
            let listed = Set(results.values.flatMap { (try? $0.get()) ?? [] }.map(\.id))
            firstLines = firstLines.filter { listed.contains($0.key) }
            return .read(results)
        } catch let error as NotionError {
            return .failed(error)
        } catch {
            return .failed(.network(error.localizedDescription))
        }
    }

    /// The project databases, under the entry page's Projects page; `nil`
    /// when no page in ntn's workspace is titled "Shipyard Notes",
    /// none when it has no Projects page yet.
    private func databases(_ client: NotionClient) async throws -> [(id: String, title: String)]? {
        try await entry(client)?.databases
    }

    /// The entry page, its Projects page (`nil` while there's none) and that
    /// page's child databases; `nil` when no page in ntn's workspace is
    /// titled "Shipyard Notes". A remembered page that's gone (404) is
    /// looked for again, once.
    private func entry(_ client: NotionClient) async throws -> (page: String, projects: String?, databases: [(id: String, title: String)])? {
        if let page = entryPage, let projects = projectsPage {
            do {
                return (page, projects, try await client.childDatabases(of: projects))
            } catch NotionError.http(404, _, _) {
                projectsPage = nil
            }
        }
        var page: String
        if let known = entryPage {
            page = known
        } else {
            guard let found = try await client.searchPages(titled: Self.entryPageTitle).first else { return nil }
            page = found
        }
        var pages: [(id: String, title: String)]
        do {
            pages = try await client.childPages(of: page)
        } catch NotionError.http(404, _, _) where entryPage != nil {
            // The remembered entry page went: searched for again, once.
            entryPage = nil
            guard let found = try await client.searchPages(titled: Self.entryPageTitle).first else { return nil }
            page = found
            pages = try await client.childPages(of: page)
        }
        entryPage = page
        let projects = pages.first { $0.title == Self.projectsPageTitle }?.id
        projectsPage = projects
        guard let projects else { return (page, nil, []) }
        return (page, projects, try await client.childDatabases(of: projects))
    }

    /// Starts a note in `project`: creates its database under the Projects
    /// page (and that page under the entry page, the first time) when none
    /// is titled exactly its name (with the fixed core and a prefix from
    /// its name that no other database's `No.` uses), then
    /// an empty note in the database's data source. Answers the note's
    /// Notion URL. A new database's data source is remembered, so the next
    /// read finds it without asking.
    func startNote(in project: String, client: NotionClient) async -> Result<URL, NewNoteError> {
        do {
            guard let entry = try await entry(client) else { return .failure(.noEntryPage) }
            let source: String
            if let database = entry.databases.first(where: { $0.title == project })?.id {
                source = try await dataSource(of: database, client: client)
            } else {
                var taken: Set<String> = []
                for database in entry.databases {
                    let schema = try await dataSource(of: database.id, client: client)
                    if let prefix = try await client.notePrefix(ofDataSource: schema) { taken.insert(prefix) }
                }
                let projects: String
                if let known = entry.projects {
                    projects = known
                } else {
                    projects = try await client.createPage(under: entry.page, title: Self.projectsPageTitle, icon: NotionClient.projectsIcon)
                    projectsPage = projects
                }
                let created = try await client.createNotesDatabase(
                    under: projects,
                    title: project,
                    prefix: NotePrefix.choose(for: project, taken: taken)
                )
                dataSources[created.database] = created.dataSource
                databases[project] = created.database
                source = created.dataSource
            }
            return .success(try await client.createEmptyNote(in: source))
        } catch let error as NotionError {
            return .failure(.notion(error))
        } catch {
            return .failure(.notion(.network(error.localizedDescription)))
        }
    }

    /// Database `database`'s data source: the remembered one, else its first.
    private func dataSource(of database: String, client: NotionClient) async throws -> String {
        if let known = dataSources[database] { return known }
        guard let first = try await client.dataSources(ofDatabase: database).first else {
            throw NotionError.unreadable("GET databases/\(database): no data source")
        }
        dataSources[database] = first
        return first
    }

    /// The open notes of `database`, each untitled one with its body's first line.
    private func notes(in database: String, client: NotionClient) async -> Result<[Note], NotionError> {
        do {
            let source: String
            if let known = dataSources[database] {
                source = known
            } else {
                guard let first = try await client.dataSources(ofDatabase: database).first else { return .success([]) }
                source = first
                dataSources[database] = first
            }
            var notes: [Note]
            do {
                notes = try await client.openNotes(in: source)
            } catch let error as NotionError {
                // The data source went (replaced, or no longer shared): look it up again next time.
                if case .http(404, _, _) = error { dataSources[database] = nil }
                throw error
            }
            for index in notes.indices where notes[index].title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                notes[index].firstLine = await firstLine(of: notes[index], client: client)
            }
            return .success(notes)
        } catch let error as NotionError {
            return .failure(error)
        } catch {
            return .failure(.network(error.localizedDescription))
        }
    }

    /// An untitled note's first line, read again only when the note was
    /// edited since; a failed read shows the note as "Untitled" for now.
    private func firstLine(of note: Note, client: NotionClient) async -> String? {
        if let known = firstLines[note.id], known.edited == note.edited { return known.line }
        guard let line = try? await client.firstLine(ofPage: note.id) else { return nil }
        firstLines[note.id] = (note.edited, line)
        return line
    }
}

/// Why the new-note icon couldn't start a note (`Shipyard.startNote`).
public enum NewNoteError: Error, Equatable, Sendable {
    /// This run reads no notes (a demo run).
    case notRead
    /// ntn's workspace has no page titled "Shipyard Notes".
    case noEntryPage
    /// A request to Notion failed.
    case notion(NotionError)
}
