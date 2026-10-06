import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore

/// Notion's answers, recorded in the shapes API version 2025-09-03 returns
/// (`Fixtures/notion-*.json`), beside the GitHub ones: the entry page
/// found by search, its child pages (Projects, and an Agent guide), the
/// Projects page's child databases (`shop`, and `Shop`, which no
/// project's exact name matches), `shop`'s database with its one data
/// source, that data source's query (SHOP-7, an untitled SHOP-6, SHOP-5,
/// and an archived SHOP-4 the filter should have left out), and the
/// untitled note's body.
enum NotionStub {
    static let entryPage = "27a0c3e1-8f4b-80d2-9a51-c7e3b2f0d101"
    static let projectsPage = "27a0c3e1-8f4b-80d2-9a51-c7e3b2f0d102"
    static let shopDatabase = "27a0c3e1-8f4b-80aa-b002-0000000000d1"
    static let shopDataSource = "27a0c3e1-8f4b-80bb-c001-0000000000e1"
    static let untitledNote = "27a0c3e1-8f4b-8106-a001-0000000000f6"

    static func url(_ path: String) -> URL { NotionClient.apiURL.appendingPathComponent(path) }

    static let search = url("search")
    static let entryChildren = url("blocks/\(entryPage)/children")
    static let projectsChildren = url("blocks/\(projectsPage)/children")
    static let shop = url("databases/\(shopDatabase)")
    static let shopQuery = url("data_sources/\(shopDataSource)/query")
    static let untitledBody = url("blocks/\(untitledNote)/children")
    static let me = url("users/me")

    /// What the new-note icon asks: each database's schema (`shop`'s
    /// prefix is SHOP, `Shop`'s SHO), and the creates.
    static let capitalisedDatabase = "27a0c3e1-8f4b-80aa-b003-0000000000d2"
    static let capitalisedDataSource = "27a0c3e1-8f4b-80bb-c002-0000000000e2"
    static let createdDataSource = "27a0c3e1-8f4b-80bb-c003-0000000000e3"
    static let shopSchema = url("data_sources/\(shopDataSource)")
    static let capitalised = url("databases/\(capitalisedDatabase)")
    static let capitalisedSchema = url("data_sources/\(capitalisedDataSource)")
    static let databases = url("databases")
    static let pages = url("pages")
    /// The page a create answers with, which the icon opens.
    static let createdPage = URL(string: "https://www.notion.so/27a0c3e18f4b8108a0010000000000f8")!

    /// The 401 Notion gives a token it doesn't take, on any request.
    static func unauthorized() throws -> StubHTTP.Answer { try .fixture("notion-unauthorized.json", status: 401) }
}

extension StubHTTP {
    /// Registers Notion's answers for a workspace with the entry page, its
    /// Projects page and `shop`'s notes database, its query answering
    /// `query` (the recorded one by default).
    func onNotion(query: [StubHTTP.Answer]? = nil) throws {
        on("POST", NotionStub.search, try .fixture("notion-search-entry.json"))
        on(NotionStub.entryChildren, try .fixture("notion-entry-children.json"))
        on(NotionStub.projectsChildren, try .fixture("notion-projects-children.json"))
        on(NotionStub.shop, try .fixture("notion-database-shop.json"))
        on("POST", NotionStub.shopQuery, answers: try query ?? [.fixture("notion-query-shop.json")])
        on(NotionStub.untitledBody, try .fixture("notion-page-blocks.json"))
        on(NotionStub.me, try .fixture("notion-me.json"))
    }

    /// Registers what starting a note asks beyond a read: both databases'
    /// schemas, and the database and page creates.
    func onNewNote() throws {
        on(NotionStub.shopSchema, try .fixture("notion-data-source-shop.json"))
        on(NotionStub.capitalised, try .fixture("notion-database-shop-capitalised.json"))
        on(NotionStub.capitalisedSchema, try .fixture("notion-data-source-shop-capitalised.json"))
        on("POST", NotionStub.databases, try .fixture("notion-database-created.json"))
        on("POST", NotionStub.pages, try .fixture("notion-page-created.json"))
    }

    /// Every request sent to Notion.
    var notionRequests: [URLRequest] {
        requests.filter { $0.url?.host == NotionClient.apiURL.host }
    }
}
