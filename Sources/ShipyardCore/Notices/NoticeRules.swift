import Foundation
import ShipyardConfig
import ShipyardNotices
import ShipyardPings

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
    /// What clicking a notice's notification hands `Shipyard.openNotification(_:)`
    /// when the notice has no click action: it does nothing. A click or a
    /// button with an action hands this URL with the action in its query
    /// (`clickURL(for:in:machine:)`).
    public static let clickURL = URL(string: "shipyard://notice")!

    /// The notification id a notice is shown under: `agent.notice <id>`,
    /// its `--id` or a fresh one (`fresh`), so a notice with the id of
    /// one still shown replaces it, and a withdrawal finds it.
    public static func notificationID(_ id: String) -> String {
        "\(EventKind.agentNotice.rawValue) \(id)"
    }

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
    /// ping's is, with every option the notice gives. Its thread is
    /// `agent.notice <thread>` when it names one, its project's otherwise.
    /// A click, and each button, hands `Shipyard.openNotification(_:)` its
    /// action (`clickURL(for:in:machine:)`).
    /// A notice from a remote machine (`machine`, its Herdr label) carries
    /// it in a Herdr action's click.
    public static func notification(for notice: Notice, project: String, id: String, machine: String? = nil) -> PostedNotification {
        PostedNotification(
            id: id,
            event: .agentNotice,
            project: project,
            headline: notice.title,
            itemTitle: [notice.body, notice.sender.map { "from \($0)" }].compactMap { $0 }.joined(separator: "\n"),
            itemURL: notice.action.map { clickURL(for: $0, in: notice, machine: machine) } ?? clickURL,
            subtitle: notice.subtitle,
            image: notice.image,
            sound: notice.sound ?? .default,
            thread: notice.thread.map { "\(EventKind.agentNotice.rawValue) \($0)" },
            level: notice.level,
            buttons: (notice.buttons ?? []).map { PostedNotification.Button(label: $0.label, url: clickURL(for: $0.action, in: notice, machine: machine)) }
        )
    }

    /// What a notice's click or button runs: its action, and, for a Herdr
    /// one, where the notice was sent from, as a ping's click runs it.
    public struct Click: Codable, Equatable, Sendable {
        public var action: PingAction
        /// The terminal app it was sent from (`Notice.terminal`).
        public var terminal: String?
        /// The named Herdr session it was sent from (`Notice.herdrSession`).
        public var herdrSession: String?
        /// The Herdr label of the remote machine it came from, whose pane a
        /// Herdr action focuses; `nil` for one sent on the Mac.
        public var machine: String?
    }

    /// The URL that runs `action` of `notice` when its notification is
    /// clicked or a button pressed: `clickURL` with the `Click` as JSON in
    /// its `click` query item. The notice isn't kept, so the notification
    /// carries what its click does.
    static func clickURL(for action: PingAction, in notice: Notice, machine: String?) -> URL {
        let herdr = if case .herdr = action { true } else { false }
        let click = Click(
            action: action,
            terminal: herdr ? notice.terminal : nil,
            herdrSession: herdr ? notice.herdrSession : nil,
            machine: herdr ? machine : nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Encoding strings and a URL can't fail.
        let json = String(decoding: try! encoder.encode(click), as: UTF8.self)
        // ASCII only: `alphanumerics` would leave other letters bare.
        let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var components = URLComponents(url: clickURL, resolvingAgainstBaseURL: false)!
        components.percentEncodedQuery = "click=" + json.addingPercentEncoding(withAllowedCharacters: unreserved)!
        return components.url!
    }

    /// The click a notice's notification or button URL runs, `nil` for
    /// one that runs nothing (`clickURL` alone) or isn't a notice's.
    public static func click(from url: URL) -> Click? {
        guard isNoticeURL(url),
              let json = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "click" })?.value
        else { return nil }
        return try? JSONDecoder().decode(Click.self, from: Data(json.utf8))
    }

    /// Whether `url` is a notice's notification or button URL.
    public static func isNoticeURL(_ url: URL) -> Bool {
        url.scheme == clickURL.scheme && url.host == clickURL.host
    }

    /// Why a notice isn't shown, as the agent reads it after
    /// `shipyard notify: `.
    public struct Refusal: Error, Equatable, Sendable {
        public var message: String
        public init(_ message: String) { self.message = message }
    }
}
