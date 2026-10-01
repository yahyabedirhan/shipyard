import Foundation

// The CLI link card's words (`CLILinkCard`).
extension PanelText {
    /// What the CLI link card says: a title, what happened or what to do,
    /// the command to copy, and its button.
    public struct CLILinkCard: Equatable, Sendable {
        /// The card's button: Link, or Try again after it couldn't.
        public enum Action: Equatable, Sendable {
            case link, tryAgain
        }

        /// The card's heading.
        public var title: String
        /// What happened or what to do.
        public var message: String
        /// `CLILink.command`, with a Copy button, when running it by hand helps.
        public var command: String?
        /// The card's button, if any.
        public var action: Action?
        /// The card's icon: the offer, a success or a problem (the skill card's tones).
        public var tone: SkillInstall.Tone = .neutral
    }

    /// The gear menu's item for the CLI link card.
    public static let linkCLI = "Link shipyard CLI…"

    /// The CLI link card for `state`, offering `command` when it helps.
    public static func cliLink(_ state: CLILink.State, command: String) -> CLILinkCard {
        let path = CLILink.displayPath
        switch state {
        case .unlinked:
            return CLILinkCard(
                title: "Link the shipyard CLI",
                message: "Your agents send you pings with the shipyard command. Shipyard links it into ~/.local/bin, as this would:",
                command: command,
                action: .link
            )
        case .linked:
            return CLILinkCard(
                title: "shipyard CLI linked",
                message: "\(path) runs this app's CLI. If your shell can't find shipyard, add ~/.local/bin to your PATH.",
                tone: .success
            )
        case .occupied(let destination):
            let found = destination.map { "\(path) already links to \($0)." } ?? "Something else is already at \(path)."
            return CLILinkCard(
                title: "Couldn't link the shipyard CLI",
                message: "\(found) Shipyard leaves it alone. To replace it with this app's CLI, run this in a terminal:",
                command: command,
                action: .tryAgain,
                tone: .warning
            )
        case .failed(let reason):
            let sentence = reason.hasSuffix(".") ? reason : reason + "."
            return CLILinkCard(
                title: "Couldn't link the shipyard CLI",
                message: "\(sentence) Run this in a terminal instead:",
                command: command,
                action: .tryAgain,
                tone: .warning
            )
        case .translocated:
            return CLILinkCard(
                title: "Move Shipyard to Applications",
                message: "macOS is running Shipyard from a temporary copy, so a link to its CLI would break. Move Shipyard to Applications first, then link the CLI.",
                tone: .warning
            )
        case .missingCLI:
            return CLILinkCard(
                title: "No CLI to link",
                message: "This copy of shipyard isn't running from Shipyard.app, which holds the CLI. Open the installed app to link it.",
                tone: .warning
            )
        }
    }
}
