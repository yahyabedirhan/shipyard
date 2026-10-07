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

    @Test("the parts not built yet open a placeholder with their name and what they're for")
    func placeholders() {
        for part in [SetupPart.notion, .skill] {
            let page = PanelText.placeholderStatus(part)
            #expect(page.title == PanelText.statusTitle(part))
            #expect(page.lead == PanelText.statusLead(part))
            #expect(page.primary == nil)
        }
    }
}
