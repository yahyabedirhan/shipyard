import LabHost
import SwiftUI

/// `CountBadge`: the accent while its rows ask to be seen, muted when
/// they're in view; a click rolls the number, a second mutes it.
public let variant = LabVariant { CountBadgeSheet() }

struct CountBadgeSheet: View {
    @State private var count = 7
    @State private var muted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 18) {
                ForEach([1, 9, 42, 128, 1_204], id: \.self) { value in
                    Specimen(title: "\(value)") { CountBadge(count: value) }
                }
            }
            HStack(spacing: 18) {
                ForEach([1, 9, 42, 128, 1_204], id: \.self) { value in
                    Specimen(title: "muted") { CountBadge(count: value, muted: true) }
                }
            }
            HStack(spacing: 12) {
                CountBadge(count: count, muted: muted)
                Button("+1") { count += 1 }.labID("increment")
                Button(muted ? "Accent" : "Mute") { muted.toggle() }.labID("mute")
            }
        }
        .padding(24)
        .background(Palette.panel)
    }
}
