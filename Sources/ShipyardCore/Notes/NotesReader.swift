import Foundation

/// What one read of the notes came to.
public enum NotesReading: Equatable, Sendable {
    /// Each project that has a notes database, by name: its open notes, or
    /// why its query failed. A project without a database isn't there.
    case read([String: Result<[Note], NotionError>])
    /// Nothing could be read (the token was rejected, Notion out of
    /// reach): every project's notes are unknown.
    case failed(NotionError)
}

/// Reads each project's open notes from Notion: finds the entry page
/// ("Shipyard Notes") by search, lists its child databases, matches each
/// project to the one titled exactly its name, and queries that
/// database's data source. The entry page, each database's data source and
/// each untitled note's first line are remembered between reads, so a read
/// costs one children listing and one query per project with a database;
/// a database or entry page that went away is looked up again.
@MainActor
final class NotesReader {
    /// The page every notes database hangs under, found by its exact title.
    static let entryPageTitle = "Shipyard Notes"

    /// The entry page's id, once search found it.
    private var entryPage: String?
    /// Each database's data source, by database id.
    private var dataSources: [String: String] = [:]
    /// Each untitled note's first line, by page id, with the edit it was read at.
    private var firstLines: [String: (edited: Date, line: String?)] = [:]

    /// Forgets everything found, as when the token changes.
    func reset() {
        entryPage = nil
        dataSources = [:]
        firstLines = [:]
    }

    /// The open notes of each of `projects` that has a database, through
    /// `client`.
    func read(projects: [String], client: NotionClient) async -> NotesReading {
        do {
            guard let databases = try await databases(client) else { return .read([:]) }
            var results: [String: Result<[Note], NotionError>] = [:]
            var used: Set<String> = []
            for project in projects {
                // The first database titled exactly the project's name.
                guard let database = databases.first(where: { $0.title == project })?.id else { continue }
                used.insert(database)
                results[project] = await notes(in: database, client: client)
            }
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

    /// The entry page's child databases; `nil` when no page shared with
    /// the connection is titled "Shipyard Notes".
    private func databases(_ client: NotionClient) async throws -> [(id: String, title: String)]? {
        try await entry(client)?.databases
    }

    /// The entry page and its child databases; `nil` when no page shared
    /// with the connection is titled "Shipyard Notes". A remembered entry
    /// page that's gone (404) is searched for again, once.
    private func entry(_ client: NotionClient) async throws -> (page: String, databases: [(id: String, title: String)])? {
        if let page = entryPage {
            do {
                return (page, try await client.childDatabases(of: page))
            } catch NotionError.http(404, _, _) {
                entryPage = nil
            }
        }
        guard let page = try await client.searchPages(titled: Self.entryPageTitle).first else { return nil }
        entryPage = page
        return (page, try await client.childDatabases(of: page))
    }

    /// Starts a note in `project`: creates its database under the entry
    /// page when none is titled exactly its name (with the fixed core and
    /// a prefix from its name that no other database's `No.` uses), then
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
                let created = try await client.createNotesDatabase(
                    under: entry.page,
                    title: project,
                    prefix: NotePrefix.choose(for: project, taken: taken)
                )
                dataSources[created.database] = created.dataSource
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
    /// No Notion token is kept.
    case notConnected
    /// No page titled "Shipyard Notes" is shared with the connection.
    case noEntryPage
    /// A request to Notion failed.
    case notion(NotionError)
}

/// What giving shipyard a Notion token came to (`Shipyard.connectNotion`).
public enum NotionConnection: Equatable, Sendable {
    /// Notion took it, and it's kept.
    case connected
    /// Nothing was pasted.
    case empty
    /// Notion said it isn't a token (401); nothing is kept.
    case rejected
    /// Notion couldn't be asked; nothing is kept.
    case couldNotCheck(NotionError)
    /// Notion took it, but the token store couldn't keep it.
    case couldNotSave(String)
}
