import Foundation

/// Decides which events are notified. Pure.
///
/// A project's rules are its own `notifications` list when it has one, else
/// `[[defaults.notifications]]` (`ProjectSettings.notifications` is already
/// the right one). An event is notified when a rule names it and the rule's
/// authors cover the item's author. It's asked only for items the project
/// lists (`Listing`): what the filters leave out is never notified, and a
/// rule's `authors` can only narrow that further (ADR 0003).
public enum NotificationRules {
    /// `viewer` is the signed-in login, which `me` matches.
    public static func shouldNotify(_ event: Event, settings: ProjectSettings, viewer: String? = nil) -> Bool {
        settings.notifications.contains { rule in
            rule.event == event.kind && rule.covers(event.item, viewer: viewer)
        }
    }

    /// What to post for `event`, in the project it's notified for.
    public static func notification(for event: Event) -> PostedNotification {
        PostedNotification(
            id: event.id,
            event: event.kind,
            project: event.project,
            headline: event.headline,
            // A run's title is its workflow; its branch says which change it tested.
            itemTitle: event.item.branch.map { "\(event.item.title) · \($0)" } ?? event.item.title,
            itemURL: event.item.url
        )
    }
}

/// The events already notified, or passed over because no rule selected
/// them, so none is notified twice. Kept apart from the seen records: seeing
/// an item doesn't make its events notifiable again, and an event nobody
/// clicked isn't notified again. App state.
public struct NotifiedEvents: Equatable, Sendable {
    /// One item's recorded events, and when a refresh last listed the item.
    public struct Record: Codable, Equatable, Sendable {
        /// `Event.kind` plus its occurrence, e.g. `pr.opened` or
        /// `pr.checks_failed <fingerprint>`.
        public var events: Set<String>
        /// Bumped at most once a day, like `Attention.SeenRecord.present`.
        public var present: Date

        public init(events: Set<String>, present: Date) {
            self.events = events
            self.present = present
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(events.sorted(), forKey: .events)
            try container.encode(present, forKey: .present)
        }
    }

    /// Records by item id (its URL).
    public private(set) var records: [String: Record]

    public init(records: [String: Record] = [:]) {
        self.records = records
    }

    public func contains(_ event: Event) -> Bool {
        records[event.item.id]?.events.contains(Self.key(event)) ?? false
    }

    /// Records `event` as handled at `now`.
    public mutating func insert(_ event: Event, at now: Date) {
        records[event.item.id, default: Record(events: [], present: now)].events.insert(Self.key(event))
    }

    /// Notes which items a refresh still knows and drops the records of items
    /// gone for longer than `Attention.retention`, so an item that leaves the
    /// list and comes back (reopened after it fell out of the closed list)
    /// isn't announced as new. Returns whether anything changed.
    @discardableResult
    public mutating func prune(present ids: some Sequence<String>, at now: Date) -> Bool {
        var changed = false
        for id in ids {
            guard let record = records[id], now.timeIntervalSince(record.present) >= Attention.presenceResolution else { continue }
            records[id]?.present = now
            changed = true
        }
        let cutoff = now.addingTimeInterval(-Attention.retention)
        let before = records.count
        records = records.filter { $0.value.present >= cutoff }
        return changed || records.count != before
    }

    private static func key(_ event: Event) -> String {
        event.occurrence.isEmpty ? event.kind.rawValue : "\(event.kind.rawValue) \(event.occurrence)"
    }
}
