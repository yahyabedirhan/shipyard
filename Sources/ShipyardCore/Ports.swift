import Foundation
import ShipyardConfig
import ShipyardNotices
import ShipyardPings

// What the app plugs into the core. Each port wraps an Apple-only service
// (Keychain, notifications, the system clock, NSWorkspace) behind a small
// protocol, so every rule in ShipyardCore builds and tests on Linux. The app
// target supplies the real adapters; tests use in-memory doubles.

/// Keeps the one GitHub token shipyard signed in with. The app stores it in
/// the login Keychain.
public protocol TokenStore: Sendable {
    /// The stored token, or `nil` when there is none.
    func token() throws -> String?
    /// Stores `token`, replacing any earlier one.
    func save(_ token: String) throws
    /// Removes the stored token. Deleting when there is none is not an error.
    func delete() throws
}

/// A macOS notification shipyard posts for an event its rules select, such
/// as "e-commerce · New PR #107" over "Fix checkout totals".
public struct PostedNotification: Equatable, Hashable, Sendable {
    /// The event's id, unique per event, so the system never shows the same
    /// event twice.
    public var id: String
    public var event: EventKind
    /// The project the event was notified for; empty for one about no
    /// project (app control's, `ControlNotice`).
    public var project: String
    /// The title text, for example "New PR #107".
    public var headline: String
    /// The item's title, for example "Fix checkout totals"; for a ping, its
    /// body and sender (`Ping.notificationBody`), since its title is the headline.
    public var itemTitle: String
    /// The item the notification is about. Clicking the notification hands
    /// it to `Shipyard.openNotification(_:)`, which opens the item and marks
    /// it seen.
    public var itemURL: URL
    /// A line between the title and the body; `nil` for none. An agent's
    /// notice's `--subtitle`.
    public var subtitle: String?
    /// A picture shown with it; `nil` for none.
    public var image: NoticeImage?
    /// What it sounds like: the default sound unless an agent's notice says.
    public var sound: NoticeSound
    /// The key Notification Center stacks it under; `nil` stacks it with
    /// its project's (`project`).
    public var thread: String?
    /// How much it interrupts; `nil` is macOS's default, `active`.
    public var level: NoticeLevel?
    /// Its buttons, in order, each handing its own URL to
    /// `Shipyard.openNotification(_:)` when pressed, as a click hands
    /// `itemURL`; none for most.
    public var buttons: [Button]

    public init(
        id: String,
        event: EventKind,
        project: String,
        headline: String,
        itemTitle: String,
        itemURL: URL,
        subtitle: String? = nil,
        image: NoticeImage? = nil,
        sound: NoticeSound = .default,
        thread: String? = nil,
        level: NoticeLevel? = nil,
        buttons: [Button] = []
    ) {
        self.id = id
        self.event = event
        self.project = project
        self.headline = headline
        self.itemTitle = itemTitle
        self.itemURL = itemURL
        self.subtitle = subtitle
        self.image = image
        self.sound = sound
        self.thread = thread
        self.level = level
        self.buttons = buttons
    }

    /// A notification's button: its label, and the URL pressing it hands
    /// `Shipyard.openNotification(_:)`.
    public struct Button: Equatable, Hashable, Sendable {
        public var label: String
        public var url: URL

        public init(label: String, url: URL) {
            self.label = label
            self.url = url
        }
    }

    /// The notification's title: "e-commerce · New PR #107", or the
    /// headline alone when it's about no project.
    public var title: String { project.isEmpty ? headline : "\(project) · \(headline)" }
    /// The notification's body: the item's title (a ping's body and sender).
    public var body: String { itemTitle }
}

/// Posts notifications. The app wraps the system notification center, asks
/// for permission on the first post (not at launch), and routes a click to
/// `Shipyard.openNotification(_:)` with the notification's `itemURL`.
public protocol Notifying: Sendable {
    func post(_ notification: PostedNotification) async
    /// Takes the notification `id` (`PostedNotification.id`) out of
    /// Notification Center, as when its ping is withdrawn or dismissed. One
    /// that was never posted, or is gone already, is no error.
    func removeDelivered(id: String) async
    /// Whether a notification posted now could show: false when the user
    /// turned shipyard's notifications off. Never asked yet counts as
    /// could, since the first post asks. An agent's notice asks it first,
    /// so its verdict is never `shown` for a notice macOS would drop.
    func canShow() async -> Bool
}

/// Tells the core what time it is, so tests can fix and move time.
/// (Not named `Clock`, which the standard library already uses.)
public protocol WallClock: Sendable {
    var now: Date { get }
}

/// The real time, for the app.
public struct SystemClock: WallClock {
    public init() {}
    public var now: Date { Date() }
}

/// What running a ping's action came to.
public enum ActionOutcome: Equatable, Sendable {
    case done
    /// It didn't work: a reason short enough for the ping's row, such as
    /// "No app", and the whole of it for its hover card, such as "No app
    /// named Claude" (`nil` when the short one says it all).
    case failed(String, detail: String? = nil)
}

/// Takes the user where shipyard sends them: opens an item's page on
/// GitHub in the browser, and runs a ping's action (opens its link, brings
/// its app forward), saying whether that worked. The app does both through
/// `NSWorkspace`. A Herdr action (`.herdr`) isn't sent here: `Shipyard`
/// focuses Herdr through `HerdrFocus`, then sends `[herdr] terminal` as an
/// `.app` action.
public protocol ActionRunning: Sendable {
    /// Opens `url` (a GitHub page), without waiting to see whether it opened.
    func open(_ url: URL)
    /// Runs a ping's action and reports how it went.
    func run(_ action: PingAction) async -> ActionOutcome
}

/// Starts shipyard when the user logs in. The app registers or removes the
/// app as a login item (`SMAppService.mainApp`); `Shipyard` tells it which,
/// following `launch-at-login`.
public protocol LoginItem: Sendable {
    /// Registers shipyard as a login item when `enabled`, removes it
    /// otherwise. Telling it what it already is changes nothing.
    func setEnabled(_ enabled: Bool)
}
