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

    /// Why a remote ping's action last failed, for its row: the Mac's
    /// record, which the machine's list never carries. It holds for one
    /// sending of the ping only (`sending`, compared with
    /// `Ping.isSameSending`), so a ping replaced on its machine, or sent
    /// anew under its id, starts without it, as a local one does. Seen is
    /// kept apart, in the app state (`RemotePingMarks`).
    private struct Failure: Equatable, Sendable {
        var sending: Ping
        var reason: String
    }

    /// By the ping's URL.
    private var failures: [URL: Failure] = [:]

    /// Every machine's pings, machine by machine, each with why its
    /// action last failed, if it did.
    public var pings: [Ping] { machines.flatMap(\.pings).map(withFailure) }

    /// `ping` with the failure recorded on its sending.
    private func withFailure(_ ping: Ping) -> Ping {
        guard let failure = failures[ping.item.url], failure.sending.isSameSending(as: ping) else { return ping }
        var ping = ping
        ping.failure = failure.reason
        return ping
    }

    /// The sending of `ping` a machine lists now; `nil` when none lists
    /// it, or lists another sending under its URL.
    private func listed(_ ping: Ping) -> Ping? {
        machines.lazy.flatMap(\.pings).first { $0.item.url == ping.item.url && $0.isSameSending(as: ping) }
    }

    /// Records why `ping`'s action failed, for its row. A sending no
    /// machine lists any more (withdrawn, replaced or sent anew since) is
    /// left out.
    public mutating func recordFailure(_ ping: Ping, reason: String) {
        guard let sending = listed(ping) else { return }
        failures[sending.item.url] = Failure(sending: sending, reason: reason)
    }

    /// Clears the failure recorded on `ping`'s sending: its action worked,
    /// or the user saw it.
    public mutating func clearFailure(_ ping: Ping) {
        guard let failure = failures[ping.item.url], failure.sending.isSameSending(as: ping) else { return }
        failures[ping.item.url] = nil
    }

    /// Forgets the failures of sendings no machine lists any more.
    private mutating func pruneFailures() {
        failures = failures.filter { listed($0.value.sending) != nil }
    }

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
        pruneFailures()
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
            pruneFailures()
        case .failure(let failure):
            machines[index].failure = failure.reason
        }
    }
}
