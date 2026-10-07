import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let projects = """
    [[projects]]
    name = "shop"
    repositories = ["yahyabedirhan/shop"]

    [[projects]]
    name = "blog"
    repositories = ["yahyabedirhan/blog"]

    """

private typealias PR = PullRequestsResponse.PullRequest

@MainActor
private extension Harness {
    /// Started with `config`, ntn logged in, Notion answering a read
    /// as `NotionStub` records and the icon's schema reads and creates,
    /// after the notes' first read.
    static func withNewNote(config: String = projects) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.ntn.set(.loggedIn)
        harness.connectNotionBeforeStart()
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([PullRequestsResponse("yahyabedirhan/shop", [PR(1)]).answer])
        try harness.stub.onNotion()
        try harness.stub.onNewNote()
        await harness.shipyard.start()
        _ = await harness.notesTimer.fire()
        return harness
    }

    /// The error rows about starting a note in `project`.
    func newNoteErrors(_ project: String) -> [String] {
        section(project)?.errors.map(\.message).filter { $0.hasPrefix("new note: ") } ?? []
    }

    /// The databases the icon created, and the pages.
    var createdDatabases: [URLRequest] { stub.requests("POST", NotionStub.databases) }
    var createdPages: [URLRequest] { stub.requests("POST", NotionStub.pages) }
}

/// A request's JSON body.
private func json(_ request: URLRequest?) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: request?.httpBody ?? Data()) as? NSDictionary)
}

private func json(_ text: String) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? NSDictionary)
}

/// The new-note icon on a project's header: a database when the project
/// has none, then an empty page, opened in Notion; end to end across
/// `NotionClient`, `NotesReader` and the orchestrator, over recorded
/// Notion answers.
@Suite("The new-note icon")
@MainActor
struct NewNoteTests {
    @Test("a project without a database: the icon creates it under the Projects page with the fixed core and a free prefix, then an empty page in it, opens the page, and the menu lists it")
    func databaseThenPage() async throws {
        let harness = try await Harness.withNewNote()
        // Once the database is made, the Projects page lists `blog`, and its query the new page.
        let children = try StubHTTP.Answer.fixture("notion-projects-children.json")
        var withBlog = children
        withBlog.body = Data(String(decoding: children.body, as: UTF8.self)
            .replacingOccurrences(of: "\"title\": \"Shop\"", with: "\"title\": \"blog\"")
            .replacingOccurrences(of: NotionStub.capitalisedDatabase, with: "27a0c3e1-8f4b-80aa-b004-0000000000d3").utf8)
        let page = try String(decoding: StubHTTP.Answer.fixture("notion-page-created.json").body, as: UTF8.self)
        harness.stub.on("POST", NotionStub.url("data_sources/\(NotionStub.createdDataSource)/query"),
                        .json(#"{"object":"list","results":[\#(page)],"has_more":false,"next_cursor":null}"#))
        harness.stub.on(NotionStub.url("blocks/27a0c3e1-8f4b-8108-a001-0000000000f8/children"),
                        .json(#"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#))
        let stub = harness.stub
        let listingBlog = withBlog
        stub.onSend { request in
            if request.httpMethod == "POST", request.url == NotionStub.databases {
                stub.on(NotionStub.projectsChildren, listingBlog)
            }
        }

        await harness.shipyard.startNote(in: "blog")

        #expect(harness.createdDatabases.count == 1)
        #expect(try json(harness.createdDatabases.first) == json("""
            {"parent": {"type": "page_id", "page_id": "\(NotionStub.projectsPage)"},
             "title": [{"text": {"content": "blog"}}],
             "icon": {"type": "emoji", "emoji": "🗂️"},
             "initial_data_source": {"properties": {
               "Name": {"title": {}},
               "No.": {"unique_id": {"prefix": "BLOG"}},
               "Labels": {"multi_select": {"options": []}},
               "Status": {"select": {"options": [{"name": "Open", "color": "green"}, {"name": "Archived", "color": "gray"}]}}}}}
            """))
        #expect(try json(harness.createdPages.first) == json("""
            {"parent": {"type": "data_source_id", "data_source_id": "\(NotionStub.createdDataSource)"},
             "properties": {"Status": {"select": {"name": "Open"}}}}
            """))
        #expect(harness.createdDatabases.first?.value(forHTTPHeaderField: "Notion-Version") == "2025-09-03")
        #expect(harness.actions.opened == [NotionStub.createdPage])
        #expect(harness.section("blog")?.rows.filter { $0.kind == .note }.map { PanelText.number($0) } == ["BLOG-1"])
        #expect(harness.newNoteErrors("blog").isEmpty)
        #expect(harness.stub.unmatched.isEmpty)
    }

    @Test("a project with a database: the icon creates only the page, in its data source, and opens it")
    func pageOnly() async throws {
        let harness = try await Harness.withNewNote()
        let queries = harness.stub.requests("POST", NotionStub.shopQuery).count

        await harness.shipyard.startNote(in: "shop")

        #expect(harness.createdDatabases.isEmpty)
        // No database is made, so no prefix is looked for.
        #expect(harness.stub.requests("GET", NotionStub.shopSchema).isEmpty)
        #expect(try json(harness.createdPages.first) == json("""
            {"parent": {"type": "data_source_id", "data_source_id": "\(NotionStub.shopDataSource)"},
             "properties": {"Status": {"select": {"name": "Open"}}}}
            """))
        #expect(harness.actions.opened == [NotionStub.createdPage])
        // The notes are read again, so the new one lists.
        #expect(harness.stub.requests("POST", NotionStub.shopQuery).count == queries + 1)
    }

    @Test("a new database's prefix comes from the project's name, two to five uppercase letters no other database's No. uses (here SHOP and SHO)", arguments: [
        ("blog", "BLOG"),
        ("shopping", "SHOPP"),
        ("sho", "SH"),
        ("my shop", "MYSH"),
        ("x", "XA"),
    ])
    func prefix(project: String, expected: String) async throws {
        let config = projects + "[[projects]]\nname = \"\(project)\"\nrepositories = [\"yahyabedirhan/other\"]\n"
        let harness = try await Harness.withNewNote(config: config)

        await harness.shipyard.startNote(in: project)

        let body = try json(harness.createdDatabases.first)
        let properties = (body["initial_data_source"] as? NSDictionary)?["properties"] as? NSDictionary
        #expect((properties?["No."] as? NSDictionary)?["unique_id"] as? NSDictionary == ["prefix": expected])
    }

    @Test("while a note is being started its icon says so, and a second click meanwhile starts nothing more")
    func starting() async throws {
        let harness = try await Harness.withNewNote()
        let shipyard = harness.shipyard
        let during = Locked<[NewNoteButton?]>([])
        harness.stub.onSend { request in
            guard request.httpMethod == "POST", request.url == NotionStub.pages else { return }
            await MainActor.run {
                during.withValue { $0.append(shipyard.menu.sections.first { $0.name == "shop" }?.newNote) }
            }
            await shipyard.startNote(in: "shop")
        }

        await harness.shipyard.startNote(in: "shop")

        #expect(during.current == [.starting])
        #expect(harness.createdPages.count == 1)
        #expect(harness.section("shop")?.newNote == .ready)
    }

    @Test("ntn logged out shows as the project's error and opens nothing; the error goes when the menu opens again")
    func rejected() async throws {
        let harness = try await Harness.withNewNote()
        harness.stub.on("POST", NotionStub.pages, try NotionStub.unauthorized())

        await harness.shipyard.startNote(in: "shop")

        #expect(harness.actions.opened.isEmpty)
        #expect(harness.newNoteErrors("shop") == ["new note: ntn isn't logged in; run ntn login in Terminal"])
        #expect(harness.newNoteErrors("blog").isEmpty)
        #expect(harness.section("shop")?.newNote == .ready)

        await harness.shipyard.panelOpened()
        #expect(harness.newNoteErrors("shop").isEmpty)
    }

    @Test("a Shipyard Notes page without a Projects page: the icon creates Projects under it, then the project's database under Projects, then the note")
    func projectsPageFirst() async throws {
        let harness = try Harness(stored: "gho_stored", config: projects)
        harness.ntn.set(.loggedIn)
        harness.connectNotionBeforeStart()
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([PullRequestsResponse("yahyabedirhan/shop", [PR(1)]).answer])
        try harness.stub.onNotion()
        try harness.stub.onNewNote()
        harness.stub.on(NotionStub.entryChildren, .json(#"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#))
        await harness.shipyard.start()
        _ = await harness.notesTimer.fire()
        #expect(harness.section("shop")?.rows.filter { $0.kind == .note }.isEmpty == true)

        await harness.shipyard.startNote(in: "shop")

        let created = try String(decoding: StubHTTP.Answer.fixture("notion-page-created.json").body, as: UTF8.self)
        let createdID = try #require(try JSONSerialization.jsonObject(with: Data(created.utf8)) as? NSDictionary)["id"] as? String
        #expect(try json(harness.createdPages.first) == json("""
            {"parent": {"type": "page_id", "page_id": "\(NotionStub.entryPage)"},
             "icon": {"type": "emoji", "emoji": "📂"},
             "properties": {"title": {"title": [{"text": {"content": "Projects"}}]}}}
            """))
        let database = try json(harness.createdDatabases.first)
        #expect((database["parent"] as? NSDictionary)?["page_id"] as? String == createdID)
        #expect(harness.createdPages.count == 2)
        #expect(harness.actions.opened == [NotionStub.createdPage])
    }

    @Test("Notion out of reach shows as the project's error, and nothing is created")
    func unreachable() async throws {
        let harness = try await Harness.withNewNote()
        harness.stub.on(NotionStub.projectsChildren, .failure())

        await harness.shipyard.startNote(in: "blog")

        #expect(harness.createdDatabases.isEmpty)
        #expect(harness.createdPages.isEmpty)
        #expect(harness.actions.opened.isEmpty)
        #expect(harness.newNoteErrors("blog").first?.hasPrefix("new note: can't reach Notion") == true)
    }

    @Test("without a Shipyard Notes page in ntn's workspace, the icon says so and creates nothing")
    func noEntryPage() async throws {
        let harness = try await Harness.withNewNote()
        harness.stub.on("POST", NotionStub.search, .json(#"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#))
        // The entry page and Projects page found by the first read are gone.
        harness.stub.on(NotionStub.projectsChildren, .json(#"{"object":"error","status":404,"code":"object_not_found","message":"Could not find block."}"#, status: 404))
        harness.stub.on(NotionStub.entryChildren, .json(#"{"object":"error","status":404,"code":"object_not_found","message":"Could not find block."}"#, status: 404))

        await harness.shipyard.startNote(in: "blog")

        #expect(harness.createdDatabases.isEmpty)
        #expect(harness.actions.opened.isEmpty)
        #expect(harness.newNoteErrors("blog") == ["new note: ntn's workspace has no page titled Shipyard Notes"])
    }

    @Test("the icon is on each project that shows notes while ntn is logged in, and nowhere else")
    func shown() async throws {
        let config = projects.replacingOccurrences(
            of: "repositories = [\"yahyabedirhan/blog\"]\n",
            with: "repositories = [\"yahyabedirhan/blog\"]\nnotes = { show = false }\n"
        )
        let harness = try await Harness.withNewNote(config: config)
        #expect(harness.section("shop")?.newNote == .ready)
        #expect(harness.section("blog")?.newNote == nil)

        // ntn logged out, or gone: no icon, until the next read finds it back.
        harness.ntn.set(.loggedOut)
        _ = await harness.notesTimer.fire()
        #expect(harness.section("shop")?.newNote == nil)
        harness.ntn.set(.missing)
        _ = await harness.notesTimer.fire()
        #expect(harness.section("shop")?.newNote == nil)
        harness.ntn.set(.loggedIn)
        _ = await harness.notesTimer.fire()
        #expect(harness.section("shop")?.newNote == .ready)
    }
}
