import Foundation

// The GitHub view's words while signed in. Signed out, the view shows the
// signed-out onboarding view's content instead (`PanelText.connect`).
extension PanelText {
    /// The command that signs the GitHub CLI out, which shipyard's Sign out doesn't.
    public static let ghLogout = "gh auth logout"

    /// The GitHub view for `connection`: the account as `@login` and the
    /// token's source; then, under a divider, what Sign out does with its
    /// button; then, for a `gh` token only, under another divider, that `gh`
    /// stays signed in, with the command that signs it out.
    public static func gitHubStatus(_ connection: GitHubConnection) -> StatusPage {
        var page = StatusPage(title: statusTitle(.github), lead: statusLead(.github))
        let account = connection.login.map { "Signed in as @\($0)." } ?? "Signed in. GitHub hasn't said which account yet."
        page.status = .init(text: account, tone: .success)
        let signOut = StatusPage.Alternative(
            line: "Sign out to stop listing your pull requests, issues and workflow runs.",
            button: .init(title: "Sign out", action: .signOut)
        )
        switch connection.source {
        case .gh:
            page.detail = "Connected through the GitHub CLI `gh`."
            page.alternatives = [
                signOut,
                .init(
                    line: "Signing out here leaves `gh` signed in, so shipyard connects through it again at its next launch. "
                        + "To sign out of `gh` too, run this in a terminal:",
                    commands: [ghLogout]
                ),
            ]
        case .tokenStore:
            page.detail = "Connected with Sign in with GitHub."
            page.alternatives = [signOut]
        }
        return page
    }
}
