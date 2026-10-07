import Foundation

// The Notion view's words (`StatusView`): where ntn stands, what to run in
// Terminal, Connect with ntn and Disconnect.
extension PanelText {
    /// The command Notion's installer gives, which puts `ntn` in `~/.local/bin`.
    public static let ntnInstall = "curl -fsSL https://ntn.dev | bash"
    /// ntn's login, run in Terminal, where the user picks the notes workspace.
    public static let ntnLogin = "ntn login"

    /// The Notion view for `status` (`nil` while it's being looked at),
    /// `connected` or not: no ntn, the install command and `ntn login`;
    /// logged out, `ntn login`; logged in, the workspace's name and Connect
    /// with ntn; a workspace without Shipyard Notes, how to change it. Check
    /// again looks again while something is left to do, and once connected
    /// Disconnect shows under a divider.
    public static func notionStatus(_ status: NotionStatus?, connected: Bool) -> StatusPage {
        var page = StatusPage(title: statusTitle(.notion), lead: statusLead(.notion))
        let checkAgain = StatusPage.Button(title: "Check again", action: .checkNotion)
        // Not connected, nothing is broken yet: what's left to do is neutral.
        let toDo: SkillInstall.Tone = connected ? .warning : .neutral
        switch status {
        case nil:
            page.status = .init(text: "Looking at ntn…", tone: .neutral)
        case .notRead:
            page.status = .init(text: "This run doesn't read notes.", tone: .neutral)
            page.detail = "A demo run never asks your ntn."
        case .ntnMissing:
            page.status = .init(text: "ntn isn't installed.", tone: toDo)
            page.detail = "Install ntn, then log in and choose your notes workspace. Run these in Terminal:"
            page.commands = [ntnInstall, ntnLogin]
            page.primary = checkAgain
        case .ntnLoggedOut:
            page.status = .init(text: "ntn isn't logged in.", tone: toDo)
            page.detail = "Log in in Terminal, and choose your notes workspace:"
            page.commands = [ntnLogin]
            page.primary = checkAgain
        case .noEntryPage(let workspace):
            let name = workspace.map { "ntn's workspace \(quoted($0))" } ?? "ntn's workspace"
            page.status = .init(text: "\(name) has no Shipyard Notes page.", tone: .warning)
            page.detail = "Shipyard reads ntn's default workspace, which `ntn doctor` shows. To change it, log in again in Terminal and choose your notes workspace:"
            page.commands = [ntnLogin]
            page.primary = checkAgain
        case .ready(let workspace):
            let name = workspace.map { " to \(quoted($0))" } ?? ""
            if connected {
                page.status = .init(text: "Connected\(name) through ntn.", tone: .success)
                page.detail = "Shipyard reads your notes every minute and when you open the menu."
            } else {
                page.status = .init(text: "ntn is logged in\(name).", tone: .success)
                page.detail = "Its Shipyard Notes page holds your notes. Connect to list them under your projects."
                page.primary = .init(title: "Connect with ntn", action: .connectNotion)
            }
        case .failed(let error):
            // "Can't reach Notion (…).", "Notion answered 503: …."
            let why = noteError(error)
            page.status = .init(text: why.prefix(1).uppercased() + why.dropFirst() + ".", tone: .warning)
            page.primary = checkAgain
        }
        if connected {
            page.alternative = .init(
                line: "Disconnect to stop reading your notes. Shipyard then runs no ntn.",
                button: .init(title: "Disconnect", action: .disconnectNotion)
            )
        }
        return page
    }

    /// Why `shipyard notes check` ran no `ntn`: a demo run reads no
    /// notes; otherwise Notion isn't connected yet.
    public static func notesCheckRefusal(canReadNotes: Bool) -> String {
        canReadNotes
            ? "Notion isn't connected, so shipyard runs no ntn: open Notion… in shipyard's settings menu and press Connect with ntn"
            : "this run doesn't read notes"
    }

    /// A workspace's name in curly quotes: “Notes”.
    private static func quoted(_ name: String) -> String {
        "\u{201C}\(name)\u{201D}"
    }
}
