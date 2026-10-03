import Foundation
import ShipyardCommand

/// Where a ping is filed: the one thing the two `shipyard` builds do
/// differently (ADR 0006). The executable picks one when it assembles its
/// commands, and `PingCommand` and `HerdrEvent` file through it, so no ping
/// code asks the platform. On a machine without the app it's `Unfiled`; on
/// the Mac it files against `config.toml`.
public protocol PingFiling: Sendable {
    /// The projects a ping for `target` goes under and the repository it
    /// keeps, or the refusal the command returns (exit 1). `whenNoProject`
    /// says what a ping no project takes comes to.
    func file(_ target: FilingTarget, whenNoProject: NoProject) -> Result<Filing, CommandResult>
    /// When a ping sent or replaced at `sent` stops being live; `nil`: never.
    func expiry(sentAt sent: Date) -> Date?
    /// The action a ping gets when the agent gives none; `nil`: none.
    func defaultAction(_ environment: CommandEnvironment) -> PingAction?
}

/// What a ping names to be filed by.
public enum FilingTarget: Equatable, Sendable {
    /// `--project <name>`.
    case project(String)
    /// `--repo <owner/name>`, else the working folder's `origin`.
    case repository(String)
    /// Neither: why there's no repository, as the refusal says it.
    case none(why: String)
}

/// What a ping no project takes comes to.
public enum NoProject: Equatable, Sendable {
    /// It's refused, saying why: `shipyard ping`, whose agent waits for the answer.
    case refuse
    /// It's saved under no project, with the repository it named:
    /// `shipyard herdr-event`, whose refusal would reach no one.
    case keepUnfiled
}

/// Where a ping is filed.
public struct Filing: Equatable, Sendable {
    /// The names of the projects it's listed under; none when it isn't filed.
    public var projects: [String]
    /// The repository (`owner/name`) it keeps; `nil` for `--project`, or
    /// when it names none.
    public var repository: String?

    public init(projects: [String], repository: String?) {
        self.projects = projects
        self.repository = repository
    }
}

/// The filing on a machine without the app (ADR 0005): there's no app to
/// file a ping for, so it's kept as the agent sent it (`--project`'s name,
/// whatever projects exist, else its repository, else none) and the Mac
/// files it when it reads the machine's list. Nothing is refused. No one
/// marks it seen there, so it expires a day after its sending or its last
/// replace; sent from a Herdr pane without an action, it focuses that pane.
public struct Unfiled: PingFiling {
    public init() {}

    public func file(_ target: FilingTarget, whenNoProject: NoProject) -> Result<Filing, CommandResult> {
        switch target {
        case .project(let name): .success(Filing(projects: [name], repository: nil))
        case .repository(let slug): .success(Filing(projects: [], repository: slug))
        case .none: .success(Filing(projects: [], repository: nil))
        }
    }

    public func expiry(sentAt sent: Date) -> Date? {
        sent.addingTimeInterval(PingCommand.lifetimeWithoutTheApp)
    }

    /// The agent's Herdr pane (`HERDR_PANE_ID`), so a click on the Mac can
    /// focus it.
    public func defaultAction(_ environment: CommandEnvironment) -> PingAction? {
        guard let pane = environment.variables[PingCommand.herdrPaneVariable]?.trimmingCharacters(in: .whitespaces),
              !pane.isEmpty
        else { return nil }
        return .herdr(pane)
    }
}
