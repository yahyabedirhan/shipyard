import LabHost
import SwiftUI

/// shipyard's logo (`LogoBadge`, from `Logo` and `Sailboat.path`) at the
/// sizes it ships, and the menu bar's template mark on a light and a dark bar.
public let variant = LabVariant { LogoSheet() }

struct LogoSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .bottom, spacing: 28) {
                ForEach([128, 64, 32, 16] as [CGFloat], id: \.self) { side in
                    Specimen(title: "\(Int(side)) pt") { LogoBadge(side: side) }
                }
            }
            HStack(spacing: 20) {
                Specimen(title: "menu bar, light") { menuBar(dark: false) }
                Specimen(title: "menu bar, dark") { menuBar(dark: true) }
                Specimen(title: "figure") {
                    Image(nsImage: SailboatImage.menuBar(side: 56))
                        .renderingMode(.template)
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(28)
    }

    private func menuBar(dark: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
            Image(nsImage: SailboatImage.menuBar())
                .renderingMode(.template)
            Text("3").font(.system(size: 13, weight: .medium)).monospacedDigit()
            Image(systemName: "battery.75percent")
        }
        .font(.system(size: 13))
        .foregroundStyle(dark ? Color.white : Color.black)
        .padding(.horizontal, 14)
        .frame(height: 24)
        .background(dark ? Color(white: 0.16) : Color(white: 0.93), in: RoundedRectangle(cornerRadius: 6))
    }
}
