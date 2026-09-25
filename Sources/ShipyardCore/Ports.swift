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

/// A macOS notification shipyard posts for an event its rules select.
public struct PostedNotification: Equatable, Hashable, Sendable {
    /// Unique per event, so the system never shows the same event twice.
    public var id: String
    /// For example "e-commerce · New PR #107".
    public var title: String
    /// For example the item's title.
    public var body: String
    /// The item the notification is about; clicking it opens this and marks it seen.
    public var itemURL: URL

    public init(id: String, title: String, body: String, itemURL: URL) {
        self.id = id
        self.title = title
        self.body = body
        self.itemURL = itemURL
    }
}

/// Posts notifications. The app wraps the system notification center and
/// asks for permission on the first post, not at launch.
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

/// Opens an item's page on GitHub in the user's browser.
public protocol URLOpening: Sendable {
    func open(_ url: URL)
}
