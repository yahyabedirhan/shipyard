import Foundation

/// What one read of the notes came to.
public enum NotesReading: Equatable, Sendable {
    case read([String: Result<[Note], NotionError>])
    case noEntryPage
    case failed(NotionError)
}

@MainActor
final class NotesReader {
    nonisolated static let entryPageTitle = "Shipyard Notes"
    nonisolated static let projectsPageTitle = "Projects"

    private var entryPage: String?
    private var projectsPage: String?
    private(set) var databases: [String: String] = [:]
    private var dataSources: [String: String] = [:]
    private var firstLines: [String: (edited: Date, line: String?)] = [:]

    func reset() {
        entryPage = nil
        projectsPage = nil
        databases = [:]
        dataSources = [:]
        firstLines = [:]
    }

    func read(projects: [(slug: String, title: String)], client: NotionClient) async -> NotesReading {
        do {
            guard let databases = try await databases(client) else {
                self.databases = [:]
                return .noEntryPage
            }
            var results: [String: Result<[Note], NotionError>] = [:]
            var used: Set<String> = []
            var matched: [String: String] = [:]
            for (project, title) in projects {
                guard let database = databases.first(where: { $0.title == title })?.id else { continue }
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

    private func databases(_ client: NotionClient) async throws -> [(id: String, title: String)]? {
        try await entry(client)?.databases
    }

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

    func startNote(in project: String, titled title: String, client: NotionClient) async -> Result<URL, NewNoteError> {
        do {
            guard let entry = try await entry(client) else { return .failure(.noEntryPage) }
            let source: String
            if let database = entry.databases.first(where: { $0.title == title })?.id {
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
                    title: title,
                    prefix: NotePrefix.choose(for: title, taken: taken)
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

    private func dataSource(of database: String, client: NotionClient) async throws -> String {
        if let known = dataSources[database] { return known }
        guard let first = try await client.dataSources(ofDatabase: database).first else {
            throw NotionError.unreadable("GET databases/\(database): no data source")
        }
        dataSources[database] = first
        return first
    }

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

    private func firstLine(of note: Note, client: NotionClient) async -> String? {
        if let known = firstLines[note.id], known.edited == note.edited { return known.line }
        guard let line = try? await client.firstLine(ofPage: note.id) else { return nil }
        firstLines[note.id] = (note.edited, line)
        return line
    }
}

/// Why the new-note icon couldn't start a note (`Shipyard.startNote`).
public enum NewNoteError: Error, Equatable, Sendable {
    case notRead
    case noEntryPage
    case notion(NotionError)
}
