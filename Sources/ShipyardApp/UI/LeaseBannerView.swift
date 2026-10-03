import ShipyardControl
import ShipyardCore
import SwiftUI

/// The banner topping the panel while an agent holds the lease: the
/// agent's logo, "Claude Code in shop is using shipyard", the time left and
/// how many wait, in `LeaseBanner`'s words, and Stop, which takes shipyard
/// back. Stop is the banner's only way into the lease.
struct LeaseBannerView: View {
    let lease: AppStatus.Lease
    /// Takes shipyard back from the holder (`ControlServer.stopLease`).
    let stop: () -> Void

    var body: some View {
        let banner = LeaseBanner(lease)
        HStack(spacing: 8) {
            LeaseAgentMark(agent: KnownAgent(sender: banner.agent))
            Text(banner.headline)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
                .truncationMode(.middle)
            HStack(spacing: 4) {
                Text("·")
                Text(banner.timeLeft)
                    .contentTransition(.numericText(countsDown: true))
                if let waiting = banner.waiting {
                    Text("·")
                    Text(waiting)
                }
            }
            .font(TypeScale.meta)
            .foregroundStyle(.secondary)
            .fixedSize()
            .layoutPriority(1)
            Spacer(minLength: 0)
            Button(LeaseBanner.stop, action: stop)
                .buttonStyle(TextButtonStyle(tint: Palette.red))
                .fixedSize()
                .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).fill(Palette.lease.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(Palette.lease.opacity(0.35), lineWidth: 0.5))
        .animation(Motion.count, value: banner.timeLeft)
        // One element reading the banner's line, with Stop as its action.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(banner.text)
        .accessibilityAction(named: LeaseBanner.stop, stop)
    }
}

/// The holder's mark in the banner: a known agent's logo, as a ping's row
/// shows it, or a generic terminal for an agent shipyard doesn't know.
private struct LeaseAgentMark: View {
    let agent: KnownAgent?

    private static let size: CGFloat = 16

    var body: some View {
        if let agent {
            AgentMarkView(agent: agent, size: Self.size)
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: Self.size, height: Self.size)
                .background(RoundedRectangle(cornerRadius: Self.size * 0.22, style: .continuous).fill(Palette.fill))
                .accessibilityHidden(true)
        }
    }
}
