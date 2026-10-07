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
    /// Started with `config`, GitHub answering one pull request, ntn
    /// logged in and Notion answering as `NotionStub` records (then as
    /// `workspace` changes them), then the notes timer's first read.
    static func withNotes(config: String = projects, query: [StubHTTP.Answer]? = nil, workspace: (StubHTTP) throws -> Void = { _ in }) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.ntn.set(.loggedIn)
        harness.connectNotionBeforeStart()
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        try harness.stub.onNotion(query: query)
        try workspace(harness.stub)
        await harness.shipyard.start()
        await harness.readNotes()
        return harness
    }

    /// Started with `config`, GitHub answering one pull request, ntn
    /// logged in and Notion answering as `NotionStub` records, but Notion
    /// not connected: as a user who never pressed Connect with ntn.
    static func notConnected(config: String = projects) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: config)
        harness.ntn.set(.loggedIn)
        try harness.answer()
        await harness.shipyard.start()
        return harness
    }

    /// GitHub answering one pull request, and Notion as `NotionStub` records.
    func answer() throws {
        stub.on(Harness.userURL, Harness.viewerAnswer)
        graphQL([onePullRequest])
        try stub.onNotion()
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

    @Test("Notion is asked as API version 2025-09-03, with no token of the app's own (ntn signs the request), for open notes only, newest first")
    func requests() async throws {
        let harness = try await Harness.withNotes()

        let query = try #require(harness.shopQueries.first)
        #expect(query.value(forHTTPHeaderField: "Notion-Version") == "2025-09-03")
        #expect(query.value(forHTTPHeaderField: "Authorization") == nil)
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
        let harness = try await Harness.withNotes { stub in
            stub.on(NotionStub.entryChildren, .json(#"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#))
        }

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
        harness.ntn.set(.loggedIn)
        harness.connectNotionBeforeStart()
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

    @Test("ntn logged out lists no notes, with no error rows and no new-note icons, and a banner says to log in; logging in brings them back")
    func ntnLoggedOut() async throws {
        let harness = try await Harness.withNotes()
        harness.ntn.set(.loggedOut)

        await harness.readNotes()

        #expect(harness.noteRows().isEmpty)
        #expect(harness.noteErrors("shop").isEmpty)
        #expect(harness.section("shop")?.newNote == nil)
        #expect(harness.notesBanner?.text == "ntn isn't logged in. Run ntn login in Terminal, choosing your notes workspace, to list your notes here.")
        #expect(harness.notesTimer.armed == 60)

        harness.ntn.set(.loggedIn)
        await harness.readNotes()

        #expect(harness.noteRows().count == 3)
        #expect(harness.section("shop")?.newNote == .ready)
        #expect(harness.notesBanner == nil)
    }

    @Test("connected without ntn, Notion is never asked, no project lists notes, and a banner says to install ntn, with Open… to the Notion view; installed, the next read lists them; with every project's notes hidden there's no banner")
    func noNtn() async throws {
        let harness = try Harness(stored: "gho_stored", config: projects)
        harness.connectNotionBeforeStart()
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        try harness.stub.onNotion()
        await harness.shipyard.start()

        await harness.shipyard.panelOpened()

        #expect(harness.stub.notionRequests.isEmpty)
        #expect(harness.noteRows().isEmpty)
        #expect(harness.noteErrors("shop").isEmpty)
        #expect(harness.notesBanner?.text == "Your notes live in Notion, and shipyard reads them with ntn, Notion's CLI. Install ntn and run ntn login to list them here.")
        #expect(harness.notesBanner?.opens == .notion)
        #expect(harness.notesTimer.armed == 60)

        harness.ntn.set(.loggedIn)
        await harness.readNotes()
        #expect(harness.noteRows().count == 3)
        #expect(harness.notesBanner == nil)

        let hidden = try Harness(stored: "gho_stored", config: "[defaults.notes]\nshow = false\n\n" + projects)
        hidden.connectNotionBeforeStart()
        hidden.stub.on(Harness.userURL, Harness.viewerAnswer)
        hidden.graphQL([onePullRequest])
        await hidden.shipyard.start()
        #expect(hidden.notesBanner == nil)
    }

    @Test("ntn's workspace without a Shipyard Notes page (ntn's default workspace isn't the notes workspace) lists no notes, with no error rows, and a banner says why; once the page is there it goes")
    func noEntryPage() async throws {
        let harness = try Harness(stored: "gho_stored", config: projects)
        harness.ntn.set(.loggedIn)
        harness.connectNotionBeforeStart()
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([onePullRequest])
        try harness.stub.onNotion()
        harness.stub.on("POST", NotionStub.search, .json(#"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#))
        await harness.shipyard.start()
        await harness.readNotes()

        #expect(harness.noteRows().isEmpty)
        #expect(harness.noteErrors("shop").isEmpty)
        #expect(harness.notesBanner?.text == "ntn's workspace has no Shipyard Notes page. Run ntn doctor to see its default workspace, and make it your notes workspace.")

        harness.stub.on("POST", NotionStub.search, try .fixture("notion-search-entry.json"))
        await harness.readNotes()

        #expect(harness.noteRows().count == 3)
        #expect(harness.notesBanner == nil)
    }

    // MARK: - Connecting Notion

    @Test("before Connect with ntn no ntn runs, at start, on opening the menu or on a configuration change: no notes, no banner, no new-note icons, no notes timer, and the notes check is refused")
    func notConnected() async throws {
        let harness = try await Harness.notConnected()
        await harness.shipyard.panelOpened()
        try harness.writeConfig(projects + "[[projects]]\nname = \"docs\"\nrepositories = [\"yahyabedirhan/docs\"]\n")
        await harness.shipyard.reloadConfiguration()

        #expect(harness.ntn.runs == 0)
        #expect(harness.stub.notionRequests.isEmpty)
        #expect(harness.noteRows().isEmpty)
        #expect(harness.notesBanner == nil)
        #expect(harness.section("shop")?.newNote == nil)
        #expect(harness.notesTimer.armed == nil)
        #expect(!harness.shipyard.notionIsSetUp)
        #expect(await harness.shipyard.checkNotes() == nil)
        #expect(harness.ntn.runs == 0)
        #expect(PanelText.notesCheckRefusal(canReadNotes: harness.shipyard.canReadNotes)
            == "Notion isn't connected, so shipyard runs no ntn: open Notion… in shipyard's settings menu and press Connect with ntn")
    }

    @Test("Connect with ntn reads the notes at once, with the new-note icons and the notes timer, and keeps the flag in state.json, so a restart lists them without connecting again")
    func connect() async throws {
        let harness = try await Harness.notConnected()

        await harness.shipyard.connectNotion()

        #expect(harness.noteRows().count == 3)
        #expect(harness.section("shop")?.newNote == .ready)
        #expect(harness.notesTimer.armed == 60)
        #expect(harness.shipyard.notionIsSetUp)
        #expect(harness.shipyard.appStateStore.state.notionConnected)
        let saved = try String(contentsOf: harness.stateURL, encoding: .utf8)
        #expect(saved.contains("\"notionConnected\" : true"))

        let relaunched = harness.relaunched()
        try relaunched.answer()
        await relaunched.shipyard.start()
        await relaunched.readNotes()

        #expect(relaunched.shipyard.notionConnected)
        #expect(relaunched.noteRows().count == 3)
        #expect(relaunched.section("shop")?.newNote == .ready)
    }

    @Test("Disconnect takes the notes, the notes banner and the new-note icons away, stops the notes timer and runs no ntn after, across a restart too")
    func disconnect() async throws {
        let harness = try await Harness.withNotes()
        #expect(harness.noteRows().count == 3)

        harness.shipyard.disconnectNotion()

        #expect(harness.noteRows().isEmpty)
        #expect(harness.section("shop")?.newNote == nil)
        #expect(harness.notesTimer.armed == nil)
        #expect(!harness.shipyard.notionIsSetUp)
        #expect(!harness.shipyard.appStateStore.state.notionConnected)
        let runs = harness.ntn.runs
        await harness.shipyard.panelOpened()
        #expect(harness.ntn.runs == runs)

        let relaunched = harness.relaunched()
        try relaunched.answer()
        await relaunched.shipyard.start()
        await relaunched.shipyard.panelOpened()
        #expect(relaunched.ntn.runs == 0)
        #expect(relaunched.noteRows().isEmpty)

        // Connected again with ntn logged out, the banner says to log in; Disconnect takes it away.
        relaunched.ntn.set(.loggedOut)
        await relaunched.shipyard.connectNotion()
        #expect(relaunched.notesBanner?.kind == .notes)
        relaunched.shipyard.disconnectNotion()
        #expect(relaunched.notesBanner == nil)
    }
}
