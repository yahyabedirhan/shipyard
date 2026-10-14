import Foundation
import Observation
import ShipyardControl
import ShipyardCore

@MainActor
@Observable
final class LeaseIndicator {
    private(set) var lease = ControlLease()
    @ObservationIgnored var onBannersChange: (@MainActor (PanelBanner.Lease) -> Void)?
    private(set) var capturesHiding = 0

    func update(_ lease: ControlLease, at now: Date) {
        if self.lease != lease { self.lease = lease }
        onBannersChange?(Self.banners(of: lease, at: now))
    }

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

    var isHiddenForCapture: Bool { capturesHiding > 0 }

    func hideForCapture() {
        capturesHiding += 1
    }

    func showAfterCapture() {
        capturesHiding = max(0, capturesHiding - 1)
    }

    func shown(at now: Date) -> AppStatus.Lease? {
        isHiddenForCapture ? nil : lease.status(at: now)
    }

    func shownEnd(at now: Date) -> Date? {
        isHiddenForCapture ? nil : lease.current(at: now)?.ends
    }
}
