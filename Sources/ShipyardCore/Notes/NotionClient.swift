import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Why a request to Notion failed.
public enum NotionError: Error, Equatable, Sendable {
    /// 401: Notion doesn't take the token (revoked, or never valid).
    case unauthorized
    /// 429 (or 529, Notion overloaded): too many requests; `Retry-After`
    /// seconds, when Notion said.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other status, with Notion's error `code` and `message` when it
    /// gave them: a 404 is a page or database not shared with the
    /// connection, or gone.
    case http(Int, code: String?, message: String?)
    /// The request never reached Notion (offline, timeout).
    case network(String)
    /// A 200 whose body isn't what the API documents.
    case unreadable(String)
}

/// Notion's REST API, as the notes need it, over the same `HTTPTransport`
/// seam GitHub's client uses, so tests answer from recorded responses.
/// Every request is sent as API version `2025-09-03`, where a database
/// holds data sources and pages are queried per data source.
///
/// It reads: who the token is (`me`), pages by title (`searchPages`), a
/// page's child databases (`childDatabases`), a database's data sources
/// (`dataSources`), a data source's open notes (`openNotes`) and a page's
/// first line of text (`firstLine`). Creating a page or a database is one
/// more method over `send`.
public struct NotionClient: Sendable {
    public static let apiURL = URL(string: "https://api.notion.com/v1")!
    /// The `Notion-Version` every request names.
    public static let version = "2025-09-03"
    /// The most a list asks for at once: the API's own maximum.
    static let pageSize = 100
    /// How many pages of a list it follows before stopping.
    static let maxPages = 10

    private let token: String
    private let transport: any HTTPTransport

    public init(token: String, transport: any HTTPTransport) {
        self.token = token
        self.transport = transport
    }

    // MARK: - Reads

    /// Checks the token: `GET /v1/users/me`, the connection's own bot user.
    public func me() async throws {
        _ = try await send("GET", "users/me", as: Ignored.self)
    }

    /// The pages shared with the connection whose title is exactly `title`,
    /// through search (`POST /v1/search`, pages only). Search matches titles
    /// that contain the words, so the exact match is picked here. Its index
    /// can lag a new page by a while, which is why it's used only to find
    /// the entry page, never notes.
    public func searchPages(titled title: String) async throws -> [String] {
        let body: [String: Any] = [
            "query": title,
            "filter": ["property": "object", "value": "page"],
            "page_size": Self.pageSize,
        ]
        let list = try await send("POST", "search", body: body, as: List<PageObject>.self)
        return list.results.filter { $0.plainTitle == title && $0.in_trash != true }.map(\.id)
    }

    /// The databases right under page `pageID`, by title, in page order:
    /// its `child_database` blocks (`GET /v1/blocks/{id}/children`). A
    /// block's id is its database's id.
    public func childDatabases(of pageID: String) async throws -> [(id: String, title: String)] {
        var found: [(id: String, title: String)] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            var query = [URLQueryItem(name: "page_size", value: String(Self.pageSize))]
            if let cursor { query.append(URLQueryItem(name: "start_cursor", value: cursor)) }
            let list = try await send("GET", "blocks/\(pageID)/children", query: query, as: List<Block>.self)
            for block in list.results where block.type == "child_database" && block.in_trash != true {
                found.append((block.id, block.child_database?.title ?? ""))
            }
            guard list.has_more, let next = list.next_cursor else { break }
            cursor = next
        }
        return found
    }

    /// The data sources of database `databaseID`, in Notion's order
    /// (`GET /v1/databases/{id}`): one, unless the user added more.
    public func dataSources(ofDatabase databaseID: String) async throws -> [String] {
        try await send("GET", "databases/\(databaseID)", as: Database.self).data_sources.map(\.id)
    }

    /// The open notes in data source `dataSourceID`, newest first: one
    /// query (`POST /v1/data_sources/{id}/query`) filtered to `Status` empty
    /// or not `Archived`, sorted by when each was created, followed page by
    /// page. A page that's archived anyway, or in the trash, is left out.
    public func openNotes(in dataSourceID: String) async throws -> [Note] {
        var notes: [Note] = []
        var cursor: String?
        for _ in 0..<Self.maxPages {
            var body: [String: Any] = [
                "filter": ["or": [
                    ["property": NoteProperty.status, "select": ["is_empty": true]],
                    ["property": NoteProperty.status, "select": ["does_not_equal": Note.archived]],
                ]],
                "sorts": [["timestamp": "created_time", "direction": "descending"]],
                "page_size": Self.pageSize,
            ]
            if let cursor { body["start_cursor"] = cursor }
            let list = try await send("POST", "data_sources/\(dataSourceID)/query", body: body, as: List<PageObject>.self)
            notes += list.results.compactMap(\.note).filter { !$0.isArchived }
            guard list.has_more, let next = list.next_cursor else { break }
            cursor = next
        }
        return notes
    }

    /// The first line of text in page `pageID`'s body: the first of its
    /// first blocks with any text (`GET /v1/blocks/{id}/children`), cut at
    /// its first line break; `nil` when none has text.
    public func firstLine(ofPage pageID: String) async throws -> String? {
        let query = [URLQueryItem(name: "page_size", value: "10")]
        let list = try await send("GET", "blocks/\(pageID)/children", query: query, as: List<Block>.self)
        for block in list.results {
            let text = block.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            return text.split(whereSeparator: \.isNewline).first.map(String.init)
        }
        return nil
    }

    // MARK: - Sending

    /// Sends one request to `path` under the API (`users/me`), with
    /// `query` and a JSON `body`, and decodes the answer as `T`. Every
    /// status but 200 throws its `NotionError`.
    func send<T: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        as type: T.Type
    ) async throws -> T {
        var components = URLComponents(url: Self.apiURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.version, forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        }
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw NotionError.network(error.localizedDescription)
        }
        switch response.statusCode {
        case 200:
            do {
                return try Self.decoder.decode(T.self, from: data)
            } catch {
                throw NotionError.unreadable("\(method) \(path)")
            }
        case 401:
            throw NotionError.unauthorized
        case 429, 529:
            let retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw NotionError.rateLimited(retryAfter: retryAfter)
        default:
            let failure = try? JSONDecoder().decode(ErrorBody.self, from: data)
            throw NotionError.http(response.statusCode, code: failure?.code, message: failure?.message)
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = NotionClient.date(text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a date: \(text)"))
            }
            return date
        }
        return decoder
    }()

    /// A Notion timestamp, "2026-09-25T11:42:00.000Z", with or without
    /// its fraction of a second.
    static func date(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}

/// The note properties the app reads: the fixed core every project's
/// database has (the shipyard skill's notes reference defines it).
enum NoteProperty {
    static let number = "No."
    static let labels = "Labels"
    static let status = "Status"
}

// MARK: - What Notion answers

/// A body the app doesn't read.
private struct Ignored: Decodable {}

/// Notion's error body: `{"object":"error","status":404,"code":"object_not_found","message":"…"}`.
private struct ErrorBody: Decodable {
    var code: String?
    var message: String?
}

/// A paginated list: `results`, `has_more` and `next_cursor`.
private struct List<Element: Decodable>: Decodable {
    var results: [Element]
    var has_more: Bool
    var next_cursor: String?
}

/// A piece of rich text; only its plain text is read.
private struct RichText: Decodable {
    var plain_text: String
}

/// A block: a `child_database` with its title, or a block with text.
private struct Block: Decodable {
    struct ChildDatabase: Decodable { var title: String }
    struct Text: Decodable { var rich_text: [RichText]? }

    var id: String
    var type: String
    var in_trash: Bool?
    var child_database: ChildDatabase?
    var text: Text?

    /// The block's text, whatever its type (a paragraph, a heading, a
    /// list item…): the plain text of its type's `rich_text`.
    var plainText: String {
        (text?.rich_text ?? []).map(\.plain_text).joined()
    }

    private enum CodingKeys: String, CodingKey { case id, type, in_trash, child_database }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        in_trash = try container.decodeIfPresent(Bool.self, forKey: .in_trash)
        child_database = try container.decodeIfPresent(ChildDatabase.self, forKey: .child_database)
        // The text sits under the block's own type: {"type":"paragraph","paragraph":{"rich_text":[…]}}.
        let byType = try decoder.container(keyedBy: AnyKey.self)
        text = try? byType.decodeIfPresent(Text.self, forKey: AnyKey(type))
    }
}

/// `GET /v1/databases/{id}`: its data sources.
private struct Database: Decodable {
    struct Source: Decodable { var id: String }
    var data_sources: [Source]
}

/// A page, from search or a data-source query.
private struct PageObject: Decodable {
    /// One property value; only the types notes use are read.
    struct Property: Decodable {
        struct Option: Decodable { var name: String }
        struct UniqueID: Decodable {
            var prefix: String?
            var number: Int?
        }

        var type: String
        var title: [RichText]?
        var unique_id: UniqueID?
        var multi_select: [Option]?
        var select: Option?
    }

    var id: String
    var url: String?
    var in_trash: Bool?
    var created_time: Date?
    var last_edited_time: Date?
    var properties: [String: Property]?

    /// The page's title, whatever its title property is called.
    var plainTitle: String {
        let title = properties?.values.first { $0.type == "title" }
        return (title?.title ?? []).map(\.plain_text).joined()
    }

    /// The page as a note; `nil` when it's in the trash or lacks what
    /// every page has (a URL, its times).
    var note: Note? {
        guard in_trash != true, let url = url.flatMap(URL.init(string:)), let created = created_time else { return nil }
        let number = properties?[NoteProperty.number]?.unique_id
        return Note(
            id: id,
            url: url,
            number: number?.number,
            prefix: number?.prefix,
            // `Name` is the title property; read by its type, so a rename doesn't blank every row.
            title: plainTitle,
            labels: (properties?[NoteProperty.labels]?.multi_select ?? []).map(\.name),
            status: properties?[NoteProperty.status]?.select?.name,
            created: created,
            edited: last_edited_time ?? created
        )
    }
}

/// A coding key named at run time, for the block's type-named member.
private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}
