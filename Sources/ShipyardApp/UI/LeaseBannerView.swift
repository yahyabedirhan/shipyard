import ShipyardControl
import ShipyardCore
import SwiftUI

struct LeaseBannerView: View {
    let lease: AppStatus.Lease
    let stop: () -> Void
    var dismiss: (() -> Void)?

    var body: some View {
        let banner = LeaseBanner(lease)
        HStack(spacing: 8) {
            LeaseAgentMark(agent: KnownAgent(sender: banner.agent))
            VStack(alignment: .leading, spacing: 1) {
                Text(banner.headline)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ThemeColor.textPrimary.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail = banner.detail {
                    Text(detail)
                        .font(TypeScale.meta)
                        .foregroundStyle(ThemeColor.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .contentTransition(.identity)
                }
            }
            Spacer(minLength: 0)
            Text(banner.timeLeft)
                .font(TypeScale.meta)
                .monospacedDigit()
                .foregroundStyle(ThemeColor.textSecondary)
                .contentTransition(.numericText(countsDown: true))
                .fixedSize()
            Button(LeaseBanner.stop, action: stop)
                .buttonStyle(TextButtonStyle(tint: ThemeColor.failure))
                .fixedSize()
                .layoutPriority(1)
            if let dismiss {
                BannerDismissButton(dismiss: dismiss)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).fill(ThemeColor.lease.opacity(0.14)))
        .overlay(RoundedRectangle(cornerRadius: Grid.radius, style: .continuous).strokeBorder(ThemeColor.lease.opacity(0.35), lineWidth: 0.5))
        .animation(Motion.count, value: banner.timeLeft)
        .help(banner.help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(banner.text)
        .accessibilityAction(named: LeaseBanner.stop, stop)
        .accessibilityAction(named: PanelText.dismissBanner) { dismiss?() }
    }
}

private struct LeaseAgentMark: View {
    let agent: KnownAgent?

    private static let size: CGFloat = 16

    var body: some View {
        if let agent {
            AgentMarkView(agent: agent, size: Self.size)
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ThemeColor.textSecondary)
                .frame(width: Self.size, height: Self.size)
                .background(RoundedRectangle(cornerRadius: Self.size * 0.22, style: .continuous).fill(ThemeColor.field))
                .accessibilityHidden(true)
        }
    }
}
