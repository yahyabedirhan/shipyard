import Foundation
import ShipyardConfig
import ShipyardNotices

/// Decides whether an agent's notice is shown, and how. Pure.
///
/// A notice is filed like a ping: under the one project it names, or under
/// every project that watches its repository (as the configuration names
/// it, or as the app last resolved a group or `owner/*`). It's shown for
/// the first of those whose rules select `agent.notice`; a notice has no
/// GitHub author, so only a rule without `authors` selects one, as for a
/// ping. It's refused, with why, when no project takes it or every one it's
/// filed under leaves `agent.notice` out. Nothing is listed, counted or kept.
public enum NoticeRules {
    /// What clicking a notice's notification hands `Shipyard.openNotification(_:)`:
    /// nothing to open yet, so it does nothing.
    public static let clickURL = URL(string: "shipyard://notice")!

    /// Why a notice the rules show wasn't: macOS would drop it.
    public static let notificationsOff =
        "shipyard's notifications are off in System Settings, so this notice wasn't shown"

    /// How long a notice may wait on another machine for the Mac's poll
    /// (`RemotePingReader.takeNotices`): one older than this when it
    /// arrives is dropped, so stale status never shows.
    public static let maxQueuedAge: TimeInterval = 10 * 60

    /// Whether `queued`, arriving at `now`, waited no longer than
    /// `maxQueuedAge` since it was sent. One sent "later" than `now` (the
    /// machine's clock ahead of the Mac's) is fresh.
    public static func isFresh(_ queued: QueuedNotice, at now: Date) -> Bool {
        now.timeIntervalSince(queued.sent) <= maxQueuedAge
    }

    /// The project `notice` is shown under, or why it isn't shown, filed
    /// against `configuration` and `resolved` (each project's repositories
    /// as last resolved, by name).
    public static func project(
        for notice: Notice,
        configuration: Configuration,
        resolved: [String: [String]]
    ) -> Result<String, Refusal> {
        let names = configuration.projects.map(\.name)
        let filed: [String]
        if let project = notice.project {
            guard names.contains(project) else {
                return .failure(Refusal("no project is named `\(project)`; \(ProjectFiling.listing(names))"))
            }
            filed = [project]
        } else if let slug = notice.repository {
            filed = ProjectFiling.watchers(of: slug, configuration: configuration, resolved: resolved).map(\.project)
            guard !filed.isEmpty else {
                return .failure(Refusal("no project watches `\(slug)`; pass --project <name> to file it under one; \(ProjectFiling.listing(names))"))
            }
        } else {
            return .failure(Refusal("the notice names no project or repository to file it by"))
        }
        let showing = configuration.projects.filter { filed.contains($0.name) && selects(configuration.settings(for: $0)) }
        guard let first = showing.first else {
            let named = filed.map { "`\($0)`" }.joined(separator: ", ")
            return .failure(Refusal("notices are off for \(filed.count == 1 ? "project" : "projects") \(named)"))
        }
        return .success(first.name)
    }

    /// Whether a project's rules (`settings.notifications`, its own list or
    /// the defaults) select an agent's notice.
    static func selects(_ settings: ProjectSettings) -> Bool {
        settings.notifications.contains { $0.event == .agentNotice && $0.authors.isEmpty }
    }

    /// What to post for `notice` under `project`, as `id`: titled with the
    /// project and the notice's title, over its body and sender, as a
    /// ping's is.
    public static func notification(for notice: Notice, project: String, id: String) -> PostedNotification {
        PostedNotification(
            id: id,
            event: .agentNotice,
            project: project,
            headline: notice.title,
            itemTitle: [notice.body, notice.sender.map { "from \($0)" }].compactMap { $0 }.joined(separator: "\n"),
            itemURL: clickURL
        )
    }

    /// Why a notice isn't shown, as the agent reads it after
    /// `shipyard notify: `.
    public struct Refusal: Error, Equatable, Sendable {
        public var message: String
        public init(_ message: String) { self.message = message }
    }
}
