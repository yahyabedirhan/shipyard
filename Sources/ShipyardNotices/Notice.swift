import Foundation
import ShipyardCommand

/// An agent's notice: a disposable status message ("tests running",
/// "done") it posts with `shipyard notify`, which the app shows as a
/// macOS notification when the user's rules let it (`agent.notice`), and
/// never keeps, counts or lists. Not a ping, which waits for the user.
///
/// It's filed like a ping: by the one project it names, or by its
/// repository, which the app files under the projects that watch it. The
/// `shipyard` command fills one of the two.
///
/// Its JSON is the one shape every route carries a notice in, the control
/// socket's request among them:
///
///     {"body":"12 of 40 passed","from":"claude","repository":"owner/shop","title":"Tests running"}
public struct Notice: Codable, Equatable, Sendable {
    /// The one line it shows, after the project's name.
    public var title: String
    /// More than the title fits.
    public var body: String?
    /// Who sent it (`--from`), the agent or its task.
    public var sender: String?
    /// The one project it's filed under (`--project`), by its name.
    public var project: String?
    /// The repository it's filed by (`--repo`, or the checkout's `origin`), as `owner/name`.
    public var repository: String?

    public init(title: String, body: String? = nil, sender: String? = nil, project: String? = nil, repository: String? = nil) {
        self.title = title
        self.body = body
        self.sender = sender
        self.project = project
        self.repository = repository
    }

    enum CodingKeys: String, CodingKey {
        case title, body, project, repository
        case sender = "from"
    }
}

/// What came of a notice, as the agent that sent it learns it.
public enum NoticeVerdict: Equatable, Sendable {
    /// The app posted it.
    case shown
    /// It wasn't shown: why, in one line, such as "notices are off for
    /// project `shop`" or "shipyard isn't running, so this notice wasn't shown".
    case refused(String)
}

/// How a notice reaches the app that shows it, and comes back with its
/// verdict. Each build gives `NoticeCommands` the route it has: on the Mac,
/// the running app's control socket.
public protocol NoticeRoute: Sendable {
    /// Hands `notice` to the app, sent by the command run in `environment`,
    /// and waits for its verdict. A route that can't reach the app refuses,
    /// saying so; it never starts the app.
    func deliver(_ notice: Notice, environment: CommandEnvironment) -> NoticeVerdict
}
