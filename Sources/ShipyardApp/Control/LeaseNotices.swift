import ShipyardControl
import ShipyardCore

/// What the user hears of the lease: the control server tells each
/// transition, and a start or an end becomes a `ControlNotice` the core
/// posts when the top-level rules select it. A renewal makes none, so one
/// lease makes one start and one end; a relaunch's handover isn't a
/// transition at all.
extension ControlNotice {
    init?(_ transition: ControlLease.Transition) {
        switch transition {
        case .started(let holder):
            self = .started(agent: holder.name, place: holder.place)
        case .renewed:
            return nil
        case .ended(let holder, let ending):
            self = .ended(agent: holder.name, reason: Reason(ending))
        }
    }
}

extension ControlNotice.Reason {
    /// Why a lease ended, as the notification words it.
    init(_ ending: ControlLease.Ending) {
        switch ending {
        // Run out after the holder's last request, or at the cap.
        case .expired, .capped: self = .ranOut
        case .released: self = .released
        case .stopped: self = .stopped
        }
    }
}
