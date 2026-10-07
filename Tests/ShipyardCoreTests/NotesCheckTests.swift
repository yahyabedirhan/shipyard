import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ShipyardCore
import Testing

private let projects = """
    [[projects]]
    slug = "shop"
    repositories = ["yahyabedirhan/shop"]

    [[projects]]
    slug = "blog"
    repositories = ["yahyabedirhan/blog"]

    """

private let empty = #"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#

/// A list answer of `blocks`, each a JSON object.
private func list(_ blocks: [String]) -> StubHTTP.Answer {
    .json(#"{"object":"list","results":[\#(blocks.joined(separator: ","))],"has_more":false,"next_cursor":null}"#)
}

/// A child block of `type` titled `title`.
private func child(_ type: String, _ id: String, _ title: String) -> String {
    #"{"object":"block","id":"\#(id)","type":"\#(type)","in_trash":false,"\#(type)":{"title":"\#(title)"}}"#
}

/// A table row of plain-text cells.
private func row(_ cells: [String]) -> String {
    let cells = cells.map { #"[{"type":"text","plain_text":"\#($0)"}]"# }.joined(separator: ",")
    return #"{"object":"block","id":"r","type":"table_row","table_row":{"cells":[\#(cells)]}}"#
}

private let tableID = "27a0c3e1-8f4b-80aa-b009-0000000000a1"

@MainActor
private extension Harness {
    /// Started with ntn logged in and Notion answering as
    /// `NotionStub` records, both databases' schemas included.
    static func withWorkspace() async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: projects)
        harness.ntn.set(.loggedIn)
        harness.connectNotionBeforeStart()
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer])
        try harness.stub.onNotion()
        try harness.stub.onNewNote()
        await harness.shipyard.start()
        return harness
    }

    /// The home page lists `rows` (project, prefix) in its Projects index.
    func index(_ rows: [[String]]) {
        stub.on(NotionStub.entryChildren, list([
            child("child_page", NotionStub.projectsPage, "Projects"),
            child("child_page", "27a0c3e1-8f4b-80d2-9a51-c7e3b2f0d103", "Agent guide"),
            #"{"object":"block","id":"\#(tableID)","type":"table","in_trash":false,"table":{}}"#,
        ]))
        stub.on(NotionStub.url("blocks/\(tableID)/children"), list(([["Project", "Prefix", "Notes"]] + rows).map(row)))
    }

    func check() async throws -> NotesCheckReport {
        try #require(await shipyard.checkNotes())
    }
}

/// `shipyard notes check` as the app answers it (`Shipyard.checkNotes`):
/// the notes workspace read through ntn, the way the menu reads
/// it, and checked against the layout the app expects; over recorded
/// Notion answers.
@Suite("The notes check")
@MainActor
struct NotesCheckTests {
    @Test("a workspace in order: each project's line (its prefix and open notes, or no database yet), no problems, and the verdict")
    func inOrder() async throws {
        let harness = try await Harness.withWorkspace()
        harness.stub.on(NotionStub.projectsChildren, list([child("child_database", NotionStub.shopDatabase, "shop")]))
        harness.index([["shop", "SHOP", "shop"]])

        let report = try await harness.check()

        #expect(report.problems.isEmpty)
        #expect(!report.hasErrors)
        #expect(report.text == """
            shop  SHOP  3 open notes
            blog  no database yet (the first note creates it)

            the notes workspace is in order

            """)
    }

    @Test("what hides notes from the app is an error: a database outside Projects, one missing a property; what agents keep tidy is a warning")
    func problems() async throws {
        let harness = try await Harness.withWorkspace()
        // `Shop` (SHO, no Labels or Status) matches no project; the index lacks both.
        harness.index([["blog", "BLOG", ""]])
        harness.stub.on(NotionStub.entryChildren, list([
            child("child_page", NotionStub.projectsPage, "Projects"),
            child("child_database", "27a0c3e1-8f4b-80aa-b00a-0000000000a2", "blog"),
            #"{"object":"block","id":"\#(tableID)","type":"table","in_trash":false,"table":{}}"#,
        ]))

        let report = try await harness.check()

        #expect(report.problems.map { "\($0.severity.rawValue): \($0.message)" } == [
            "error: the database \"blog\" is directly under Shipyard Notes, where the app doesn't look: move it under Projects",
            "warning: Shipyard Notes has no \"Agent guide\" page for agents",
            "warning: the database \"Shop\" matches no project that shows notes, so the menu doesn't list it",
            "error: \"Shop\" has no Labels property (multi_select)",
            "error: \"Shop\" has no Status property (select)",
            "warning: the Projects index on Shipyard Notes has no row for \"Shop\"",
            "warning: the Projects index on Shipyard Notes has no row for \"shop\"",
            "warning: the Projects index lists \"blog\", which has no database under Projects",
        ])
        #expect(report.hasErrors)
        #expect(report.text.hasSuffix("3 errors, 5 warnings\n"))
    }

    @Test("ntn's workspace without a Shipyard Notes page is one error and no project lines; ntn logged out is one error too")
    func noEntryPage() async throws {
        let harness = try await Harness.withWorkspace()
        harness.stub.on("POST", NotionStub.search, .json(empty))

        let report = try await harness.check()

        #expect(report.projects.isEmpty)
        #expect(report.problems == [.init(.error, "ntn's workspace has no page titled \"Shipyard Notes\": run ntn doctor and check that its default workspace is the notes workspace")])

        harness.ntn.set(.loggedOut)
        let loggedOut = try await harness.check()
        #expect(loggedOut.projects.isEmpty)
        #expect(loggedOut.problems.map(\.message) == ["Notion: \(PanelText.noteError(.unauthorized))"])
    }

    @Test("a database's No. without a prefix is an error, as is a Status without both options")
    func prefixes() {
        let schema: [String: NotesSchemaProperty] = [
            "Name": .init(type: "title"),
            "No.": .init(type: "unique_id"),
            "Labels": .init(type: "multi_select"),
            "Status": .init(type: "select", options: ["Open"]),
        ]

        #expect(NotesCheck.schemaProblems(schema, database: "blog").map(\.message) == [
            "\"blog\"'s No. has no prefix, so its notes have no NAME-7 numbers",
            "\"blog\"'s Status has no Archived option",
        ])
    }
}
