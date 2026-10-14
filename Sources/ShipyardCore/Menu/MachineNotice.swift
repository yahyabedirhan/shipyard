import Foundation

/// The panel's one quiet line about a remote machine (`[remote] machines`):
/// why its latest poll failed (its last pings staying listed, if it ever answered), or that
/// its list stopped early. A machine whose latest poll was good and whole
/// has none, so its next good poll clears the line by itself.
public struct MachineNotice: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        case unreachable(String, answered: Bool)
        case truncated(listed: Int)
    }

    /// The machine's label.
    public var machine: String
    public var kind: Kind

    public var id: String { machine }

    public init(machine: String, kind: Kind) {
        self.machine = machine
        self.kind = kind
    }

    /// One notice per machine with something to say, in configuration
    /// order: a failure first, since a failed poll's list may be old.
    public static func notices(_ remote: RemoteMachines) -> [MachineNotice] {
        remote.machines.compactMap { machine in
            if let failure = machine.failure {
                return MachineNotice(machine: machine.label, kind: .unreachable(failure, answered: machine.answered != nil))
            }
            if machine.truncated {
                return MachineNotice(machine: machine.label, kind: .truncated(listed: machine.pings.count))
            }
            return nil
        }
    }
}
