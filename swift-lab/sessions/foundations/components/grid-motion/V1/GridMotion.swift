import LabHost
import SwiftUI

/// `Grid`'s spacing and radii, drawn to scale, and `Motion`'s springs,
/// each replayed by a click.
public let variant = LabVariant { GridMotionSheet() }

struct GridMotionSheet: View {
    @State private var on = false
    private let lengths: [(String, CGFloat)] = [
        ("panelWidth", Grid.panelWidth), ("titleBarHeight", Grid.titleBarHeight), ("headerHeight", Grid.headerHeight),
        ("rowHeight", Grid.rowHeight), ("gutter", Grid.gutter), ("dotColumn", Grid.dotColumn), ("iconColumn", Grid.iconColumn),
        ("inset", Grid.inset), ("maxTabTitleWidth", Grid.maxTabTitleWidth), ("tabFade", Grid.tabFade), ("tabSlide", Grid.tabSlide),
    ]
    private let springs: [(String, Animation)] = [
        ("collapse", Motion.collapse), ("count", Motion.count), ("tint", Motion.tint), ("banner", Motion.banner),
        ("seen", Motion.seen), ("hover", Motion.hover), ("highlight", Motion.highlight), ("tab", Motion.tab),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 32) {
            Specimen(title: "Grid (points, to scale up to 140)") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(lengths, id: \.0) { name, length in
                        HStack(spacing: 8) {
                            Text("\(name) \(Int(length))").font(TypeScale.meta).frame(width: 150, alignment: .leading)
                            Capsule().fill(Palette.accent.opacity(0.7)).frame(width: min(length, 140), height: 6)
                        }
                    }
                    HStack(spacing: 10) {
                        ForEach([("small", Grid.smallRadius), ("card", Grid.radius)], id: \.0) { name, radius in
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(Palette.border)
                                .frame(width: 60, height: 30)
                                .overlay(Text("\(name) \(Int(radius))").font(TypeScale.caption))
                        }
                    }
                    .padding(.top, 6)
                }
            }
            Specimen(title: "Motion (click to replay)") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(springs, id: \.0) { name, animation in
                        HStack(spacing: 8) {
                            Text(name).font(TypeScale.meta).frame(width: 70, alignment: .leading)
                            ZStack(alignment: on ? .trailing : .leading) {
                                Capsule().fill(Palette.track).frame(width: 160, height: 14)
                                Circle().fill(Palette.accent).frame(width: 14, height: 14)
                            }
                            .animation(animation, value: on)
                        }
                    }
                    Button(on ? "Back" : "Play") { on.toggle() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .labID("play")
                }
            }
        }
        .padding(24)
        .background(Palette.panel)
    }
}
