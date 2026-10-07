import Foundation
@testable import ShipyardCore
import Testing

/// The GitHub view: the connection `Shipyard` reports while signed in (the
/// view's account and source, the settings menu's mark), none while signed
/// out (the view shows the onboarding content then), and the view's words.
@Suite("The GitHub view")
@MainActor
struct GitHubViewTests {
    private let withProjects = """
        [[projects]]
        slug = "shipyard"
        repositories = ["yahyabedirhan/shipyard"]

        """

    private func marked(_ harness: Harness) -> Bool {
        let status = SetupStatus(cli: .unlinked, github: harness.shipyard.gitHubConnection != nil)
        let items = PanelText.settingsMenu(status, canSignOut: true)
        return items.contains { $0.action == .open(.github) && $0.isChecked }
    }

    @Test("signed in, the connection names the login and the source, gh's or the stored token's, and GitHub is marked", arguments: [
        (nil as String?, "gho_fromgh" as String?, TokenSource.gh),
        ("gho_stored", nil, .tokenStore),
    ])
    func signedIn(stored: String?, gh: String?, source: TokenSource) async throws {
        let harness = try Harness(stored: stored, gh: gh, config: withProjects)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)

        await harness.shipyard.start()

        #expect(harness.shipyard.gitHubConnection == GitHubConnection(login: "yabepa", source: source))
        #expect(marked(harness))
    }

    @Test("signed out, there is no connection, so the view shows the onboarding content and GitHub has no mark")
    func signedOut() async throws {
        let harness = try Harness()

        await harness.shipyard.start()

        #expect(harness.shipyard.gitHubConnection == nil)
        #expect(!marked(harness))
    }

    @Test("signing out ends the connection and takes the mark away")
    func signOut() async throws {
        let harness = try Harness(gh: "gho_fromgh", config: withProjects)
        harness.stub.on(Harness.userURL, Harness.viewerAnswer)
        await harness.shipyard.start()

        harness.shipyard.signOut()

        #expect(harness.shipyard.gitHubConnection == nil)
        #expect(!marked(harness))
    }

    @Test("GitHub out of reach still signs in: the connection has its source, and no login yet")
    func offline() async throws {
        let harness = try Harness(stored: "gho_stored")
        harness.stub.on(Harness.userURL, .failure())

        await harness.shipyard.start()

        #expect(harness.shipyard.gitHubConnection == GitHubConnection(login: nil, source: .tokenStore))
    }

    // MARK: - The words

    private let signOutSegment = PanelText.StatusPage.Alternative(
        line: "Sign out to stop listing your pull requests, issues and workflow runs.",
        button: .init(title: "Sign out", action: .signOut)
    )

    @Test("a gh token's view shows the login, then Sign out under a divider, then under another that gh stays signed in, with gh's own sign-out command")
    func ghWords() {
        let page = PanelText.gitHubStatus(GitHubConnection(login: "yabepa", source: .gh))
        #expect(page.title == "GitHub")
        #expect(page.status == .init(text: "Signed in as @yabepa.", tone: .success))
        #expect(page.detail == "Connected through the GitHub CLI `gh`.")
        #expect(page.commands.isEmpty && page.primary == nil)
        #expect(page.alternatives == [
            signOutSegment,
            .init(
                line: "Signing out here leaves `gh` signed in, so shipyard connects through it again at its next launch. "
                    + "To sign out of `gh` too, run this in a terminal:",
                commands: ["gh auth logout"]
            ),
        ])
    }

    @Test("a stored token's view shows the login and Sign in with GitHub as the source, then Sign out under a divider, and nothing about gh")
    func storedWords() {
        let page = PanelText.gitHubStatus(GitHubConnection(login: "yabepa", source: .tokenStore))
        #expect(page.status == .init(text: "Signed in as @yabepa.", tone: .success))
        #expect(page.detail == "Connected with Sign in with GitHub.")
        #expect(page.commands.isEmpty && page.primary == nil)
        #expect(page.alternatives == [signOutSegment])
    }

    @Test("before GitHub says which account, the view says so in place of the login")
    func unknownLogin() {
        let page = PanelText.gitHubStatus(GitHubConnection(login: nil, source: .tokenStore))
        #expect(page.status?.text == "Signed in. GitHub hasn't said which account yet.")
    }
}
