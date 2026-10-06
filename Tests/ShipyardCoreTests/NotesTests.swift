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

/// One open pull request in `yahyabedirhan/shop`, none in the blog.
private let onePullRequest = PullRequestsResponse("yahyabedirhan/shop", [PR(1)]).answer

@MainActor
private extension Harness {
    /// Started with `config`, GitHub answering one pull request, a Notion
    /// token kept and Notion answering as `NotionStub` records, then the
    /// notes timer's first read.
    static func withNotes(config: String = projects, query: [StubHTTP.Answer]? = nil) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        try harness.notion.save("ntn_token")
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        try harness.stub.onNotion(query: query)
        await harness.shipyard.start()
        await harness.readNotes()
        return harness
    }

    /// Fires the notes timer, which must be armed, and waits for the read.
    func readNotes(sourceLocation: SourceLocation = #_sourceLocation) async {
        let fired = await notesTimer.fire()
        #expect(fired, "the notes timer wasn't armed", sourceLocation: sourceLocation)
    }

    /// The note rows of `project`.
    func noteRows(_ project: String = "shop") -> [MenuRow] {
        section(project)?.rows.filter { $0.kind == .note } ?? []
    }

    /// The error rows about `project`'s notes, beside its repositories' own.
    func noteErrors(_ project: String) -> [String] {
        section(project)?.errors.map(\.message).filter { $0.hasPrefix("notes: ") } ?? []
    }

    /// The notes banner, when the panel shows one.
    var notesBanner: PanelBanner? { shipyard.banners(at: clock.now).first { $0.kind == .notes } }

    /// The queries sent for `shop`'s notes.
    var shopQueries: [URLRequest] { stub.requests("POST", NotionStub.shopQuery) }
}

/// The user's notes, read from Notion through the HTTP seam, in the menu:
/// end to end across `NotionClient`, `NotesReader` and the orchestrator.
@Suite("Notes in the menu")
@MainActor
struct NotesTests {
    @Test("a project's open notes list newest first in a Notes group, each with its number, title (or first line) and labels; the archived one doesn't")
    func rows() async throws {
        let harness = try await Harness.withNotes()

        let rows = harness.noteRows()
        #expect(rows.map(\.title) == [
            "Use note numbers in commit messages",
            "what if the cart remembered the last address",
            "Brainstorm the checkout flow",
        ])
        #expect(rows.map { PanelText.number($0) } == ["SHOP-7", "SHOP-6", "SHOP-5"])
        #expect(rows.map { PanelText.rowDetail($0, showingRepository: false) } == [
            "SHOP-7 · ideation", "SHOP-6", "SHOP-5 · brainstorming · checkout",
        ])
        #expect(rows.map { PanelText.noteLabels($0) } == ["ideation", nil, "brainstorming, checkout"])
        #expect(harness.section("shop")?.groups.map(\.title) == ["Pull requests", "Notes"])
        // `Shop` isn't `blog`, and isn't `shop` either: no database, no Notes group.
        #expect(harness.noteRows("blog").isEmpty)
        #expect(harness.noteErrors("blog").isEmpty)
    }

    @Test("Notion is asked as API version 2025-09-03, with the token, for open notes only, newest first")
    func requests() async throws {
        let harness = try await Harness.withNotes()

        let query = try #require(harness.shopQueries.first)
        #expect(query.value(forHTTPHeaderField: "Notion-Version") == "2025-09-03")
        #expect(query.value(forHTTPHeaderField: "Authorization") == "Bearer ntn_token")
        let body = try #require(try JSONSerialization.jsonObject(with: query.httpBody ?? Data()) as? [String: Any])
        let filter = try #require((body["filter"] as? [String: Any])?["or"] as? [[String: Any]])
        #expect(filter.contains { ($0["select"] as? [String: Any])?["is_empty"] as? Bool == true })
        #expect(filter.contains { ($0["select"] as? [String: Any])?["does_not_equal"] as? String == "Archived" })
        #expect((body["sorts"] as? [[String: String]]) == [["timestamp": "created_time", "direction": "descending"]])
        // Only `shop` has a database: one query in all, and the entry page found by search.
        #expect(harness.shopQueries.count == 1)
        #expect(harness.stub.requests("POST", NotionStub.search).first?.bodyText.contains("Shipyard Notes") == true)
        #expect(harness.stub.unmatched.isEmpty)
    }

    @Test("the header's notes count opens the project's notes database in Notion; a project without a database has no link")
    func countOpensDatabase() async throws {
        let harness = try await Harness.withNotes()

        let link = try #require(harness.section("shop")?.pageLinks(for: .note).first)
        #expect(link.url == URL(string: "https://www.notion.so/27a0c3e18f4b80aab0020000000000d1"))
        #expect(link.count == 3)
        #expect(harness.section("blog")?.pageLinks(for: .note).isEmpty == true)
        #expect(PanelText.headerCountPage(.note) == "Open the notes in Notion")
    }

    @Test("a Shipyard Notes page with no Projects page yet lists no notes, with no error and no banner: no project has notes yet")
    func noProjectsPage() async throws {
        let harness = try await Harness.withNotes()
        harness.shipyard.disconnectNotion()
        try harness.notion.save("ntn_token")
        harness.stub.on(NotionStub.entryChildren, .json(#"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#))

        _ = await harness.shipyard.connectNotion(token: "ntn_token")

        #expect(harness.noteRows().isEmpty)
        #expect(harness.noteErrors("shop").isEmpty)
        #expect(harness.notesBanner == nil)
    }

    @Test("notes need no attention: they add nothing to any count, and Mark all seen leaves them out")
    func notCounted() async throws {
        let harness = try await Harness.withNotes()

        #expect(harness.noteRows().allSatisfy { !$0.needsAttention })
        let pullRequest = try #require(harness.section("shop")?.rows.first { $0.kind == .pullRequest })
        #expect(harness.section("shop")?.attentionCount == 1)
        #expect(harness.shipyard.menu.attention == AttentionCounts(pullRequests: 1))
        harness.shipyard.markAllSeen()
        #expect(harness.shipyard.appStateStore.state.attention.seen.keys.sorted() == [pullRequest.id])
    }

    @Test("clicking a note opens its page in Notion and marks nothing seen; ⌥-click does nothing")
    func click() async throws {
        let harness = try await Harness.withNotes()
        let row = try #require(harness.noteRows().first)

        await harness.shipyard.open(row).value
        harness.shipyard.markSeen(row)

        #expect(harness.actions.opened == [URL(string: "https://www.notion.so/Use-note-numbers-in-commit-messages-27a0c3e18f4b8107a0010000000000f7")!])
        #expect(harness.shipyard.appStateStore.state.attention.seen.isEmpty)
    }

    @Test("[defaults.notes] show = false lists no notes and asks Notion nothing; a project's notes = { show = true } brings its own back")
    func showSettings() async throws {
        let hidden = try await Harness.withNotes(config: "[defaults.notes]\nshow = false\n" + projects)
        #expect(hidden.noteRows().isEmpty)
        #expect(hidden.stub.notionRequests.isEmpty)

        let shown = projects.replacingOccurrences(of: "repositories = [\"yahyabedirhan/shop\"]\n", with: "repositories = [\"yahyabedirhan/shop\"]\nnotes = { show = true }\n")
        try hidden.writeConfig("[defaults.notes]\nshow = false\n" + shown)
        await hidden.shipyard.reloadConfiguration()
        await hidden.readNotes()
        #expect(hidden.noteRows().count == 3)
    }

    @Test("notes are read again every 60 seconds and whenever the menu opens; a note written meanwhile shows")
    func refreshTriggers() async throws {
        let later = try StubHTTP.Answer.fixture("notion-query-shop.json")
        var withNewNote = later
        withNewNote.body = Data(String(decoding: later.body, as: UTF8.self)
            .replacingOccurrences(of: "Use note numbers in commit messages", with: "Rename the cart").utf8)
        let harness = try await Harness.withNotes(query: [later, withNewNote])

        #expect(harness.notesTimer.armed == 60)
        await harness.readNotes()
        #expect(harness.shopQueries.count == 2)
        #expect(harness.noteRows().first?.title == "Rename the cart")
        #expect(harness.notesTimer.armed == 60)

        await harness.shipyard.panelOpened()
        #expect(harness.shopQueries.count == 3)
        // Found once: the entry page and the data source are remembered.
        #expect(harness.stub.requests("POST", NotionStub.search).count == 1)
        #expect(harness.stub.requests("GET", NotionStub.shop).count == 1)
        // The untitled note wasn't edited since: its first line isn't read again.
        #expect(harness.stub.requests("GET", NotionStub.untitledBody).count == 1)
    }

    @Test("a failed query shows on its project as an error row and keeps the notes it had, never an empty list")
    func failedQuery() async throws {
        let harness = try await Harness.withNotes(query: [
            try .fixture("notion-query-shop.json"),
            .json(#"{"object":"error","status":503,"code":"service_unavailable","message":"Notion is unavailable, please try again later."}"#, status: 503),
        ])

        await harness.readNotes()

        #expect(harness.noteErrors("shop") == ["notes: Notion answered 503: Notion is unavailable, please try again later."])
        #expect(harness.noteRows().count == 3)
    }

    @Test("Notion out of reach before any read: every project showing notes says so, and lists no notes it doesn't know")
    func unreachable() async throws {
        let harness = try Harness(stored: "gho_stored", config: projects)
        try harness.notion.save("ntn_token")
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        harness.stub.on("POST", NotionStub.search, .failure())
        await harness.shipyard.start()
        await harness.readNotes()

        for project in ["shop", "blog"] {
            #expect(harness.noteErrors(project).first?.hasPrefix("notes: can't reach Notion") == true)
        }
        #expect(harness.notesTimer.armed == 60)
    }

    @Test("a rejected token shows on every project that shows notes, saying to connect again")
    func rejectedToken() async throws {
        let harness = try await Harness.withNotes()
        harness.stub.on(NotionStub.projectsChildren, try NotionStub.unauthorized())

        await harness.readNotes()

        let message = "notes: Notion rejected the token; connect Notion again from the settings menu"
        #expect(harness.noteErrors("shop") == [message])
        #expect(harness.noteErrors("blog") == [message])
        #expect(harness.noteRows().count == 3)
    }

    @Test("without a Notion token, Notion is never asked, no project lists notes, and a banner says to connect Notion; with every project's notes hidden it doesn't")
    func noToken() async throws {
        let harness = try await Harness.started(config: projects, graphQL: onePullRequest)

        await harness.shipyard.panelOpened()

        #expect(harness.notesTimer.armed == nil)
        #expect(harness.stub.notionRequests.isEmpty)
        #expect(harness.noteRows().isEmpty)
        #expect(harness.notesBanner?.text == "Your notes live in Notion. Choose Connect Notion in the settings menu to list them here.")

        let hidden = try await Harness.started(config: "[defaults.notes]\nshow = false\n\n" + projects, graphQL: onePullRequest)
        #expect(hidden.notesBanner == nil)
    }

    @Test("a token that sees no Shipyard Notes page (another workspace's, or the page not shared) lists no notes, with no error rows, and a banner says why; once the page is shared it goes")
    func noEntryPage() async throws {
        let harness = try Harness(stored: "gho_stored", config: projects)
        try harness.notion.save("ntn_token")
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        try harness.stub.onNotion()
        harness.stub.on("POST", NotionStub.search, .json(#"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#))
        await harness.shipyard.start()
        await harness.readNotes()

        #expect(harness.noteRows().isEmpty)
        #expect(harness.noteErrors("shop").isEmpty)
        #expect(harness.notesBanner?.text == "Notion connected, but its token sees no Shipyard Notes page. Check the token is for your notes workspace, and share Shipyard Notes with the connection.")

        harness.stub.on("POST", NotionStub.search, try .fixture("notion-search-entry.json"))
        await harness.readNotes()

        #expect(harness.noteRows().count == 3)
        #expect(harness.notesBanner == nil)
    }

    @Test("the token the user pastes is checked with Notion, kept in the token store, and lists the notes; one Notion refuses is kept nowhere")
    func connect() async throws {
        let harness = try await Harness.started(config: projects, graphQL: onePullRequest)
        try harness.stub.onNotion()
        harness.stub.on(NotionStub.me, try NotionStub.unauthorized())

        #expect(await harness.shipyard.connectNotion(token: "ntn_wrong") == .rejected)
        #expect(try harness.notion.token() == nil)
        #expect(await harness.shipyard.connectNotion(token: "  ") == .empty)

        harness.stub.on(NotionStub.me, try .fixture("notion-me.json"))
        #expect(await harness.shipyard.connectNotion(token: " ntn_token\n") == .connected)
        #expect(try harness.notion.token() == "ntn_token")
        #expect(harness.shipyard.notionConnected)
        #expect(harness.noteRows().count == 3)
        #expect(harness.stub.requests("GET", NotionStub.me).last?.value(forHTTPHeaderField: "Authorization") == "Bearer ntn_token")
    }

    @Test("disconnecting deletes the token and takes every note out of the menu")
    func disconnect() async throws {
        let harness = try await Harness.withNotes()

        harness.shipyard.disconnectNotion()

        #expect(try harness.notion.token() == nil)
        #expect(!harness.shipyard.notionConnected)
        #expect(harness.noteRows().isEmpty)
        #expect(harness.notesTimer.armed == nil)
    }
}
