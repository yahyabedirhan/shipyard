import LabHost
import SwiftUI

/// `TypeScale`: one family (SF Pro), a few sizes, weights for emphasis,
/// monospaced digits wherever a number sits.
public let variant = LabVariant { TypeSheet() }

struct TypeSheet: View {
    private let styles: [(String, Font, String)] = [
        ("display · 14 semibold", TypeScale.display, "Connect to GitHub"),
        ("title · 13 semibold", TypeScale.title, "@shipyard-lab"),
        ("body · 12", TypeScale.body, "Cache the All tab's rows"),
        ("bodyEmphasis · 12 semibold", TypeScale.bodyEmphasis, "Slow scroll in the All tab"),
        ("button · 12 medium", TypeScale.button, "Harbor  Atlas  Lighthouse"),
        ("meta · 11 monospaced digits", TypeScale.meta, "#214 · harbor · octocat   3h"),
        ("section · 11 semibold", TypeScale.section, "Harbor"),
        ("eyebrow · 10 semibold", TypeScale.eyebrow, "PULL REQUESTS"),
        ("caption · 10.5 monospaced digits", TypeScale.caption, "Last updated 1 min ago"),
        ("captionEmphasis · 10.5 medium", TypeScale.captionEmphasis, "Mark all seen"),
        ("badge · 10 bold monospaced digits", TypeScale.badge, "75"),
        ("code · 12 medium monospaced", TypeScale.code, "shipyard ping --from claude"),
        ("branch · 10.5 medium monospaced", TypeScale.branch, "feat/tabs-strip"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(styles, id: \.0) { name, font, sample in
                HStack(alignment: .firstTextBaseline) {
                    Text(name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 230, alignment: .leading)
                    Text(sample).font(font)
                }
            }
        }
        .padding(24)
        .background(Palette.panel)
    }
}
