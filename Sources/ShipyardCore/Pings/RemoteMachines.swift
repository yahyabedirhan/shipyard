import Foundation

/// What the Mac knows of each remote machine (`[remote] machines`): the
/// pings its last good poll listed and how its latest poll went. Pure
/// state: `Shipyard` polls each machine through `RemotePingReader` and
/// records the result here, and lists `pings` beside the local ones.
///
/// A poll that fails keeps the machine's last pings, so a machine that
/// restarts or a network that sleeps doesn't empty the menu; its
/// `failure` says why until a poll succeeds again.
public struct RemoteMachines: Equatable, Sendable {
    /// One machine, by its Herdr label.
    public struct Machine: Equatable, Sendable {
        public var label: String
        /// The pings its last good poll listed, newest first, each with
        /// `machine` set to `label`; none before one succeeded.
        public var pings: [Ping]
        /// Whether that list stopped early, so the machine holds more.
        public var truncated: Bool
        /// Why its latest poll failed; `nil` before any poll and after a good one.
        public var failure: String?
        /// When a poll last succeeded; `nil` before one did.
        public var answered: Date?

        public init(label: String, pings: [Ping] = [], truncated: Bool = false, failure: String? = nil, answered: Date? = nil) {
            self.label = label
            self.pings = pings
            self.truncated = truncated
            self.failure = failure
            self.answered = answered
        }
    }

    /// In the configuration's order, which is the order of their sections.
    public private(set) var machines: [Machine] = []

    public init(machines: [Machine] = []) {
        self.machines = machines
    }

    /// The configured labels, in order.
    public var labels: [String] { machines.map(\.label) }

    /// Every machine's pings, machine by machine.
    public var pings: [Ping] { machines.flatMap(\.pings) }

    /// The machine `label` names, if it's configured.
    public func machine(_ label: String) -> Machine? {
        machines.first { $0.label == label }
    }

    /// Follows the configuration's `labels`: a machine still listed keeps
    /// what it knows, a new one starts empty, and a removed one is
    /// forgotten with its pings.
    public mutating func follow(_ labels: [String]) {
        let known = Dictionary(machines.map { ($0.label, $0) }, uniquingKeysWith: { first, _ in first })
        machines = labels.map { known[$0] ?? Machine(label: $0) }
    }

    /// Records how polling `label` went at `now`: its list replaces the
    /// pings it had, and clears its failure; a failure keeps its pings.
    /// A machine no longer configured (removed while it was polled) is
    /// left out.
    public mutating func record(_ result: Result<PingList, RemotePingReader.Failure>, for label: String, at now: Date) {
        guard let index = machines.firstIndex(where: { $0.label == label }) else { return }
        switch result {
        case .success(let list):
            machines[index].pings = list.pings
            machines[index].truncated = list.truncated
            machines[index].failure = nil
            machines[index].answered = now
        case .failure(let failure):
            machines[index].failure = failure.reason
        }
    }
}
