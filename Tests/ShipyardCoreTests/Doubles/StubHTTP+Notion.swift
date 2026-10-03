import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore

/// Notion's answers, recorded in the shapes API version 2025-09-03 returns
/// (`Fixtures/notion-*.json`), beside the GitHub ones: the entry page
/// found by search, its child databases (`shop`, and `Shop`, which no
/// project's exact name matches), `shop`'s database with its one data
/// source, that data source's query (SHOP-7, an untitled SHOP-6, SHOP-5,
/// and an archived SHOP-4 the filter should have left out), and the
/// untitled note's body.
enum NotionStub {
    static let entryPage = "27a0c3e1-8f4b-80d2-9a51-c7e3b2f0d101"
    static let shopDatabase = "27a0c3e1-8f4b-80aa-b002-0000000000d1"
    static let shopDataSource = "27a0c3e1-8f4b-80bb-c001-0000000000e1"
    static let untitledNote = "27a0c3e1-8f4b-8106-a001-0000000000f6"

    static func url(_ path: String) -> URL { NotionClient.apiURL.appendingPathComponent(path) }

    static let search = url("search")
    static let entryChildren = url("blocks/\(entryPage)/children")
    static let shop = url("databases/\(shopDatabase)")
    static let shopQuery = url("data_sources/\(shopDataSource)/query")
    static let untitledBody = url("blocks/\(untitledNote)/children")
    static let me = url("users/me")

    /// The 401 Notion gives a token it doesn't take, on any request.
    static func unauthorized() throws -> StubHTTP.Answer { try .fixture("notion-unauthorized.json", status: 401) }
}

extension StubHTTP {
    /// Registers Notion's answers for a workspace with the entry page and
    /// `shop`'s notes database, its query answering `query` (the recorded
    /// one by default).
    func onNotion(query: [StubHTTP.Answer]? = nil) throws {
        on("POST", NotionStub.search, try .fixture("notion-search-entry.json"))
        on(NotionStub.entryChildren, try .fixture("notion-entry-children.json"))
        on(NotionStub.shop, try .fixture("notion-database-shop.json"))
        on("POST", NotionStub.shopQuery, answers: try query ?? [.fixture("notion-query-shop.json")])
        on(NotionStub.untitledBody, try .fixture("notion-page-blocks.json"))
        on(NotionStub.me, try .fixture("notion-me.json"))
    }

    /// Every request sent to Notion.
    var notionRequests: [URLRequest] {
        requests.filter { $0.url?.host == NotionClient.apiURL.host }
    }
}
