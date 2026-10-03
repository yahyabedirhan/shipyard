import Foundation

/// The numbers the Mac gives pings (`#3`), kept in the app state: one
/// sequence per section, a project or a remote machine's own section of
/// unfiled pings, like issues in a repository. A ping takes its section's
/// next number the first time the Mac lists it there, and keeps it while
/// it stays, through every replace, since a ping is known by its URL
/// (`shipyard://ping/<id>`, `shipyard://ping/<machine>/<id>`). A ping filed
/// under two projects has a number in each.
///
/// When a ping leaves a section (withdrawn, expired, seen past its
/// `seen-window`, dismissed, or filed elsewhere), its number there is
/// retired: each section remembers the last number it gave, so one never
/// comes back, even once every ping has left.
public struct PingNumbers: Codable, Equatable, Sendable {
    /// One section's sequence.
    public struct Sequence: Codable, Equatable, Sendable {
        /// The last number given; 0 before any.
        public var last: Int
        /// The number of each ping listed there now, by its URL.
        public var pings: [String: Int]

        public init(last: Int = 0, pings: [String: Int] = [:]) {
            self.last = last
            self.pings = pings
        }
    }

    /// By section name: a project's, or a machine's label.
    public var sections: [String: Sequence]

    public init(sections: [String: Sequence] = [:]) {
        self.sections = sections
    }

    /// The number `url`'s ping has in `section`; `nil` when it has none there.
    public func number(of url: String, in section: String) -> Int? {
        sections[section]?.pings[url]
    }

    /// Numbers `filed`, the pings each section lists now: a ping new to
    /// its section takes the next number there, the new ones of one call
    /// oldest sent first (then by URL). A number whose ping a section no
    /// longer holds is retired when `mayRetire` says its absence counts
    /// (a remote machine not heard from yet may still list it); a section
    /// whose pings all left keeps its last number.
    public mutating func number(_ filed: [String: [Ping]], mayRetire: (String) -> Bool = { _ in true }) {
        for (name, sequence) in sections {
            let present = Set((filed[name] ?? []).map(\.item.id))
            sections[name]?.pings = sequence.pings.filter { present.contains($0.key) || !mayRetire($0.key) }
        }
        for (name, pings) in filed {
            var sequence = sections[name] ?? Sequence()
            let new = pings
                .filter { sequence.pings[$0.item.id] == nil }
                .sorted { ($0.sent, $0.item.id) < ($1.sent, $1.item.id) }
            for ping in new where sequence.pings[ping.item.id] == nil {
                sequence.last += 1
                sequence.pings[ping.item.id] = sequence.last
            }
            sections[name] = sequence
        }
    }
}
