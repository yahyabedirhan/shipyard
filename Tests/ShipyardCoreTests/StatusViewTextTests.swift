import Foundation
@testable import ShipyardCore
import Testing

/// The settings menu's items and marks, and the words of each status view,
/// as `PanelText` gives them to the panel.
@Suite("The settings menu and the status views")
struct StatusViewTextTests {
    private let command = "mkdir -p ~/.local/bin && ln -sf /Applications/Shipyard.app/Contents/Helpers/shipyard ~/.local/bin/shipyard"

    // MARK: - The settings menu

    @Test("the settings menu lists the configuration file, the four parts by name, then Sign out once signed in")
    func settingsMenuOrder() {
        let signedIn = PanelText.settingsMenu(SetupStatus(cli: .unlinked), canSignOut: true)
        #expect(signedIn.map(\.title) == [
            "Open configuration file", "GitHub…", "Notion…", "Shipyard Skill…", "Shipyard CLI…", "Sign out",
        ])
        #expect(signedIn.map(\.action) == [
            .openConfiguration, .open(.github), .open(.notion), .open(.skill), .open(.cli), .signOut,
        ])
        let signedOut = PanelText.settingsMenu(SetupStatus(cli: .unlinked), canSignOut: false)
        #expect(signedOut.map(\.title).last == "Shipyard CLI…")
    }

    @Test("the Shipyard CLI item has the check mark only while the CLI is linked, and no other item has a mark", arguments: [
        (CLILink.State.linked, true),
        (.unlinked, false),
        (.occupied(destination: "/opt/shipyard"), false),
        (.occupied(destination: nil), false),
        (.failed("no permission"), false),
        (.missingCLI, false),
        (.translocated, false),
    ])
    func cliMark(state: CLILink.State, checked: Bool) {
        let items = PanelText.settingsMenu(SetupStatus(cli: state), canSignOut: true)
        #expect(items.filter(\.isChecked).map(\.action) == (checked ? [.open(.cli)] : []))
    }

    @Test("the Shipyard Skill item has the check mark only while the skill is installed")
    func skillMark() {
        let installed = PanelText.settingsMenu(SetupStatus(cli: .unlinked, skill: true), canSignOut: true)
        #expect(installed.filter(\.isChecked).map(\.action) == [.open(.skill)])
        let notInstalled = PanelText.settingsMenu(SetupStatus(cli: .unlinked, skill: false), canSignOut: true)
        #expect(notInstalled.filter(\.isChecked).isEmpty)
    }

    // MARK: - Opening a view by name

    @Test("a view is named as the panel command takes it, in any case, and projects names none; another name is refused with the names")
    func viewNames() throws {
        #expect(SetupPart.allCases.map(\.commandName) == ["github", "notion", "skill", "cli"])
        #expect(try SetupPart.named("CLI") == .cli)
        #expect(try SetupPart.named("github") == .github)
        #expect(try SetupPart.named("Projects") == nil)
        #expect(throws: PanelRefusal("no view is named `gh`; the views are `github`, `notion`, `skill`, `cli`, or `projects` for the projects")) {
            try SetupPart.named("gh")
        }
    }

    // MARK: - The Shipyard CLI view

    @Test("linked, the CLI view shows the link's path and nothing to do")
    func cliLinked() {
        let page = PanelText.cliStatus(.linked, command: command)
        #expect(page.title == "Shipyard CLI")
        #expect(page.status == .init(text: "Linked at `~/.local/bin/shipyard`.", tone: .success))
        #expect(page.primary == nil && page.commands.isEmpty && page.alternative == nil)
    }

    @Test("unlinked, the CLI view offers Link, and the manual command in a box under a divider")
    func cliUnlinked() {
        let page = PanelText.cliStatus(.unlinked, command: command)
        #expect(page.status?.tone == .neutral)
        #expect(page.primary == .init(title: "Link", action: .linkCLI))
        #expect(page.alternative == .init(line: "Or link it yourself in a terminal:", commands: [command]))
    }

    @Test("occupied, the CLI view says what's at the path and why shipyard leaves it, with the command that replaces it")
    func cliOccupied() {
        let link = PanelText.cliStatus(.occupied(destination: "/Users/me/Downloads/Shipyard.app/Contents/Helpers/shipyard"), command: command)
        #expect(link.status == .init(
            text: "`~/.local/bin/shipyard` already links to `/Users/me/Downloads/Shipyard.app/Contents/Helpers/shipyard`.", tone: .warning
        ))
        #expect(link.detail?.hasPrefix("Shipyard never replaces what it didn't make there.") == true)
        #expect(link.commands == [command])
        #expect(link.primary == .init(title: "Try again", action: .linkCLI))
        let file = PanelText.cliStatus(.occupied(destination: nil), command: command)
        #expect(file.status?.text == "Something else is already at `~/.local/bin/shipyard`.")
    }

    @Test("failed, the CLI view gives the system's reason and the command to run instead")
    func cliFailed() {
        let page = PanelText.cliStatus(.failed("You don't have permission to save the file “shipyard” in the folder “bin”"), command: command)
        #expect(page.status == .init(
            text: "Couldn't link: You don't have permission to save the file “shipyard” in the folder “bin”.", tone: .warning
        ))
        #expect(page.detail == "Run this in a terminal instead:")
        #expect(page.commands == [command])
        #expect(page.primary?.title == "Try again")
    }

    @Test("with no CLI to link, or a translocated copy, the CLI view says why and what to do, with no button", arguments: [
        (CLILink.State.missingCLI, "Open the installed Shipyard.app to link it."),
        (.translocated, "Move Shipyard to Applications, open it from there, then link the CLI here."),
    ])
    func cliCannotLink(state: CLILink.State, detail: String) {
        let page = PanelText.cliStatus(state, command: command)
        #expect(page.status?.tone == .warning)
        #expect(page.detail == detail)
        #expect(page.primary == nil && page.commands.isEmpty && page.alternative == nil)
    }

    // MARK: - The Shipyard Skill view

    private let skillCommand = "npx -y skills add yahyabedirhan/shipyard -g -y"

    @Test("installed, the skill view says so and offers Update, which runs the install's command")
    func skillInstalled() {
        let page = PanelText.skillStatus(isInstalled: true, installation: .idle)
        #expect(page.title == "Shipyard Skill")
        #expect(page.status == .init(text: "Installed.", tone: .success))
        #expect(page.primary == .init(title: "Update", action: .installSkill))
        #expect(page.alternative == .init(line: "Or update it yourself in a terminal:", commands: [skillCommand]))
    }

    @Test("not installed, the skill view explains what the skill does and offers Install, and the command under a divider")
    func skillNotInstalled() {
        let page = PanelText.skillStatus(isInstalled: false, installation: .idle)
        #expect(page.lead == "The shipyard skill teaches your agents to edit your configuration, ping you and drive the app.")
        #expect(page.status == .init(text: "Not installed.", tone: .neutral))
        #expect(page.detail?.hasPrefix("With it, you can ask an agent to watch a repository for you") == true)
        #expect(page.primary == .init(title: "Install", action: .installSkill))
        #expect(page.alternative == .init(line: "Or install it yourself in a terminal:", commands: [skillCommand]))
    }

    @Test("running, the skill view says it's installing or updating, with Cancel alone", arguments: [
        (false, "Installing the skill…"),
        (true, "Updating the skill…"),
    ])
    func skillRunning(isInstalled: Bool, status: String) {
        let page = PanelText.skillStatus(isInstalled: isInstalled, installation: .running)
        #expect(page.status == .init(text: status, tone: .neutral))
        #expect(page.primary == .init(title: "Cancel", action: .cancelSkillInstall))
        #expect(page.commands.isEmpty && page.alternative == nil && page.output == nil)
    }

    @Test("installed by the view, it shows what npx printed, and Update again")
    func skillJustInstalled() {
        let page = PanelText.skillStatus(isInstalled: true, installation: .finished(.installed(output: "Installed 1 skill")))
        #expect(page.status == .init(text: "Installed.", tone: .success))
        #expect(page.output == "Installed 1 skill")
        #expect(page.primary?.title == "Update")
        let quiet = PanelText.skillStatus(isInstalled: true, installation: .finished(.installed(output: "")))
        #expect(quiet.output == nil)
    }

    @Test("failed, the skill view shows the output, the command to copy and Try again")
    func skillFailed() {
        let page = PanelText.skillStatus(isInstalled: false, installation: .finished(.failed(output: "npm ERR! network")))
        #expect(page.status == .init(text: "Couldn't install the skill.", tone: .warning))
        #expect(page.output == "npm ERR! network")
        #expect(page.commands == [skillCommand])
        #expect(page.primary == .init(title: "Try again", action: .installSkill))
        let update = PanelText.skillStatus(isInstalled: true, installation: .finished(.failed(output: "npm ERR! network")))
        #expect(update.status?.text == "Couldn't update the skill.")
    }

    @Test("with no npx, the skill view shows the command in a box to copy")
    func skillNoNpx() {
        let page = PanelText.skillStatus(isInstalled: false, installation: .finished(.npxNotFound(command: skillCommand)))
        #expect(page.status == .init(text: "`npx` wasn't found.", tone: .warning))
        #expect(page.detail?.hasSuffix("Run this in a terminal instead:") == true)
        #expect(page.commands == [skillCommand])
        #expect(page.primary?.title == "Try again")
    }

    @Test("stopped after the timeout, the skill view says how long it ran, with the command and Try again")
    func skillTimedOut() {
        let page = PanelText.skillStatus(isInstalled: false, installation: .timedOut(seconds: 180))
        #expect(page.status == .init(text: "The install took too long.", tone: .warning))
        #expect(page.detail == "It was stopped after 3 min. Try again, or run it in a terminal:")
        #expect(page.commands == [skillCommand])
        #expect(page.primary?.title == "Try again")
    }
}
