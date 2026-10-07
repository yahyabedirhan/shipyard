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

    """

private let emptySearch = StubHTTP.Answer.json(#"{"object":"list","results":[],"has_more":false,"next_cursor":null}"#)

@MainActor
private extension Harness {
    /// Started with ntn as `ntn` and Notion answering as `NotionStub`
    /// records, Notion not connected, then the Notion view's check.
    static func notionChecked(_ ntn: FakeNtnRoute.State, workspace: (StubHTTP) -> Void = { _ in }) async throws -> Harness {
        let harness = try Harness(stored: "gho_stored", config: projects)
        harness.ntn.set(ntn)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        harness.graphQL([PullRequestsResponse("yahyabedirhan/shop", [PullRequestsResponse.PullRequest(1)]).answer])
        try harness.stub.onNotion()
        workspace(harness.stub)
        await harness.shipyard.start()
        await harness.shipyard.checkNotion()
        return harness
    }
}

/// The Notion view: where ntn stands, found through the route the notes
/// are read through, and the view's words for each status.
@Suite("The Notion view")
@MainActor
struct NotionViewTests {
    // MARK: - The check

    @Test("the check finds ntn missing, logged out, or logged in to its workspace by name, with or without a Shipyard Notes page", arguments: [
        (FakeNtnRoute.State.missing, false, NotionStatus.ntnMissing),
        (.loggedOut, false, .ntnLoggedOut),
        (.loggedIn, false, .ready(workspace: "Notes")),
        (.loggedIn, true, .noEntryPage(workspace: "Notes")),
    ])
    func check(ntn: FakeNtnRoute.State, noEntryPage: Bool, expected: NotionStatus) async throws {
        let harness = try await Harness.notionChecked(ntn) { stub in
            if noEntryPage { stub.on("POST", NotionStub.search, emptySearch) }
        }

        #expect(harness.shipyard.notionStatus == expected)
    }

    @Test("the check asks who ntn is (GET /v1/users/me) and searches for Shipyard Notes, and connects nothing: no notes, no notes timer")
    func checkAsksOnly() async throws {
        let harness = try await Harness.notionChecked(.loggedIn)

        #expect(harness.stub.requests("GET", NotionStub.me).count == 1)
        #expect(harness.stub.requests("POST", NotionStub.search).count == 1)
        #expect(harness.ntn.runs == 2)
        #expect(!harness.shipyard.notionConnected)
        #expect(harness.section("shop")?.rows.contains { $0.kind == .note } == false)
        #expect(harness.notesTimer.armed == nil)
    }

    @Test("Notion out of reach is its own status, with why; Check again finds it back")
    func unreachable() async throws {
        let harness = try await Harness.notionChecked(.loggedIn) { stub in
            stub.on("POST", NotionStub.search, .json(#"{"object":"error","status":503,"code":"service_unavailable","message":"try later"}"#, status: 503))
        }
        #expect(harness.shipyard.notionStatus == .failed(.http(503, code: "service_unavailable", message: "try later")))

        try harness.stub.onNotion()
        await harness.shipyard.checkNotion()

        #expect(harness.shipyard.notionStatus == .ready(workspace: "Notes"))
    }

    @Test("the settings menu marks Notion only when it's connected and ntn works")
    func mark() async throws {
        let harness = try await Harness.notionChecked(.loggedIn)
        #expect(!harness.shipyard.notionIsSetUp)

        await harness.shipyard.connectNotion()
        #expect(harness.shipyard.notionIsSetUp)
        let items = PanelText.settingsMenu(SetupStatus(cli: .unlinked, notion: harness.shipyard.notionIsSetUp), canSignOut: true)
        #expect(items.filter(\.isChecked).map(\.action) == [.open(.notion)])

        harness.ntn.set(.loggedOut)
        _ = await harness.notesTimer.fire()
        #expect(!harness.shipyard.notionIsSetUp)
    }

    // MARK: - The words

    @Test("no ntn: the install command and ntn login, each in a box, and Check again")
    func ntnMissingPage() {
        let page = PanelText.notionStatus(.ntnMissing, connected: false)
        #expect(page.title == "Notion")
        #expect(page.status == .init(text: "ntn isn't installed.", tone: .neutral))
        #expect(page.commands == ["curl -fsSL https://ntn.dev | bash", "ntn login"])
        #expect(page.primary == .init(title: "Check again", action: .checkNotion))
        #expect(page.alternatives.isEmpty)
    }

    @Test("ntn logged out: ntn login in a box, and Check again")
    func loggedOutPage() {
        let page = PanelText.notionStatus(.ntnLoggedOut, connected: false)
        #expect(page.status == .init(text: "ntn isn't logged in.", tone: .neutral))
        #expect(page.commands == ["ntn login"])
        #expect(page.primary == .init(title: "Check again", action: .checkNotion))
    }

    @Test("logged in: the workspace's name and Connect with ntn; once connected, the workspace, Disconnect under a divider, then under another that ntn stays logged in, with ntn logout")
    func readyPage() {
        let ready = PanelText.notionStatus(.ready(workspace: "Notes"), connected: false)
        #expect(ready.status == .init(text: "ntn is logged in to \u{201C}Notes\u{201D}.", tone: .success))
        #expect(ready.primary == .init(title: "Connect with ntn", action: .connectNotion))
        #expect(ready.commands.isEmpty && ready.alternatives.isEmpty)

        let connected = PanelText.notionStatus(.ready(workspace: "Notes"), connected: true)
        #expect(connected.status == .init(text: "Connected to \u{201C}Notes\u{201D} through ntn.", tone: .success))
        #expect(connected.primary == nil)
        #expect(connected.alternatives == [
            .init(
                line: "Disconnect to stop reading your notes. Shipyard then runs no ntn.",
                button: .init(title: "Disconnect", action: .disconnectNotion)
            ),
            .init(
                line: "Disconnecting leaves `ntn` logged in for your other tools. To log out of `ntn` too, run this in a terminal:",
                commands: ["ntn logout"]
            ),
        ])

        #expect(PanelText.notionStatus(.ready(workspace: nil), connected: false).status?.text == "ntn is logged in.")
    }

    @Test("no Shipyard Notes page: says so with the workspace's name, and how to change the workspace")
    func noEntryPagePage() {
        let page = PanelText.notionStatus(.noEntryPage(workspace: "Personal"), connected: false)
        #expect(page.status == .init(text: "ntn's workspace \u{201C}Personal\u{201D} has no Shipyard Notes page.", tone: .warning))
        #expect(page.detail == "Shipyard reads ntn's default workspace, which `ntn doctor` shows. To change it, log in again in Terminal and choose your notes workspace:")
        #expect(page.commands == ["ntn login"])
        #expect(page.primary == .init(title: "Check again", action: .checkNotion))
    }

    @Test("connected but ntn logged out: what's left to do is a warning, with Disconnect under the divider and no ntn logout")
    func connectedBroken() {
        let page = PanelText.notionStatus(.ntnLoggedOut, connected: true)
        #expect(page.status?.tone == .warning)
        #expect(page.primary == .init(title: "Check again", action: .checkNotion))
        #expect(page.alternatives.map(\.button?.action) == [.disconnectNotion])
    }

    @Test("while looking, out of reach, and in a demo run")
    func otherPages() {
        #expect(PanelText.notionStatus(nil, connected: false).status == .init(text: "Looking at ntn…", tone: .neutral))
        let failed = PanelText.notionStatus(.failed(.network("offline")), connected: false)
        #expect(failed.status == .init(text: "Can't reach Notion (offline).", tone: .warning))
        #expect(failed.primary?.action == .checkNotion)
        let demo = PanelText.notionStatus(.notRead, connected: false)
        #expect(demo.status?.text == "This run doesn't read notes.")
        #expect(demo.primary == nil)
    }
}
