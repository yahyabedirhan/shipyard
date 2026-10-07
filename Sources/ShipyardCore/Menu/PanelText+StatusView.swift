import Foundation

// The settings menu's words, and each status view's (`StatusView`): one
// page shape for every part, in the signed-out onboarding view's style.
extension PanelText {
    // MARK: - The settings menu

    /// One item of the header's settings menu: its words, what a click
    /// does, and whether it shows the set-up mark on its right.
    public struct SettingsItem: Equatable, Sendable {
        public enum Action: Equatable, Sendable {
            /// Opens `config.toml`.
            case openConfiguration
            /// Opens the part's status view.
            case open(SetupPart)
            /// Signs out of GitHub.
            case signOut
        }

        public var title: String
        public var action: Action
        /// Whether `setUpMark` shows on the item's right: only for a part that is set up.
        public var isChecked = false
    }

    /// The mark on the right of a part's item when the part is set up.
    public static let setUpMark = "✓"

    /// The settings menu: Open configuration file, then each part's Set up
    /// item (a check mark when it's set up, no mark otherwise), then Sign
    /// out when `canSignOut`.
    public static func settingsMenu(_ status: SetupStatus, canSignOut: Bool) -> [SettingsItem] {
        var items = [SettingsItem(title: "Open configuration file", action: .openConfiguration)]
        items += SetupPart.allCases.map { part in
            SettingsItem(title: settingsTitle(part), action: .open(part), isChecked: status.isSetUp(part))
        }
        if canSignOut { items.append(SettingsItem(title: "Sign out", action: .signOut)) }
        return items
    }

    // MARK: - A status view

    /// What a status view shows, top to bottom, under its ‹ Back row: the
    /// logo badge and `title`, the `lead` line, the `status` line, a
    /// `detail` line on what to do, a command's `output`, `commands` each in
    /// a box with a copy button, the `primary` full-width button, and an
    /// `alternative` under a divider. The words may hold Markdown code spans
    /// (`CodeText`).
    public struct StatusPage: Equatable, Sendable {
        /// Where the part stands, with its tone's icon.
        public struct Status: Equatable, Sendable {
            public var text: String
            public var tone: SkillInstall.Tone
        }

        /// What a button does; the view runs it.
        public enum Action: Equatable, Sendable {
            /// Links the CLI (`CLILink.makeLink`), or looks again at what's in the way.
            case linkCLI
            /// Installs or updates the agent skill (`SkillInstallation.start`).
            case installSkill
            /// Stops the running skill install (`SkillInstallation.cancel`).
            case cancelSkillInstall
            /// Looks at ntn again (`Shipyard.checkNotion()`): Check again.
            case checkNotion
            /// Connects Notion, reads the notes and shows the projects (`Shipyard.connectNotion()`).
            case connectNotion
            /// Disconnects Notion (`Shipyard.disconnectNotion()`).
            case disconnectNotion
        }

        /// A full-width button.
        public struct Button: Equatable, Sendable {
            public var title: String
            public var action: Action
        }

        /// Another way to the same end, under a divider: a line, the
        /// commands it means and, optionally, its own button.
        public struct Alternative: Equatable, Sendable {
            public var line: String
            public var commands: [String] = []
            public var button: Button?
        }

        public var title: String
        public var lead: String
        public var status: Status?
        public var detail: String?
        /// What a command printed, when it's worth showing, as plain text.
        public var output: String?
        public var commands: [String] = []
        public var primary: Button?
        public var alternative: Alternative?
    }

    /// The row at the top of every status view that shows the projects again.
    public static let back = "‹ Back"

    /// A part's item in the settings menu: "Set up", then the part, then "…".
    public static func settingsTitle(_ part: SetupPart) -> String {
        switch part {
        case .github: "Set up GitHub"
        case .notion: "Set up Notion"
        case .skill: "Set up /shipyard skill"
        case .cli: "Set up shipyard CLI"
        }
    }

    /// A part's name, as its view's title.
    public static func statusTitle(_ part: SetupPart) -> String {
        switch part {
        case .github: "GitHub"
        case .notion: "Notion"
        case .skill: "Shipyard Skill"
        case .cli: "Shipyard CLI"
        }
    }

    /// What a part is for: its view's lead line.
    public static func statusLead(_ part: SetupPart) -> String {
        switch part {
        case .github: "Shipyard lists your pull requests, issues and workflow runs from GitHub."
        case .notion: "Shipyard lists your notes from Notion, read through `ntn`, Notion's CLI."
        case .skill: "The shipyard skill teaches your agents to edit your configuration, ping you and drive the app."
        case .cli: "Your agents run the `shipyard` command to ping you, post notices and drive the app."
        }
    }

    // MARK: - The Shipyard CLI view

    /// The Shipyard CLI view for `state`: the link's path once linked; the
    /// Link button and `command` to run by hand while unlinked; what's in
    /// the way and why shipyard leaves it; why it couldn't, and what to do.
    public static func cliStatus(_ state: CLILink.State, command: String) -> StatusPage {
        let path = "`\(CLILink.displayPath)`"
        var page = StatusPage(title: statusTitle(.cli), lead: statusLead(.cli))
        let tryAgain = StatusPage.Button(title: "Try again", action: .linkCLI)
        switch state {
        case .linked:
            page.status = .init(text: "Linked at \(path).", tone: .success)
            page.detail = "If your shell can't find `shipyard`, add `~/.local/bin` to your `PATH`."
        case .unlinked:
            page.status = .init(text: "Not linked yet.", tone: .neutral)
            page.detail = "Shipyard links its command at \(path), where your agents find it."
            page.primary = .init(title: "Link", action: .linkCLI)
            page.alternative = .init(line: "Or link it yourself in a terminal:", commands: [command])
        case .occupied(let destination):
            let found = destination.map { "\(path) already links to `\($0)`." } ?? "Something else is already at \(path)."
            page.status = .init(text: found, tone: .warning)
            page.detail = "Shipyard never replaces what it didn't make there. To replace it with this app's CLI, run this in a terminal:"
            page.commands = [command]
            page.primary = tryAgain
        case .failed(let reason):
            let sentence = reason.hasSuffix(".") ? reason : reason + "."
            page.status = .init(text: "Couldn't link: \(sentence)", tone: .warning)
            page.detail = "Run this in a terminal instead:"
            page.commands = [command]
            page.primary = tryAgain
        case .translocated:
            page.status = .init(text: "macOS is running Shipyard from a temporary copy, so a link to its CLI would break.", tone: .warning)
            page.detail = "Move Shipyard to Applications, open it from there, then link the CLI here."
        case .missingCLI:
            page.status = .init(text: "This copy of shipyard isn't running from Shipyard.app, which holds the CLI.", tone: .warning)
            page.detail = "Open the installed Shipyard.app to link it."
        }
        return page
    }
}
