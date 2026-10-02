import Foundation

/// What the user did to remote pings (seen, dismissed), kept on the Mac in
/// the app state: nothing is written back to a machine, since a plugin
/// action can't carry an argument there. Keyed by the remote ping's URL
/// (`shipyard://ping/<machine>/<id>`), each mark holds the instance it
/// was made for, so a ping withdrawn and sent anew under its id starts
/// over.
///
/// - Seen behaves as for a local ping: it holds for the sending the user
///   saw, so a replace (same instance, new content) needs attention again,
///   and a seen ping leaves its listing after the `seen-window`.
/// - Dismissed hides the ping until its machine stops listing that
///   instance, replaced or not.
///
/// A mark for a ping no machine lists any more is pruned (`prune(listed:)`).
public struct RemotePingMarks: Equatable, Sendable {
    public struct Mark: Codable, Equatable, Sendable {
        /// The instance of the ping it was made for (`Ping.instance`).
        public var instance: String?
        /// When the user saw it; `nil` while unseen.
        public var seen: Date?
        /// The sending the user saw, as its machine listed it: a replace
        /// since is unseen again.
        public var seenSending: Ping?
        /// Whether the user dismissed it (✕ or ⌫).
        public var dismissed: Bool

        public init(instance: String?, seen: Date? = nil, seenSending: Ping? = nil, dismissed: Bool = false) {
            self.instance = instance
            self.seen = seen
            self.seenSending = seenSending
            self.dismissed = dismissed
        }
    }

    /// By the remote ping's URL.
    public var marks: [String: Mark]

    public init(marks: [String: Mark] = [:]) {
        self.marks = marks
    }

    /// The mark for `ping`'s instance, if any: a mark made for another
    /// instance under its URL isn't this ping's.
    private func mark(for ping: Ping) -> Mark? {
        guard let mark = marks[ping.item.id], mark.instance == ping.instance else { return nil }
        return mark
    }

    /// Records `ping` (the sending the user saw) as seen at `now`. One
    /// already seen keeps its first time.
    public mutating func markSeen(_ ping: Ping, at now: Date) {
        var mark = self.mark(for: ping) ?? Mark(instance: ping.instance)
        if let sending = mark.seenSending, Self.isSameSending(sending, ping) { return }
        mark.seen = now
        mark.seenSending = ping
        marks[ping.item.id] = mark
    }

    /// Hides `ping` until its machine stops listing its instance.
    public mutating func dismiss(_ ping: Ping) {
        var mark = self.mark(for: ping) ?? Mark(instance: ping.instance)
        mark.dismissed = true
        marks[ping.item.id] = mark
    }

    /// `pings` as the user's marks leave them: the dismissed left out,
    /// and each seen sending with its `seen` time.
    public func apply(to pings: [Ping]) -> [Ping] {
        guard !marks.isEmpty else { return pings }
        return pings.compactMap { ping in
            guard let mark = mark(for: ping) else { return ping }
            if mark.dismissed { return nil }
            guard let seen = mark.seen, let sending = mark.seenSending, Self.isSameSending(sending, ping) else { return ping }
            var marked = ping
            marked.seen = seen
            return marked
        }
    }

    /// Drops the marks of pings no machine lists any more: not in
    /// `listed`, by URL and instance. The marks of the machines in
    /// `unknown` (configured, but not yet heard from since the app
    /// started) are kept as they are; so are those the machines in
    /// `truncated` (whose list stopped early) leave out, which may be
    /// past its end.
    public mutating func prune(listed: [Ping], keeping unknown: Set<String> = [], truncated: Set<String> = []) {
        let current = Dictionary(listed.map { ($0.item.id, $0.instance) }, uniquingKeysWith: { first, _ in first })
        marks = marks.filter { url, mark in
            if let machine = URL(string: url).flatMap(Ping.remote(from:))?.machine {
                if unknown.contains(machine) { return true }
                if truncated.contains(machine) && current[url] == nil { return true }
            }
            return current[url].map { $0 == mark.instance } ?? false
        }
    }

    /// Whether two listings of a remote ping are the same sending, whatever
    /// the machine's label (not kept in the stored copy).
    private static func isSameSending(_ first: Ping, _ second: Ping) -> Bool {
        var first = first, second = second
        first.machine = nil
        second.machine = nil
        return first.isSameSending(as: second)
    }
}
