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
        name = "shipyard"
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

    @Test("a gh token's view shows the login, says Sign out leaves gh signed in, and gives gh's own sign-out command")
    func ghWords() {
        let page = PanelText.gitHubStatus(GitHubConnection(login: "yabepa", source: .gh))
        #expect(page.title == "GitHub")
        #expect(page.status == .init(text: "Signed in as @yabepa.", tone: .success))
        #expect(page.detail?.hasPrefix("Connected through the GitHub CLI `gh`. Sign out in shipyard doesn't sign out `gh`") == true)
        #expect(page.commands == ["gh auth logout"])
        #expect(page.primary == nil && page.alternative == nil)
    }

    @Test("a stored token's view shows the login and Sign in with GitHub as the source, with nothing to run")
    func storedWords() {
        let page = PanelText.gitHubStatus(GitHubConnection(login: "yabepa", source: .tokenStore))
        #expect(page.status == .init(text: "Signed in as @yabepa.", tone: .success))
        #expect(page.detail == "Connected with Sign in with GitHub. Sign out, in the settings menu, forgets the sign-in.")
        #expect(page.commands.isEmpty && page.primary == nil)
    }

    @Test("before GitHub says which account, the view says so in place of the login")
    func unknownLogin() {
        let page = PanelText.gitHubStatus(GitHubConnection(login: nil, source: .tokenStore))
        #expect(page.status?.text == "Signed in. GitHub hasn't said which account yet.")
    }
}
