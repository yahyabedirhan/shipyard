import Foundation
import Observation
import ShipyardControl

/// What the maintainer sees of the lease: the yellow dot on the menu bar
/// icon and the banner topping the panel, both drawn while an agent holds
/// it. The control server, which owns the lease, writes each change here,
/// and settles it when it runs out, so the dot and the banner follow its
/// start and end with no request and no refresh. Of the maintainer's
/// clicks, only the banner's Stop and a quiet line's Allow reach the lease,
/// through `AppServices` to the control server; the views only read it.
@MainActor
@Observable
final class LeaseIndicator {
    /// The lease as the control server last left it.
    var lease = ControlLease()
    /// How many captures without `--with-indicator` are under way, each
    /// counted by `Screenshotter` from its start to its end. Captures can
    /// overlap (one holder's parallel commands), so a count, not a flag:
    /// the last one to end shows the dot and the banner again.
    private(set) var capturesHiding = 0

    /// Whether a capture hides the dot and the banner now.
    var isHiddenForCapture: Bool { capturesHiding > 0 }

    /// A capture that leaves the indicator out starts.
    func hideForCapture() {
        capturesHiding += 1
    }

    /// A capture that left the indicator out ends; the indicator is drawn
    /// again once no other is under way.
    func showAfterCapture() {
        capturesHiding = max(0, capturesHiding - 1)
    }

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

    /// The holders the maintainer stopped, still barred at `now`, a quiet
    /// line each under the banner; none while a capture hides the indicator.
    func stopped(at now: Date) -> [ControlLease.Bar] {
        isHiddenForCapture ? [] : lease.stopped(at: now)
    }
}
