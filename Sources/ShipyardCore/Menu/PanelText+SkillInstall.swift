import Foundation

// The skill install card's words (`SkillInstallCard`).
extension PanelText {
    /// What the skill install card says: a title, what happened or what to
    /// do, the command's output, the command to copy, and its button.
    public struct SkillInstall: Equatable, Sendable {
        /// The card's button: Install, Cancel (while running) or Try again.
        public enum Action: Equatable, Sendable {
            case install, cancel, tryAgain
        }

        /// The card's icon: the offer, a success or a problem.
        public enum Tone: Equatable, Sendable {
            case neutral, success, warning
        }

        /// The card's heading.
        public var title: String
        /// What happened or what to do.
        public var message: String
        /// What the command printed, when it's worth showing.
        public var output: String?
        /// `SkillInstaller.command`, with a Copy button, when running it by hand helps.
        public var command: String?
        /// The card's button, if any.
        public var action: Action?
        public var tone: Tone = .neutral
    }

    /// The footer's button for the skill install card.
    public static let installSkill = "Install agent skill…"

    /// The skill install card for `state`.
    public static func skillInstall(_ state: SkillInstallation.State) -> SkillInstall {
        let command = SkillInstaller.command
        switch state {
        case .idle:
            return SkillInstall(
                title: "Install the agent skill",
                message: "It teaches your agents shipyard's configuration file, so you can ask one to watch a repository for you. Shipyard runs this in your login shell:",
                command: command,
                action: .install
            )
        case .running:
            return SkillInstall(
                title: "Installing the agent skill…",
                message: "Running npx in your login shell. It can take a minute.",
                action: .cancel
            )
        case .finished(.installed(let output)):
            return SkillInstall(
                title: "Agent skill installed",
                message: "Your agents can now edit shipyard's configuration file for you.",
                output: output.isEmpty ? nil : output,
                tone: .success
            )
        case .finished(.failed(let output)):
            return SkillInstall(
                title: "Couldn't install the agent skill",
                message: "The command failed. Try again, or run it in a terminal:",
                output: output,
                command: command,
                action: .tryAgain,
                tone: .warning
            )
        case .finished(.npxNotFound(let command)):
            return SkillInstall(
                title: "npx wasn't found",
                message: "Shipyard couldn't find npx (it comes with Node.js) in your login shell. Run this in a terminal instead:",
                command: command,
                action: .tryAgain,
                tone: .warning
            )
        case .timedOut(let seconds):
            return SkillInstall(
                title: "The install took too long",
                message: "It was stopped after \(interval(seconds)). Try again, or run it in a terminal:",
                command: command,
                action: .tryAgain,
                tone: .warning
            )
        }
    }
}
