import Foundation
import Observation
import ShipyardControl
import ShipyardCore

/// What the maintainer sees of the lease: the yellow dot on the menu bar
/// icon and the banners topping the panel, drawn while an agent holds it
/// or a stopped one is barred. The control server, which owns the lease,
/// writes each change here (`update(_:at:)`), and settles it when it runs
/// out, so the dot and the banners follow its start and end with no
/// request and no refresh. The panel's lease banners are the core's
/// (`Shipyard.lease`, handed on through `onBannersChange`), so they snooze
/// like the others; the dot reads the lease here, and a snooze never hides
/// it. Of the maintainer's clicks, only the banner's Stop and a quiet
/// line's Allow reach the lease, through `AppServices` to the control
/// server; the views only read it.
@MainActor
@Observable
final class LeaseIndicator {
    /// The lease as the control server last left it.
    private(set) var lease = ControlLease()
    /// Called with the lease's banners each time the control server writes
    /// the lease: the app hands them to `Shipyard.lease`.
    @ObservationIgnored var onBannersChange: (@MainActor (PanelBanner.Lease) -> Void)?
    /// How many captures without `--with-indicator` are under way, each
    /// counted by `Screenshotter` from its start to its end. Captures can
    /// overlap (one holder's parallel commands), so a count, not a flag:
    /// the last one to end shows the dot and the banner again.
    private(set) var capturesHiding = 0

    /// The control server's lease after a change, at `now`: kept for the
    /// dot and the banner's countdown, and handed on as the panel's banners.
    func update(_ lease: ControlLease, at now: Date) {
        if self.lease != lease { self.lease = lease }
        onBannersChange?(Self.banners(of: lease, at: now))
    }

    /// The lease's banners at `now`: the lease held, told from the next by
    /// its holder and when it was taken, and each stopped holder's quiet line.
    static func banners(of lease: ControlLease, at now: Date) -> PanelBanner.Lease {
        PanelBanner.Lease(
            held: lease.current(at: now).flatMap { term in
                lease.status(at: now).map { status in
                    PanelBanner.Lease.Held(
                        term: "\(term.holder.key)@\(term.taken.timeIntervalSince1970)",
                        headline: LeaseBanner(status).headline
                    )
                }
            },
            stopped: lease.stopped(at: now).map {
                PanelBanner.Lease.Stopped(key: $0.holder.key, text: LeaseBanner.tookBack(from: $0.holder.name))
            }
        )
    }

    /// Whether a capture hides the dot and the banners now.
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
}
