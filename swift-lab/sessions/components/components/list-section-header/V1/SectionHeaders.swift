import LabHost
import SwiftUI

/// The list layout's pinned project header: fold chevron, title, the
/// kinds' count chips (accent where rows need attention), Mark all seen,
/// the new-note icon and the open-repository icon.
public let variant = LabVariant { SectionHeaderSheet() }

struct SectionHeaderSheet: View {
    private let model = Fixtures.model(.light, layout: .list)

    /// The light volume's projects, the third one collapsed.
    private var sections: [MenuSection] {
        model.sections.enumerated().map { index, section in
            var section = section
            section.isCollapsed = index == 2
            return section
        }
    }

    var body: some View {
        PanelSurface {
            VStack(spacing: 0) {
                ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                    ListSectionHeader(section: section, isHighlighted: index == 1, actions: Gallery.actions)
                    Hairline()
                }
            }
        }
        .hoverHelpHost()
        .padding(20)
    }
}
