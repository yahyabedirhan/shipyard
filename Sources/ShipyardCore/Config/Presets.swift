import Foundation

/// A ready-made configuration for one main use of shipyard: a whole
/// commented file to start from. Onboarding offers them (`Preset.all`, in
/// the order it lists them), and the skill's `presets.md` shows the same
/// files, so a user's agent can start from one too.
public struct Preset: Hashable, Sendable, Identifiable {
    /// What onboarding asks for before the preset is written.
    public enum Asks: Hashable, Sendable {
        /// Repositories to watch, one project each.
        case repositories
        /// Every repository the account owns (`owned`), or picked ones.
        case ownedOrRepositories
        /// Nothing: the preset watches no repositories of its own.
        case nothing
    }

    /// The preset's name, kebab-case, as the skill and the user say it.
    public let name: String
    /// Its title in onboarding.
    public let title: String
    /// One sentence on what it lists.
    public let summary: String
    public let asks: Asks

    public var id: String { name }

    /// Everything you and your agents open, in your repositories: one
    /// project per repository, issues shown, grouped by kind.
    public static let myAgents = Preset(
        name: "my-agents",
        title: "My agents",
        summary: "The pull requests and issues you and your agents open, one project per repository.",
        asks: .repositories
    )

    /// What other people open on your repositories, bots left out, and the
    /// pull requests anywhere waiting on your review.
    public static let incomingContributions = Preset(
        name: "incoming-contributions",
        title: "Incoming contributions",
        summary: "The pull requests and issues other people open on your repositories, and the pull requests waiting on your review.",
        asks: .ownedOrRepositories
    )

    /// Only the pull requests waiting on your review, in any repository.
    public static let reviewQueue = Preset(
        name: "review-queue",
        title: "Review queue",
        summary: "Only the pull requests waiting on your review, in any repository.",
        asks: .nothing
    )

    /// Every preset, in the order onboarding lists them.
    public static let all: [Preset] = [myAgents, incomingContributions, reviewQueue]

    /// The preset with this name, if there is one.
    public static func named(_ name: String) -> Preset? {
        all.first { $0.name == name }
    }

    /// The name of the project `incoming-contributions` watches your
    /// repositories in, when onboarding doesn't name it.
    public static let incomingProjectName = "Incoming"

    /// The whole configuration file, commented, with `projects` as its
    /// `[[projects]]` blocks:
    /// - `my-agents` writes each of `projects` as it is.
    /// - `incoming-contributions` writes each of `projects` as it is, or,
    ///   when there are none, one project "Incoming" watching `owned`;
    ///   then its "Review requests" project.
    /// - `review-queue` ignores `projects`: its one project is `anywhere`.
    public func text(projects: [NewProject] = []) -> String {
        switch name {
        case Preset.incomingContributions.name:
            let incoming = projects.isEmpty
                ? [NewProject(name: Preset.incomingProjectName, repositories: [RepositoryGroup.owned.rawValue])]
                : projects
            return Preset.incomingContributionsText(incoming)
        case Preset.reviewQueue.name:
            return Preset.reviewQueueText
        default:
            return Preset.myAgentsText(projects)
        }
    }

    // MARK: - The files

    private static func myAgentsText(_ projects: [NewProject]) -> String {
        """
        #:schema \(Configuration.schemaURL)
        # shipyard configuration, started from the my-agents preset: the pull
        # requests and issues you and your agents open, one project per
        # repository.
        \(editedBy)
        version = \(Configuration.supportedVersion)

        # Group each project's items by kind: pull requests, then issues.
        [defaults]
        group-by = "kind"

        # List issues too, not only pull requests, in every project.
        [defaults.issues]
        show = true

        # Projects: one [[projects]] block per repository. Add more at the end.

        """ + blocks(projects)
    }

    private static func incomingContributionsText(_ projects: [NewProject]) -> String {
        """
        #:schema \(Configuration.schemaURL)
        # shipyard configuration, started from the incoming-contributions preset:
        # the pull requests and issues other people open on your repositories,
        # bots left out, and the pull requests waiting on your review anywhere.
        \(editedBy)
        version = \(Configuration.supportedVersion)

        # Group each project's items by repository, each under a subheader.
        [defaults]
        group-by = "repository"
        subsections = true

        # List other people's pull requests: yours (and your agents') and
        # bots' are hidden.
        [defaults.pull-requests]
        authors = { hide = ["me", "bots"] }

        # List other people's issues too, hiding the same authors.
        [defaults.issues]
        show = true
        authors = { hide = ["me", "bots"] }

        # Notify when someone else opens a pull request or an issue.
        [[defaults.notifications]]
        event = "pr.opened"
        authors = ["others"]

        [[defaults.notifications]]
        event = "issue.opened"
        authors = ["others"]

        # Projects: one [[projects]] block each. owned is every repository
        # your account owns, including ones you create later.

        """ + blocks(projects) + """

        # The pull requests waiting on your review, or a team's you're in, in
        # any repository. anywhere lists only those, so this project shows no
        # issues, and it notifies each new request instead.
        [[projects]]
        name = "Review requests"
        repositories = ["anywhere"]
        pull-requests = { review-requested = true }
        issues = { show = false }
        notifications = [
          { event = "pr.review_requested" },
        ]

        """
    }

    private static let reviewQueueText = """
        #:schema \(Configuration.schemaURL)
        # shipyard configuration, started from the review-queue preset: only the
        # pull requests waiting on your review, in any repository.
        \(editedBy)
        version = \(Configuration.supportedVersion)

        # The pull requests waiting on your review, or a team's you're in, in
        # any repository, grouped by repository under subheaders. Each new
        # request notifies.
        [[projects]]
        name = "Review queue"
        repositories = ["anywhere"]
        pull-requests = { review-requested = true }
        group-by = "repository"
        subsections = true
        notifications = [
          { event = "pr.review_requested" },
        ]

        """

    /// What every preset's opening comment says after its summary.
    private static let editedBy = """
        # You and your agents edit this file; shipyard applies changes live.
        # Every key is optional; keys, defaults and events are in the schema above.
        """

    /// `projects` as plain `[[projects]]` blocks, a blank line between each.
    private static func blocks(_ projects: [NewProject]) -> String {
        projects.map { project in
            let repositories = project.repositories.map(Configuration.tomlString).joined(separator: ", ")
            return """
                [[projects]]
                name = \(Configuration.tomlString(project.name))
                repositories = [\(repositories)]

                """
        }.joined(separator: "\n")
    }
}
