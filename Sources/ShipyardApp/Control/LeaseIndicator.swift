import Foundation
import Observation
import ShipyardControl

/// What the maintainer sees of the lease: the yellow dot on the menu bar
/// icon and the banner topping the panel, both drawn while an agent holds
/// it. The control server, which owns the lease, writes each change here,
/// and settles it when it runs out, so the dot and the banner follow its
/// start and end with no request and no refresh. The maintainer's clicks
/// never touch the lease: the views only read it.
@MainActor
@Observable
final class LeaseIndicator {
    /// The lease as the control server last left it.
    var lease = ControlLease()
    /// Set by `Screenshotter` while it captures without `--with-indicator`,
    /// so the dot and the banner are left out, and cleared afterwards.
    var isHiddenForCapture = false

    /// The lease to draw at `now`: nil while it's free, or while a capture
    /// hides it.
    func shown(at now: Date) -> AppStatus.Lease? {
        isHiddenForCapture ? nil : lease.status(at: now)
    }

    /// When the lease drawn at `now` ends, which the banner's countdown
    /// ticks by; nil when none is drawn.
    func shownEnd(at now: Date) -> Date? {
        isHiddenForCapture ? nil : lease.current(at: now)?.ends
    }
}
