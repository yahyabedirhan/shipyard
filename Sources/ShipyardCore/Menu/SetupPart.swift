/// One part of shipyard the user sets up, which the settings menu lists by
/// name and opens in its status view: GitHub, Notion through `ntn`, the
/// agent skill and the `shipyard` CLI, in the menu's order.
public enum SetupPart: String, CaseIterable, Equatable, Sendable {
    case github, notion, skill, cli

    /// The name `shipyard panel view` takes and `shipyard app status`
    /// reports: `github`, `notion`, `skill`, `cli`.
    public var commandName: String { rawValue }

    /// The part `name` names, as `shipyard panel view` takes it, in any
    /// case; nil for `projects`, no view. Refused, naming the views, when
    /// it names none.
    public static func named(_ name: String) throws(PanelRefusal) -> SetupPart? {
        let lowered = name.lowercased()
        if lowered == projectsName { return nil }
        if let part = SetupPart(rawValue: lowered) { return part }
        let names = allCases.map { "`\($0.commandName)`" }.joined(separator: ", ")
        throw PanelRefusal("no view is named `\(name)`; the views are \(names), or `\(projectsName)` for the projects")
    }

    /// What `shipyard panel view` takes, and `app status` reports, for the
    /// projects: no status view open.
    public static let projectsName = "projects"
}

/// Whether each part is set up, as the settings menu marks it: a check mark
/// only beside a part that is, and no mark otherwise.
public struct SetupStatus: Equatable, Sendable {
    /// The CLI link's state: set up only when `linked`.
    public var cli: CLILink.State
    /// Whether shipyard is signed in to GitHub (`Shipyard.gitHubConnection`).
    public var github: Bool

    /// Whether Notion is connected and ntn works (`Shipyard.notionIsSetUp`).
    public var notion: Bool

    /// Whether the agent skill is installed (`SkillDetector`).
    public var skill: Bool

    public init(cli: CLILink.State, github: Bool = false, notion: Bool = false, skill: Bool = false) {
        self.cli = cli
        self.github = github
        self.notion = notion
        self.skill = skill
    }

    public func isSetUp(_ part: SetupPart) -> Bool {
        switch part {
        case .cli: cli == .linked
        case .github: github
        case .notion: notion
        case .skill: skill
        }
    }
}
