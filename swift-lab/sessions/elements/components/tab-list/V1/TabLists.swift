import LabHost
import SwiftUI

/// A project's tab as the tabs layout lists it: its error rows, then its
/// kinds under subheaders, at a light volume, without the strip.
public let variant = LabVariant { TabListSheet() }

struct TabListSheet: View {
    @State private var highlight = RowHighlight()
    private let model = Fixtures.model(.light, runningRuns: false)

    /// Harbor's tab, with one repository that couldn't be fetched.
    private var content: MenuTabContent {
        var content = model.tabContent(for: .project("harbor"))
        content.errors = [MenuErrorRow(RepositoryError(repository: "shipyard-lab/harbor-web", kind: .notFound, message: ""))]
        return content
    }

    var body: some View {
        PanelSurface {
            TabList(content: content, actions: Gallery.actions, highlight: $highlight)
                .rowHighlight(highlight)
        }
        .hoverHelpHost()
        .padding(20)
    }
}
