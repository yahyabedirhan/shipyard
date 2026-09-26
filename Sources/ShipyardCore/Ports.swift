import Foundation

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
    /// The project the event was notified for.
    public var project: String
    /// The title text, for example "New PR #107".
    public var headline: String
    /// The item's title, for example "Fix checkout totals".
    public var itemTitle: String
    /// The item the notification is about. Clicking the notification hands
    /// it to `Shipyard.openNotification(_:)`, which opens the item and marks
    /// it seen.
    public var itemURL: URL

    public init(id: String, event: EventKind, project: String, headline: String, itemTitle: String, itemURL: URL) {
        self.id = id
        self.event = event
        self.project = project
        self.headline = headline
        self.itemTitle = itemTitle
        self.itemURL = itemURL
    }

    /// The notification's title: "e-commerce · New PR #107".
    public var title: String { "\(project) · \(headline)" }
    /// The notification's body: the item's title.
    public var body: String { itemTitle }
}

/// Posts notifications. The app wraps the system notification center, asks
/// for permission on the first post (not at launch), and routes a click to
/// `Shipyard.openNotification(_:)` with the notification's `itemURL`.
public protocol Notifying: Sendable {
    func post(_ notification: PostedNotification) async
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

/// Waits the given number of seconds; throws `CancellationError` when
/// cancelled. The device flow and the skill install wait with it, so tests
/// can pass one that returns at once.
public typealias Sleep = @Sendable (TimeInterval) async throws -> Void

/// Real waiting, for the app.
public let systemSleep: Sleep = { seconds in
    try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
}

/// Opens an item's page on GitHub in the user's browser.
public protocol URLOpening: Sendable {
    func open(_ url: URL)
}

/// Starts shipyard when the user logs in. The app registers or removes the
/// app as a login item (`SMAppService.mainApp`); `Shipyard` tells it which,
/// following `launch-at-login`.
public protocol LoginItem: Sendable {
    /// Registers shipyard as a login item when `enabled`, removes it
    /// otherwise. Telling it what it already is changes nothing.
    func setEnabled(_ enabled: Bool)
}
