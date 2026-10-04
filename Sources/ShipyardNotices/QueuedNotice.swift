import Foundation

/// A notice waiting on another machine for the Mac's poll: the notice's
/// own JSON, carried as is, under the id it's stored by and when it was
/// sent. The herdr-shipyard plugin keeps it as opaque JSON with at least
/// an `id` and a `sent` time, and hands it back in its `notices` listing:
///
///     {"id":"5c0f…","notice":{"from":"claude","repository":"owner/shop","title":"Done"},"sent":"2026-10-03T09:41:00Z"}
public struct QueuedNotice: Codable, Equatable, Sendable {
    /// What the plugin stores it under: a new notice under the same id
    /// replaces it there.
    public var id: String
    /// When the agent sent it, so the Mac can drop one that waited too long.
    public var sent: Date
    public var notice: Notice

    public init(id: String, sent: Date, notice: Notice) {
        self.id = id
        self.sent = sent
        self.notice = notice
    }

    /// One line of compact JSON, `sent` in ISO 8601: what the plugin stores.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        // Every field is a string or a date: encoding can't fail.
        return (try? encoder.encode(self)) ?? Data()
    }
}
