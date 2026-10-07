import Foundation

// The Shipyard Skill view's words (`StatusView`).
extension PanelText {
    /// The Shipyard Skill view while the skill `isInstalled` (`SkillDetector`)
    /// and the install is in `state`: installed, with Update; not installed,
    /// with Install; the running install with Cancel; and how it ended, with
    /// what the command printed, and Try again with the command to copy when
    /// it didn't install. Update and Install run the same command.
    public static func skillStatus(isInstalled: Bool, installation state: SkillInstallation.State) -> StatusPage {
        let command = SkillInstaller.command
        var page = StatusPage(title: statusTitle(.skill), lead: statusLead(.skill))
        let tryAgain = StatusPage.Button(title: "Try again", action: .installSkill)
        let verb = isInstalled ? "update" : "install"
        switch state {
        case .idle where isInstalled:
            page.status = .init(text: "Installed.", tone: .success)
            page.detail = "Update gets the newest skill. Shipyard runs `npx` in your login shell."
            page.primary = .init(title: "Update", action: .installSkill)
            page.alternative = .init(line: "Or update it yourself in a terminal:", commands: [command])
        case .idle:
            page.status = .init(text: "Not installed.", tone: .neutral)
            page.detail = "With it, you can ask an agent to watch a repository for you, or to ping you when its pull request is ready. Shipyard installs it with `npx` in your login shell."
            page.primary = .init(title: "Install", action: .installSkill)
            page.alternative = .init(line: "Or install it yourself in a terminal:", commands: [command])
        case .running:
            page.status = .init(text: isInstalled ? "Updating the skill…" : "Installing the skill…", tone: .neutral)
            page.detail = "Running `npx` in your login shell. It can take a minute."
            page.primary = .init(title: "Cancel", action: .cancelSkillInstall)
        case .finished(.installed(let output)):
            page.status = .init(text: "Installed.", tone: .success)
            page.detail = "Your agents can now use the shipyard skill."
            page.output = output.isEmpty ? nil : output
            page.primary = .init(title: "Update", action: .installSkill)
        case .finished(.failed(let output)):
            page.status = .init(text: "Couldn't \(verb) the skill.", tone: .warning)
            page.detail = "The command failed. Try again, or run it in a terminal:"
            page.output = output
            page.commands = [command]
            page.primary = tryAgain
        case .finished(.npxNotFound(let command)):
            page.status = .init(text: "`npx` wasn't found.", tone: .warning)
            page.detail = "Shipyard couldn't find `npx` (it comes with Node.js) in your login shell. Run this in a terminal instead:"
            page.commands = [command]
            page.primary = tryAgain
        case .timedOut(let seconds):
            page.status = .init(text: "The \(verb) took too long.", tone: .warning)
            page.detail = "It was stopped after \(interval(seconds)). Try again, or run it in a terminal:"
            page.commands = [command]
            page.primary = tryAgain
        }
        return page
    }
}
