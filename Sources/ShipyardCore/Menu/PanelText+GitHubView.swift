import Foundation

// The GitHub view's words while signed in. Signed out, the view shows the
// signed-out onboarding view's content instead (`PanelText.connect`).
extension PanelText {
    /// The command that signs the GitHub CLI out, which shipyard's Sign out doesn't.
    public static let ghLogout = "gh auth logout"

    /// The GitHub view for `connection`: the account as `@login` and the
    /// token's source, then how to sign out under a divider. A `gh` token
    /// says that Sign out in shipyard leaves `gh` signed in, with the
    /// command that signs it out.
    public static func gitHubStatus(_ connection: GitHubConnection) -> StatusPage {
        var page = StatusPage(title: statusTitle(.github), lead: statusLead(.github))
        let account = connection.login.map { "Signed in as @\($0)." } ?? "Signed in. GitHub hasn't said which account yet."
        page.status = .init(text: account, tone: .success)
        switch connection.source {
        case .gh:
            page.detail = "Connected through the GitHub CLI `gh`."
            page.alternative = .init(
                line: "Sign out in shipyard doesn't sign out `gh`, so shipyard connects through it again at the next launch. "
                    + "To sign out of `gh` too, run this in a terminal:",
                commands: [ghLogout]
            )
        case .tokenStore:
            page.detail = "Connected with Sign in with GitHub."
            page.alternative = .init(line: "To sign out, choose Sign out in the settings menu. Shipyard then forgets the sign-in.")
        }
        return page
    }
}
