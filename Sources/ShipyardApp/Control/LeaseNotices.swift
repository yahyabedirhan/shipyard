import ShipyardControl
import ShipyardCore

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
    init(_ ending: ControlLease.Ending) {
        switch ending {
        case .expired, .capped: self = .ranOut
        case .released: self = .released
        case .stopped: self = .stopped
        }
    }
}
